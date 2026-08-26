package com.goodusestudios.weldinggaswallet.backend

import android.content.Context
import com.goodusestudios.weldinggaswallet.backend.billing.ActivityProvider
import com.goodusestudios.weldinggaswallet.backend.billing.GooglePlayBillingGateway
import com.goodusestudios.weldinggaswallet.backend.domain.*
import com.goodusestudios.weldinggaswallet.backend.reminders.WorkManagerReminderScheduler
import com.goodusestudios.weldinggaswallet.backend.storage.AtomicFileWalletRepository
import com.goodusestudios.weldinggaswallet.backend.storage.JsonWalletCodec
import kotlinx.coroutines.flow.SharedFlow
import java.io.File
import java.security.SecureRandom
import java.time.Instant

class AndroidWeldingWalletBackend private constructor(
    val engine: WeldingGasWalletEngine,
    val repository: AtomicFileWalletRepository,
    val billing: GooglePlayBillingGateway,
    val reminders: WorkManagerReminderScheduler,
    val codec: JsonWalletCodec,
) : AutoCloseable {

    val entitlementRefreshRequests: SharedFlow<Unit>
        get() = billing.entitlementRefreshRequests

    suspend fun bootstrap(): WalletData {
        repository.read()
        try {
            engine.restoreAndResume()
        } catch (_: Throwable) {
        }
        engine.enforceDowngradeIfNeeded()
        engine.reconcileReminders()
        return engine.snapshot()
    }

    suspend fun onResume(): WalletData {
        try {
            engine.restoreAndResume()
        } catch (_: Throwable) {
        }
        try {
            engine.reconcileReminders()
        } catch (_: Throwable) {
        }
        return engine.snapshot()
    }

    override fun close() {
        billing.close()
    }

    companion object {
        fun create(
            context: Context,
            activityProvider: ActivityProvider,
            playLicenseKeyBase64: String,
            notificationSmallIconResId: Int,
            reminderChannelName: String,
            reminderChannelDescription: String,
            initialLocale: String,
            initialCurrencyCode: String? = null,
        ): AndroidWeldingWalletBackend {
            val appContext = context.applicationContext
            val codec = JsonWalletCodec()
            val repository = AtomicFileWalletRepository(
                directory = File(appContext.filesDir, "welding-gas-wallet"),
                codec = codec,
                initialLocale = initialLocale,
                initialCurrencyCode = initialCurrencyCode,
            )
            val clock = Clock { Instant.now() }
            val scheduler = WorkManagerReminderScheduler(
                context = appContext,
                notificationSmallIconResId = notificationSmallIconResId,
            ).apply {
                configureLocalizedPresentation(
                    channelName = reminderChannelName,
                    channelDescription = reminderChannelDescription,
                )
            }
            val billing = GooglePlayBillingGateway(
                context = appContext,
                activityProvider = activityProvider,
                clock = clock,
                playLicenseKeyBase64 = playLicenseKeyBase64,
            )
            val engine = WeldingGasWalletEngine(
                repo = repository,
                billing = billing,
                scheduler = scheduler,
                ids = UuidV7IdFactory(),
                clock = clock,
                backupCodec = codec,
            )
            return AndroidWeldingWalletBackend(
                engine = engine,
                repository = repository,
                billing = billing,
                reminders = scheduler,
                codec = codec,
            )
        }
    }
}

class UuidV7IdFactory(
    private val random: SecureRandom = SecureRandom(),
    private val nowMillis: () -> Long = System::currentTimeMillis,
) : IdFactory {
    override fun newId(): String {
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        val millis = nowMillis() and 0x0000FFFFFFFFFFFFL
        for (index in 0 until 6) {
            val shift = (5 - index) * 8
            bytes[index] = ((millis ushr shift) and 0xff).toByte()
        }
        bytes[6] = ((bytes[6].toInt() and 0x0f) or 0x70).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3f) or 0x80).toByte()
        val hex = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
        return buildString(36) {
            append(hex, 0, 8)
            append('-')
            append(hex, 8, 12)
            append('-')
            append(hex, 12, 16)
            append('-')
            append(hex, 16, 20)
            append('-')
            append(hex, 20, 32)
        }
    }
}

object LegalLinks {
    const val privacy = "https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/privacy/"
    const val terms = "https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/terms/"
    const val support = "https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/support/"
    const val deletion = "https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/deletion/"
    const val disclaimer = "https://lrodeveloperr.github.io/privacy-policy/welding-gas-wallet/disclaimer/"
}
