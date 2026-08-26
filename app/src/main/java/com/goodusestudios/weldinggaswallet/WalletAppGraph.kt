package com.goodusestudios.weldinggaswallet

import android.app.Activity
import android.content.Context
import com.goodusestudios.weldinggaswallet.backend.UuidV7IdFactory
import com.goodusestudios.weldinggaswallet.backend.billing.ActivityProvider
import com.goodusestudios.weldinggaswallet.backend.billing.GooglePlayBillingGateway
import com.goodusestudios.weldinggaswallet.backend.domain.*
import com.goodusestudios.weldinggaswallet.backend.reminders.WorkManagerReminderScheduler
import com.goodusestudios.weldinggaswallet.backend.storage.AtomicFileWalletRepository
import com.goodusestudios.weldinggaswallet.backend.storage.JsonWalletCodec
import java.io.File
import java.time.Instant

class WalletAppGraph(
    context: Context,
    activityProvider: () -> Activity?,
    initialLocale: String,
) : AutoCloseable {
    private val appContext = context.applicationContext
    private val codec = JsonWalletCodec()
    private val repository = AtomicFileWalletRepository(
        directory = File(appContext.filesDir, "welding-gas-wallet"),
        codec = codec,
        initialLocale = initialLocale,
    )
    private val clock = Clock { Instant.now() }
    private val scheduler = WorkManagerReminderScheduler(
        context = appContext,
        notificationSmallIconResId = R.drawable.ic_stat_cylinder,
    ).apply {
        configureLocalizedPresentation(
            channelName = appContext.getString(R.string.reminder_channel_name),
            channelDescription = appContext.getString(R.string.reminder_channel_description),
        )
    }

    private val billing: StoreBillingGateway = createBilling(activityProvider)

    val engine = WeldingGasWalletEngine(
        repo = repository,
        billing = billing,
        scheduler = scheduler,
        ids = UuidV7IdFactory(),
        clock = clock,
        backupCodec = codec,
    )

    val billingConfigured: Boolean = billing is GooglePlayBillingGateway

    private fun createBilling(activityProvider: () -> Activity?): StoreBillingGateway {
        val key = BuildConfig.PLAY_LICENSE_KEY.trim()
        if (key.isEmpty()) return PreviewBillingGateway
        return try {
            GooglePlayBillingGateway(
                context = appContext,
                activityProvider = ActivityProvider { activityProvider() },
                clock = clock,
                playLicenseKeyBase64 = key,
            )
        } catch (_: Throwable) {
            PreviewBillingGateway
        }
    }

    suspend fun bootstrap(): WalletData {
        repository.read()
        try { engine.restoreAndResume() } catch (_: Throwable) { }
        engine.enforceDowngradeIfNeeded()
        try { engine.reconcileReminders() } catch (_: Throwable) { }
        return engine.snapshot()
    }

    suspend fun onResume(): WalletData {
        try { engine.restoreAndResume() } catch (_: Throwable) { }
        try { engine.enforceDowngradeIfNeeded() } catch (_: Throwable) { }
        try { engine.reconcileReminders() } catch (_: Throwable) { }
        return engine.snapshot()
    }

    override fun close() {
        (billing as? AutoCloseable)?.close()
    }

    private object PreviewBillingGateway : StoreBillingGateway {
        override suspend fun loadProducts(): List<StoreProduct> = emptyList()
        override suspend fun purchaseVerified(productId: String): Entitlement =
            throw PurchaseOutcomeException(PurchaseOutcome.failed)
        override suspend fun restoreOrRefreshVerified(): Entitlement = Entitlement.Free
        override suspend fun openSubscriptionManagement() = Unit
    }
}
