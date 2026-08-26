package com.goodusestudios.weldinggaswallet.backend.storage

import com.goodusestudios.weldinggaswallet.backend.domain.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

class StorageCorruptionException(
    val quarantinedPath: String,
    cause: Throwable,
) : IllegalStateException("Wallet storage was quarantined at $quarantinedPath: ${cause.message}", cause)

class AtomicFileWalletRepository(
    private val directory: File,
    private val codec: JsonWalletCodec,
    private val fileName: String = "welding-gas-wallet-v2.json",
    private val initialLocale: String = "en",
    private val initialCurrencyCode: String? = null,
) : AtomicWalletRepository,
    SessionEntitlementTrust,
    ResidualWalletDataPurger,
    CorruptionRecoveryRepository {

    private val mutex = Mutex()
    @Volatile
    private var sessionEntitlement: Entitlement = Entitlement.Free

    private val file get() = File(directory, fileName)
    private val previous get() = File(directory, "$fileName.previous")
    private val recovery get() = File(directory, "$fileName.recovery")
    private val temporary get() = File(directory, "$fileName.tmp")
    private val corruptionMarker get() = File(directory, "$fileName.corruption-marker")

    override suspend fun read(): WalletData = mutex.withLock {
        withContext(Dispatchers.IO) { readUnlocked() }
    }

    override fun acceptStoreVerifiedEntitlement(entitlement: Entitlement) {
        sessionEntitlement = entitlement
    }

    override suspend fun <T> transact(
        expectedRevision: Int?,
        mutation: (WalletData) -> TransactionOutcome<T>,
    ): T = mutex.withLock {
        withContext(Dispatchers.IO) {
            val current = readUnlocked()
            if (expectedRevision != null && current.revision != expectedRevision) {
                throw WalletConflictException(expectedRevision, current.revision)
            }
            val outcome = mutation(current)
            if (outcome.state !== current) {
                check(outcome.state.revision > current.revision) {
                    "A persisted mutation must advance the revision."
                }
                writeUnlocked(outcome.state)
            }
            outcome.value
        }
    }

    override suspend fun replaceFromBackup(
        imported: WalletData,
        expectedRevision: Int,
    ): WalletData = mutex.withLock {
        withContext(Dispatchers.IO) {
            val current = readUnlocked()
            if (current.revision != expectedRevision) {
                throw WalletConflictException(expectedRevision, current.revision)
            }
            val replacement = WalletData(
                schemaVersion = WALLET_SCHEMA_VERSION,
                revision = current.revision + 1,
                settings = imported.settings,
                suppliers = imported.suppliers,
                cylinders = imported.cylinders,
                events = imported.events,
                reminders = imported.reminders,
                pendingDraft = imported.pendingDraft,
                freeEditableSelection = imported.freeEditableSelection,
                entitlementCache = current.entitlementCache,
            )
            writeUnlocked(replacement)
            replacement
        }
    }

    override suspend fun replaceCorruptStore(validatedBackup: WalletData): WalletData = mutex.withLock {
        withContext(Dispatchers.IO) {
            sessionEntitlement = Entitlement.Free
            val recovered = WalletData(
                schemaVersion = WALLET_SCHEMA_VERSION,
                revision = 1,
                settings = validatedBackup.settings,
                suppliers = validatedBackup.suppliers,
                cylinders = validatedBackup.cylinders,
                events = validatedBackup.events,
                reminders = validatedBackup.reminders.map { reminder ->
                    reminder.copy(
                        delivery = if (reminder.completed) {
                            ReminderDelivery.needsCancellation
                        } else {
                            ReminderDelivery.needsScheduling
                        },
                    )
                },
                pendingDraft = validatedBackup.pendingDraft,
                freeEditableSelection = validatedBackup.freeEditableSelection,
                entitlementCache = Entitlement.Free,
            )
            prepareExplicitRecoveryUnlocked()
            writeUnlocked(recovered)
            purgeResidualUnlocked()
            recovered
        }
    }

    override suspend fun clearCorruptStore(confirmed: Boolean): WalletData = mutex.withLock {
        withContext(Dispatchers.IO) {
            check(confirmed) { "Explicit confirmation is required." }
            sessionEntitlement = Entitlement.Free
            val cleared = WalletData.empty(initialLocale, initialCurrencyCode)
            prepareExplicitRecoveryUnlocked()
            writeUnlocked(cleared)
            purgeResidualUnlocked()
            cleared
        }
    }

    override suspend fun purgeResidualWalletFiles() = mutex.withLock {
        withContext(Dispatchers.IO) { purgeResidualUnlocked() }
    }

    private fun readUnlocked(): WalletData {
        directory.mkdirs()
        val quarantines = quarantinedFiles()
        if (corruptionMarker.exists() || (!file.exists() && quarantines.isNotEmpty())) {
            val quarantinePath = if (corruptionMarker.exists()) {
                corruptionMarker.readText()
            } else {
                quarantines.first().absolutePath
            }
            throw StorageCorruptionException(
                quarantinePath,
                IllegalStateException("Explicit recovery, import, or clearing is required."),
            )
        }
        if (!file.exists() && previous.exists()) {
            if (!previous.renameTo(file)) {
                previous.copyTo(file, overwrite = false)
                previous.delete()
            }
        }
        if (!file.exists()) {
            return WalletData.empty(initialLocale, initialCurrencyCode)
        }
        return try {
            withSessionEntitlement(codec.decodePrivate(file.readText(Charsets.UTF_8)))
        } catch (error: Throwable) {
            val stamp = System.currentTimeMillis()
            val quarantine = File(directory, "$fileName.corrupt.$stamp")
            if (!file.renameTo(quarantine)) {
                file.copyTo(quarantine, overwrite = false)
                file.delete()
            }
            durableWrite(corruptionMarker, quarantine.absolutePath)
            throw StorageCorruptionException(quarantine.absolutePath, error)
        }
    }

    private fun withSessionEntitlement(decoded: WalletData): WalletData =
        decoded.copy(entitlementCache = sessionEntitlement)

    private fun writeUnlocked(state: WalletData) {
        directory.mkdirs()
        durableWrite(temporary, codec.encodePrivate(state))
        if (previous.exists()) previous.delete()
        if (file.exists()) {
            if (!file.renameTo(previous)) {
                file.copyTo(previous, overwrite = true)
                file.delete()
            }
        }
        try {
            if (!temporary.renameTo(file)) {
                temporary.copyTo(file, overwrite = false)
                temporary.delete()
            }
            if (previous.exists()) {
                previous.copyTo(recovery, overwrite = true)
                previous.delete()
            }
        } catch (error: Throwable) {
            if (!file.exists() && previous.exists()) {
                if (!previous.renameTo(file)) previous.copyTo(file, overwrite = false)
            }
            throw error
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    private fun durableWrite(target: File, content: String) {
        target.parentFile?.mkdirs()
        FileOutputStream(target, false).use { stream ->
            stream.write(content.toByteArray(Charsets.UTF_8))
            stream.flush()
            stream.fd.sync()
        }
    }

    private fun quarantinedFiles(): List<File> {
        if (!directory.exists()) return emptyList()
        val prefix = "$fileName.corrupt."
        return directory.listFiles()?.filter { it.isFile && it.name.startsWith(prefix) }.orEmpty()
    }

    private fun prepareExplicitRecoveryUnlocked() {
        listOf(file, previous, recovery, temporary).forEach { if (it.exists()) it.delete() }
    }

    private fun purgeResidualUnlocked() {
        (listOf(previous, recovery, temporary, corruptionMarker) + quarantinedFiles())
            .forEach { if (it.exists()) it.delete() }
    }
}
