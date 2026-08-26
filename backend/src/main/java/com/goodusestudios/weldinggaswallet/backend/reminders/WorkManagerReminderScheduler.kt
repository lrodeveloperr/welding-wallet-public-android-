package com.goodusestudios.weldinggaswallet.backend.reminders

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.goodusestudios.weldinggaswallet.backend.domain.Reminder
import com.goodusestudios.weldinggaswallet.backend.domain.ReminderScheduler
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

interface ReminderPresentationGateway {
    fun configureLocalizedPresentation(channelName: String, channelDescription: String)
}

class WorkManagerReminderScheduler(
    context: Context,
    private val notificationSmallIconResId: Int,
    private val now: () -> Instant = Instant::now,
) : ReminderScheduler, ReminderPresentationGateway {
    private val appContext = context.applicationContext
    private val workManager = WorkManager.getInstance(appContext)
    private val permissionFailures = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @Volatile private var channelName: String? = null
    @Volatile private var channelDescription: String? = null

    init {
        require(notificationSmallIconResId != 0) { "A valid notification small-icon resource is required." }
    }

    override fun configureLocalizedPresentation(channelName: String, channelDescription: String) {
        require(channelName.isNotBlank()) { "Reminder channel name is required." }
        require(channelDescription.isNotBlank()) { "Reminder channel description is required." }
        this.channelName = channelName
        this.channelDescription = channelDescription
    }

    override fun canPostNotifications(): Boolean = notificationsGranted(appContext)

    override suspend fun consumePermissionFailure(reminderId: String): Boolean =
        withContext(Dispatchers.IO) {
            val key = permissionFailureKey(reminderId)
            val failed = permissionFailures.getBoolean(key, false)
            if (failed) permissionFailures.edit().remove(key).commit()
            failed
        }

    override suspend fun schedule(reminder: Reminder) {
        val localizedName = checkNotNull(channelName) {
            "Localized reminder presentation was not configured."
        }
        val localizedDescription = checkNotNull(channelDescription) {
            "Localized reminder presentation was not configured."
        }
        val current = now()
        val effective = if (reminder.dueAt.isAfter(current)) {
            reminder.dueAt
        } else {
            current.plusSeconds(5)
        }
        val delayMillis = Duration.between(current, effective).toMillis().coerceAtLeast(0L)

        val request = OneTimeWorkRequestBuilder<ReminderNotificationWorker>()
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .setInputData(
                workDataOf(
                    ReminderNotificationWorker.KEY_REMINDER_ID to reminder.id,
                    ReminderNotificationWorker.KEY_NOTIFICATION_ID to reminder.notificationId,
                    ReminderNotificationWorker.KEY_TITLE to reminder.title,
                    ReminderNotificationWorker.KEY_CHANNEL_NAME to localizedName,
                    ReminderNotificationWorker.KEY_CHANNEL_DESCRIPTION to localizedDescription,
                    ReminderNotificationWorker.KEY_SMALL_ICON to notificationSmallIconResId,
                ),
            )
            .addTag(TAG_ALL_REMINDERS)
            .addTag(tagForReminder(reminder.id))
            .build()

        val operation = workManager.enqueueUniqueWork(
            workName(reminder.id),
            ExistingWorkPolicy.REPLACE,
            request,
        )
        withContext(Dispatchers.IO) { operation.result.get() }
        withContext(Dispatchers.IO) {
            permissionFailures.edit().remove(permissionFailureKey(reminder.id)).commit()
        }
    }

    override suspend fun cancel(reminder: Reminder) {
        var failure: Throwable? = null
        try {
            val operation = workManager.cancelUniqueWork(workName(reminder.id))
            withContext(Dispatchers.IO) { operation.result.get() }
        } catch (error: Throwable) {
            failure = error
        } finally {
            try { dismiss(reminder) } catch (_: Throwable) { }
            withContext(Dispatchers.IO) {
                permissionFailures.edit().remove(permissionFailureKey(reminder.id)).commit()
            }
        }
        failure?.let { throw it }
    }

    override suspend fun dismiss(reminder: Reminder) {
        NotificationManagerCompat.from(appContext).cancel(reminder.notificationId)
    }

    override suspend fun cancelAll() {
        var failure: Throwable? = null
        try {
            val operation = workManager.cancelAllWorkByTag(TAG_ALL_REMINDERS)
            withContext(Dispatchers.IO) { operation.result.get() }
        } catch (error: Throwable) {
            failure = error
        } finally {
            NotificationManagerCompat.from(appContext).cancelAll()
            withContext(Dispatchers.IO) { permissionFailures.edit().clear().commit() }
        }
        failure?.let { throw it }
    }

    companion object {
        internal const val PREFS_NAME = "welding-wallet-reminder-delivery"
        internal const val TAG_ALL_REMINDERS = "welding-wallet-reminders"
        internal fun workName(id: String) = "reminder-$id"
        internal fun tagForReminder(id: String) = "reminder-tag-$id"
        internal fun permissionFailureKey(id: String) = "permission-missed-$id"
    }
}

class ReminderNotificationWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
    override fun doWork(): Result {
        val reminderId = inputData.getString(KEY_REMINDER_ID) ?: return Result.failure()
        val notificationId = inputData.getInt(KEY_NOTIFICATION_ID, Int.MIN_VALUE)
        if (notificationId == Int.MIN_VALUE) return Result.failure()
        val title = inputData.getString(KEY_TITLE)?.takeIf { it.isNotBlank() } ?: return Result.failure()
        val channelName = inputData.getString(KEY_CHANNEL_NAME)?.takeIf { it.isNotBlank() }
            ?: return Result.failure()
        val channelDescription = inputData.getString(KEY_CHANNEL_DESCRIPTION)?.takeIf { it.isNotBlank() }
            ?: return Result.failure()
        val icon = inputData.getInt(KEY_SMALL_ICON, 0)
        if (icon == 0) return Result.failure()

        if (!notificationsGranted(applicationContext)) {
            applicationContext.getSharedPreferences(
                WorkManagerReminderScheduler.PREFS_NAME,
                Context.MODE_PRIVATE,
            ).edit()
                .putBoolean(WorkManagerReminderScheduler.permissionFailureKey(reminderId), true)
                .commit()
            return Result.success()
        }

        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    channelName,
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = channelDescription
                },
            )
        }

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(applicationContext).notify(notificationId, notification)
        return Result.success()
    }

    companion object {
        const val KEY_REMINDER_ID = "reminder_id"
        const val KEY_NOTIFICATION_ID = "notification_id"
        const val KEY_TITLE = "title"
        const val KEY_CHANNEL_NAME = "channel_name"
        const val KEY_CHANNEL_DESCRIPTION = "channel_description"
        const val KEY_SMALL_ICON = "small_icon"
        private const val CHANNEL_ID = "wallet_reminders"
    }
}

fun notificationsGranted(context: Context): Boolean =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED
