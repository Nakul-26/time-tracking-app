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
  static const int _nextReminderNotificationId = 4000;
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
  }

  static Future<void> cancelReminder() async {
    await _notificationsPlugin.cancel(_nextReminderNotificationId);
  }

  static Future<void> scheduleReminder({
    required DateTime when,
    required int minutes,
    required String taskName,
  }) async {
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

    await cancelReminder();

    await _notificationsPlugin.zonedSchedule(
      _nextReminderNotificationId,
      'Time Tracker',
      'Time to check in on $taskName after $minutes minutes.',
      tz.TZDateTime.from(when, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: _logPayload,
    );
  }
}
