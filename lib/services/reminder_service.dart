import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/models.dart';

class ReminderService {
  ReminderService({FlutterLocalNotificationsPlugin? notifications})
    : _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _notifications;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final ios = await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return android ?? ios ?? true;
  }

  Future<void> schedule(
    Reminder reminder, {
    required String cylinderName,
  }) async {
    await initialize();
    if (!reminder.dueAt.isAfter(DateTime.now().toUtc())) return;
    await _notifications.zonedSchedule(
      id: reminder.notificationId,
      title: reminder.title,
      body: '$cylinderName · Welding Gas Wallet',
      scheduledDate: tz.TZDateTime.from(reminder.dueAt, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'wallet_reminders',
          'Cylinder reminders',
          channelDescription:
              'Refill, rental, return and cylinder check reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.cylinderId,
    );
  }

  Future<void> cancel(Reminder reminder) =>
      _notifications.cancel(id: reminder.notificationId);

  Future<void> cancelAll() => _notifications.cancelAll();
}
