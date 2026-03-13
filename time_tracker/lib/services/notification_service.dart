import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../screens/log_activity_screen.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'time_tracker_channel';
  static const String _channelName = 'Time Tracker';
  static const String _channelDescription =
      'Reminders to log the last 30 minutes.';
  static const int _reminderNotificationBaseId = 3000;
  static const String _logPayload = 'open_log_activity';

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse:
          (NotificationResponse notificationResponse) {
            if (notificationResponse.payload != _logPayload) {
              return;
            }

            final NavigatorState? navigator = navigatorKey.currentState;
            if (navigator == null) {
              return;
            }

            navigator.push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const LogActivityScreen(),
              ),
            );
          },
    );

    await _requestPermissions();
  }

  static Future<void> _requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();
  }

  static Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }

  static Future<void> scheduleTodayReminders() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await cancelAll();

    final DateTime now = DateTime.now();
    final DateTime startOfDay = DateTime(now.year, now.month, now.day);
    DateTime nextSlot = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute < 30 ? 30 : 0,
    );

    if (nextSlot.isBefore(now) || nextSlot.isAtSameMomentAs(now)) {
      nextSlot = nextSlot.add(const Duration(hours: 1));
    }

    if (nextSlot.day != startOfDay.day) {
      nextSlot = startOfDay.add(const Duration(days: 1));
    }

    int notificationId = _reminderNotificationBaseId;
    while (nextSlot.day == startOfDay.day) {
      await _notificationsPlugin.zonedSchedule(
        notificationId,
        'Time Tracker',
        'What were you doing the last 30 minutes?',
        tz.TZDateTime.from(nextSlot, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: _logPayload,
      );

      notificationId += 1;
      nextSlot = nextSlot.add(const Duration(minutes: 30));
    }
  }

  static Future<void> scheduleHalfHourReminders() async {
    await scheduleTodayReminders();
  }
}
