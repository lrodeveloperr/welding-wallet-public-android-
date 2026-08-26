package com.goodusestudios.weldinggaswallet.backend

import com.goodusestudios.weldinggaswallet.backend.domain.*
import com.goodusestudios.weldinggaswallet.backend.storage.AtomicFileWalletRepository
import com.goodusestudios.weldinggaswallet.backend.storage.JsonWalletCodec
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.Instant

class StorageCodecTest {
    @get:Rule val folder = TemporaryFolder()

    @Test
    fun atomicRepositoryPersistsCommittedState() = runBlocking {
        val codec = JsonWalletCodec()
        val repo = AtomicFileWalletRepository(folder.root, codec, initialLocale = "en", initialCurrencyCode = "USD")
        repo.transact { current ->
            val supplier = Supplier("supplier-1", "Local Gas", Instant.EPOCH, Instant.EPOCH)
            TransactionOutcome(current.next(suppliers = listOf(supplier)), Unit)
        }
        val reopened = AtomicFileWalletRepository(folder.root, codec, initialLocale = "en", initialCurrencyCode = "USD")
        assertEquals("Local Gas", reopened.read().suppliers.single().name)
    }

    @Test
    fun backupExcludesDevicePhotoUriAndEntitlement() {
        val codec = JsonWalletCodec()
        val now = Instant.parse("2027-01-01T00:00:00Z")
        val state = WalletData.empty("en", "USD").copy(
            cylinders = listOf(
                Cylinder(
                    id = "c1", nickname = "Argon", gasType = "Argon",
                    relationship = RelationshipType.owned, lifecycle = CylinderLifecycle.active,
                    createdAt = now, updatedAt = now, localPhotoUri = "content://private/photo",
                ),
            ),
            entitlementCache = Entitlement(
                AccessTier.pro, EntitlementSource.googlePlaySubscription,
                validUntil = Instant.parse("2030-01-01T00:00:00Z"), willRenew = true,
            ),
        )
        val encoded = codec.encode(state, now)
        assertFalse(encoded.contains("content://private/photo"))
        val imported = codec.decode(encoded)
        assertNull(imported.cylinders.single().localPhotoUri)
        assertEquals(Entitlement.Free, imported.entitlementCache)
    }

    @Test
    fun privateCodecRoundTripsCurrentSchema() {
        val codec = JsonWalletCodec()
        val now = Instant.parse("2027-01-01T00:00:00Z")
        val state = WalletData.empty("fr", "EUR").copy(
            revision = 4,
            suppliers = listOf(Supplier("s1", "Gaz", now, now)),
            cylinders = listOf(Cylinder("c1", "Atelier", "Argon", RelationshipType.leased, CylinderLifecycle.active, now, now, supplierId = "s1")),
        )
        val decoded = codec.decodePrivate(codec.encodePrivate(state))
        assertEquals(4, decoded.revision)
        assertEquals("Gaz", decoded.suppliers.single().name)
        assertEquals("s1", decoded.cylinders.single().supplierId)
    }
}
