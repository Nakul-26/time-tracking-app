import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../screens/log_activity_screen.dart';
import 'log_service.dart';
import 'settings_service.dart';
import 'task_service.dart';
import '../models/task.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static Future<void>? _initializationFuture;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static final TaskService _taskService = TaskService();
  static final LogService _logService = LogService();
  static final SettingsService _settingsService = SettingsService();

  static const String _channelId = 'time_tracker_channel';
  static const String _channelName = 'Time Tracker';
  static const String _channelDescription =
      'Reminders to log the last 30 minutes.';
  static const int _nextReminderNotificationId = 4000;
  static const String _logPayload = 'open_log_activity';
  static const String _taskActionPrefix = 'task:';

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;
    if (_initializationFuture != null) {
      return _initializationFuture;
    }

    _initializationFuture = _initialize(navigatorKey);
    return _initializationFuture;
  }

  static Future<void> _initialize(GlobalKey<NavigatorState> navigatorKey) async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: handleNotificationResponse,
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
    await _ensureInitialized();
    await _notificationsPlugin.cancel(_nextReminderNotificationId);
  }

  static Future<void> scheduleReminder({
    required DateTime when,
    required int minutes,
    required String taskName,
  }) async {
    await _ensureInitialized();
    final List<AndroidNotificationAction> actions =
        await _buildReminderActions();
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      actions: actions,
    );
    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await cancelReminder();

    final tz.TZDateTime scheduledAt = tz.TZDateTime.from(when, tz.local);
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

    if (!scheduledAt.isAfter(now)) {
      await _notificationsPlugin.show(
        _nextReminderNotificationId,
        'Time Tracker',
        'What are you doing right now? Check in for $taskName.',
        notificationDetails,
        payload: _logPayload,
      );
      return;
    }

    await _notificationsPlugin.zonedSchedule(
      _nextReminderNotificationId,
      'Time Tracker',
      'Time to check in on $taskName after $minutes minutes.',
      scheduledAt,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: _logPayload,
    );
  }

  static Future<void> showTestNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Manual test notifications for debugging.',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _ensureInitialized();
    await _notificationsPlugin.show(
      999,
      'Test Notification',
      'If you see this, notifications are working.',
      notificationDetails,
    );
  }

  static Future<int> pendingReminderCount() async {
    await _ensureInitialized();
    final List<PendingNotificationRequest> pending =
        await _notificationsPlugin.pendingNotificationRequests();
    return pending.length;
  }

  static Future<void> _ensureInitialized() async {
    final Future<void>? initializationFuture = _initializationFuture;
    if (initializationFuture != null) {
      await initializationFuture;
    }
  }

  @pragma('vm:entry-point')
  static Future<void> handleNotificationResponse(
    NotificationResponse notificationResponse,
  ) async {
    final String? actionId = notificationResponse.actionId;
    if (actionId != null && actionId.startsWith(_taskActionPrefix)) {
      await _handleTaskAction(actionId);
      return;
    }

    if (notificationResponse.payload != _logPayload) {
      return;
    }

    final NavigatorState? navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      return;
    }

    navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const LogActivityScreen(),
      ),
    );
  }

  static Future<List<AndroidNotificationAction>> _buildReminderActions() async {
    final List<Task> tasks = await _taskService.getTasks();
    final String? selectedTaskId = await _taskService.getSelectedTaskId();
    final List<Task> prioritizedTasks = <Task>[];
    final Set<String> addedIds = <String>{};

    if (selectedTaskId != null) {
      final Task? selectedTask = tasks.cast<Task?>().firstWhere(
        (Task? task) => task?.id == selectedTaskId,
        orElse: () => null,
      );
      if (selectedTask != null && addedIds.add(selectedTask.id)) {
        prioritizedTasks.add(selectedTask);
      }
    }

    final currentActivity = await _logService.getCurrentActivity();
    if (currentActivity != null) {
      final Task? currentTask = tasks.cast<Task?>().firstWhere(
        (Task? task) => task?.id == currentActivity.taskId,
        orElse: () => null,
      );
      if (currentTask != null && addedIds.add(currentTask.id)) {
        prioritizedTasks.add(currentTask);
      }
    }

    for (final Task task in tasks) {
      if (addedIds.add(task.id)) {
        prioritizedTasks.add(task);
      }

      if (prioritizedTasks.length >= 3) {
        break;
      }
    }

    return prioritizedTasks
        .take(3)
        .map(
          (Task task) => AndroidNotificationAction(
            '$_taskActionPrefix${task.id}',
            task.name,
            showsUserInterface: false,
            cancelNotification: true,
          ),
        )
        .toList();
  }

  static Future<void> _handleTaskAction(String actionId) async {
    final String taskId = actionId.substring(_taskActionPrefix.length);
    final List<Task> tasks = await _taskService.getTasks();
    final Task? task = tasks.cast<Task?>().firstWhere(
      (Task? item) => item?.id == taskId,
      orElse: () => null,
    );

    if (task == null) {
      return;
    }

    final currentActivity = await _logService.getCurrentActivity();
    if (currentActivity?.taskId == task.id) {
      await _scheduleNextReminderFromNow(task);
      await _showActionConfirmation(task);
      return;
    }

    final activityLog = await _logService.startActivity(task.id);
    await _taskService.setSelectedTaskId(task.id);

    final bool remindersEnabled = await _settingsService.getRemindersEnabled();
    if (!remindersEnabled) {
      await cancelReminder();
      return;
    }

    await scheduleReminder(
      when: activityLog.startTime.add(Duration(minutes: task.defaultMinutes)),
      minutes: task.defaultMinutes,
      taskName: task.name,
    );
    await _showActionConfirmation(task);
  }

  static Future<void> _scheduleNextReminderFromNow(Task task) async {
    final bool remindersEnabled = await _settingsService.getRemindersEnabled();
    if (!remindersEnabled) {
      await cancelReminder();
      return;
    }

    await scheduleReminder(
      when: DateTime.now().add(Duration(minutes: task.defaultMinutes)),
      minutes: task.defaultMinutes,
      taskName: task.name,
    );
  }

  static Future<void> _showActionConfirmation(Task task) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      4001,
      'Started ${task.name}',
      'Next reminder in ${task.defaultMinutes} minutes.',
      notificationDetails,
    );
  }
}
