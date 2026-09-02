package com.goodusestudios.weldinggaswallet.backend

import com.goodusestudios.weldinggaswallet.backend.domain.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class WalletEngineTest {
    @Test
    fun freeTierFourthCurrentCylinderRequiresPaywall() = runBlocking {
        val h = Harness()
        repeat(3) { assertTrue(h.engine.addOrGate(h.draft("Bottle ${it + 1}")) is CylinderAdded) }
        val result = h.engine.addOrGate(h.draft("Bottle 4"))
        assertTrue(result is AddRequiresPaywall)
        assertEquals(3, h.repo.read().cylinders.size)
        assertNotNull(h.repo.read().pendingDraft)
    }

    @Test
    fun nonCurrentCylinderIsReadOnlyForFreeTier() = runBlocking {
        val h = Harness()
        val cylinder = (h.engine.addOrGate(h.draft("Returned bottle")) as CylinderAdded).cylinder
        h.engine.markReturned(cylinder.id)
        val decision = h.engine.canEditCylinder(cylinder.id)
        assertTrue(decision is ReadOnly)
        assertEquals("Cylinder is not current, read-only for free tier.", (decision as ReadOnly).reason)
    }

    @Test
    fun proUserCanEditNonCurrentCylinder() = runBlocking {
        val h = Harness()
        val cylinder = (h.engine.addOrGate(h.draft("Pro bottle")) as CylinderAdded).cylinder
        h.engine.markReturned(cylinder.id)
        h.repo.state = h.repo.state.copy(
            entitlementCache = Entitlement(
                tier = AccessTier.pro,
                source = EntitlementSource.googlePlaySubscription,
                validUntil = Instant.parse("2030-01-01T00:00:00Z"),
            ),
        )
        assertEquals(Editable, h.engine.canEditCylinder(cylinder.id))
    }

    @Test
    fun unknownSupplierCannotBeAttachedToCylinder() = runBlocking {
        val h = Harness()
        try {
            h.engine.addOrGate(h.draft("Orphan", supplierId = "missing"))
            fail("Expected supplier validation failure")
        } catch (error: IllegalArgumentException) {
            assertTrue(error.message.orEmpty().contains("Supplier does not exist"))
        }
        assertTrue(h.repo.read().cylinders.isEmpty())
    }

    @Test
    fun deleteReminderCancelsSystemWorkAndAppendsAuditEvent() = runBlocking {
        val h = Harness()
        val cylinder = (h.engine.addOrGate(h.draft("Reminder bottle")) as CylinderAdded).cylinder
        h.engine.setRemindersEnabled(true)
        val reminder = h.engine.createReminder(
            cylinderId = cylinder.id,
            kind = ReminderKind.refill,
            title = "Check refill",
            dueAt = Instant.parse("2028-01-01T00:00:00Z"),
        ).reminder

        h.engine.deleteReminder(reminder.id)

        val state = h.repo.read()
        assertFalse(state.reminders.any { it.id == reminder.id })
        assertTrue(reminder.id in h.scheduler.cancelledIds)
        val event = state.events.last { it.type == CylinderEventType.reminderDeleted }
        assertEquals(cylinder.id, event.cylinderId)
        assertEquals(reminder.id, event.metadata["reminderId"])
    }

    @Test
    fun statusIsFastAndRefillOrExchangeResetsReady() = runBlocking {
        val h = Harness()
        val cylinder = (
            h.engine.addOrGate(
                AddCylinderDraft(
                    nickname = "",
                    gasType = "Argon 75/25",
                    relationship = RelationshipType.owned,
                    capacityValue = 80.0,
                    capacityUnit = "ft3",
                ),
            ) as CylinderAdded
        ).cylinder
        assertEquals("Argon 75/25 · 80 ft³", cylinder.nickname)
        assertEquals(CylinderState.ready, cylinder.state)

        h.engine.changeCylinderState(cylinder.id, CylinderState.low)
        assertEquals(CylinderState.low, h.repo.read().cylinders.single().state)
        assertEquals(CylinderEventType.stateChanged, h.repo.read().events.last().type)

        h.engine.recordRefill(
            cylinderId = cylinder.id,
            occurredAt = Instant.parse("2027-01-02T00:00:00Z"),
        )
        assertEquals(CylinderState.ready, h.repo.read().cylinders.single().state)

        h.engine.changeCylinderState(cylinder.id, CylinderState.empty)
        h.engine.recordExchange(
            cylinderId = cylinder.id,
            occurredAt = Instant.parse("2027-01-03T00:00:00Z"),
        )
        val exchanged = h.repo.read().cylinders.single()
        assertEquals(CylinderState.ready, exchanged.state)
        assertEquals(CylinderLifecycle.active, exchanged.lifecycle)
        assertEquals(CylinderEventType.exchange, h.repo.read().events.last().type)
    }

    @Test
    fun downgradeClearsLegacyFlagOnNonCurrentCylinder() = runBlocking {
        val h = Harness()
        val cylinder = (h.engine.addOrGate(h.draft("Legacy flag")) as CylinderAdded).cylinder
        h.repo.state = h.repo.state.copy(
            cylinders = h.repo.state.cylinders.map {
                if (it.id == cylinder.id) it.copy(
                    lifecycle = CylinderLifecycle.archived,
                    isFreeEditableSelection = true,
                ) else it
            },
        )
        h.engine.enforceDowngradeIfNeeded()
        assertFalse(h.repo.read().cylinders.single().isFreeEditableSelection)
    }
}

private class Harness {
    val repo = MemoryRepo()
    val scheduler = FakeScheduler()
    private var id = 0
    val engine = WeldingGasWalletEngine(
        repo = repo,
        billing = FakeBilling,
        scheduler = scheduler,
        ids = IdFactory { "id-${++id}" },
        clock = Clock { Instant.parse("2027-01-01T00:00:00Z") },
        backupCodec = NoopBackupCodec,
    )

    fun draft(name: String, supplierId: String? = null) = AddCylinderDraft(
        nickname = name,
        gasType = "Argon 75/25",
        relationship = RelationshipType.owned,
        supplierId = supplierId,
    )
}

private class MemoryRepo : AtomicWalletRepository {
    var state: WalletData = WalletData.empty("en", "USD")
    override suspend fun read(): WalletData = state
    override suspend fun <T> transact(expectedRevision: Int?, mutation: (WalletData) -> TransactionOutcome<T>): T {
        if (expectedRevision != null && expectedRevision != state.revision) {
            throw WalletConflictException(expectedRevision, state.revision)
        }
        val out = mutation(state)
        state = out.state
        return out.value
    }
    override suspend fun replaceFromBackup(imported: WalletData, expectedRevision: Int): WalletData {
        if (expectedRevision != state.revision) throw WalletConflictException(expectedRevision, state.revision)
        state = imported.copy(revision = state.revision + 1)
        return state
    }
}

private class FakeScheduler : ReminderScheduler {
    val cancelledIds = mutableListOf<String>()
    override suspend fun schedule(reminder: Reminder) = Unit
    override suspend fun cancel(reminder: Reminder) { cancelledIds += reminder.id }
    override suspend fun dismiss(reminder: Reminder) = Unit
    override suspend fun cancelAll() = Unit
}

private object FakeBilling : StoreBillingGateway {
    override suspend fun loadProducts(): List<StoreProduct> = emptyList()
    override suspend fun purchaseVerified(productId: String): Entitlement = Entitlement.Free
    override suspend fun restoreOrRefreshVerified(): Entitlement = Entitlement.Free
    override suspend fun openSubscriptionManagement() = Unit
}

private object NoopBackupCodec : WalletBackupCodec {
    override fun encode(state: WalletData, exportedAt: Instant): String = "{}"
    override fun decode(encoded: String): WalletData = WalletData.empty()
}
