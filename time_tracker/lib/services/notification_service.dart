import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../screens/log_activity_screen.dart';
import 'log_service.dart';
import 'settings_service.dart';
import 'stats_service.dart';
import 'task_service.dart';
import '../models/task.dart';
import '../screens/main_navigation_screen.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static Future<void>? _initializationFuture;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static final TaskService _taskService = TaskService();
  static final LogService _logService = LogService();
  static final SettingsService _settingsService = SettingsService();
  static final StatsService _statsService = StatsService(
    LogService(),
    SettingsService(),
  );

  static const String _channelId = 'time_tracker_channel';
  static const String _channelName = 'Time Tracker';
  static const String _channelDescription =
      'Reminders to log the last 30 minutes.';
  static const int _reviewNotificationId = 4000;
  static const int _nextPromptNotificationId = 4001;
  static const int _confirmationNotificationId = 4002;
  static const int _dailySummaryNotificationId = 4003;
  static const int _weeklySummaryNotificationId = 4004;
  static const int _reminderIntervalMinutes = 30;
  static const String _logPayload = 'open_log_activity';
  static const String _reviewTaskActionPrefix = 'review:';
  static const String _nextTaskActionPrefix = 'next:';
  static const String _reviewPayloadPrefix = 'review:';
  static const String _dailySummaryPayload = 'summary:daily';
  static const String _weeklySummaryPayload = 'summary:weekly';

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
    await _notificationsPlugin.cancel(_reviewNotificationId);
    await _notificationsPlugin.cancel(_nextPromptNotificationId);
    await _notificationsPlugin.cancel(_confirmationNotificationId);
  }

  static Future<void> syncSummaryNotifications() async {
    await _ensureInitialized();
    await _scheduleDailySummaryNotification();
    await _scheduleWeeklySummaryNotification();
  }

  static Future<void> cancelSummaryNotifications() async {
    await _ensureInitialized();
    await _notificationsPlugin.cancel(_dailySummaryNotificationId);
    await _notificationsPlugin.cancel(_weeklySummaryNotificationId);
  }

  static Future<void> scheduleReminder({
    required DateTime when,
    required int minutes,
    required String taskName,
  }) async {
    await _ensureInitialized();
    await cancelReminder();

    final List<AndroidNotificationAction> actions =
        await _buildReminderActions(_reviewTaskActionPrefix);
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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

    final tz.TZDateTime scheduledAt = tz.TZDateTime.from(when, tz.local);
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

    if (!scheduledAt.isAfter(now)) {
      await _notificationsPlugin.show(
        _reviewNotificationId,
        'Time Tracker',
        'What are you doing right now? Check in for $taskName.',
        notificationDetails,
        payload: _logPayload,
      );
      return;
    }

    await _notificationsPlugin.zonedSchedule(
      _reviewNotificationId,
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

  static Future<void> syncReminders() async {
    await _ensureInitialized();

    final bool remindersEnabled = await _settingsService.getRemindersEnabled();
    if (!remindersEnabled) {
      await cancelReminder();
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? nextReminderAt = await _settingsService.getNextReminderAt();
    final int durationMinutes =
        await _settingsService.getNextReminderDurationMinutes();
    final DateTime scheduledAt = nextReminderAt != null && nextReminderAt.isAfter(now)
        ? nextReminderAt
        : await _nextReviewTime(now, _reminderIntervalMinutes);
    final int effectiveDuration =
        nextReminderAt != null && nextReminderAt.isAfter(now)
            ? durationMinutes
            : _reminderIntervalMinutes;

    await _scheduleReviewReminder(
      scheduledAt: scheduledAt,
      durationMinutes: effectiveDuration,
    );
    await syncSummaryNotifications();
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
    if (actionId != null && actionId.startsWith(_reviewTaskActionPrefix)) {
      await _handleReviewTaskAction(actionId, notificationResponse.payload);
      return;
    }
    if (actionId != null && actionId.startsWith(_nextTaskActionPrefix)) {
      await _handleNextTaskAction(actionId);
      return;
    }

    final String? payload = notificationResponse.payload;
    if (payload == _dailySummaryPayload) {
      await _openStatsScreen(initialIndex: 2);
      return;
    }
    if (payload == _weeklySummaryPayload) {
      await _openStatsScreen(initialIndex: 2);
      return;
    }
    if (payload != _logPayload) {
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

  static Future<List<AndroidNotificationAction>> _buildReminderActions(
    String actionPrefix,
  ) async {
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
            '$actionPrefix${task.id}',
            task.name,
            showsUserInterface: false,
            cancelNotification: true,
          ),
        )
        .toList();
  }

  static Future<void> _handleReviewTaskAction(
    String actionId,
    String? payload,
  ) async {
    final String taskId = actionId.substring(_reviewTaskActionPrefix.length);
    final List<Task> tasks = await _taskService.getTasks();
    final Task? task = tasks.cast<Task?>().firstWhere(
      (Task? item) => item?.id == taskId,
      orElse: () => null,
    );

    if (task == null) {
      return;
    }

    final DateTime rangeEnd = _reviewEndFromPayload(payload) ?? DateTime.now();
    final int durationMinutes =
        await _settingsService.getNextReminderDurationMinutes();
    final DateTime rangeStart = rangeEnd.subtract(
      Duration(minutes: durationMinutes),
    );
    final int blockCount =
        (durationMinutes / LogService.retroBlockSize.inMinutes).round();
    await _logService.assignSlots(
      rangeStart,
      List<String?>.filled(blockCount <= 0 ? 1 : blockCount, task.id),
    );
    await _taskService.setSelectedTaskId(task.id);
    await _settingsService.setNextReminderAt(null);

    await _showNextTaskPrompt();
    await syncSummaryNotifications();
  }

  static Future<void> _handleNextTaskAction(String actionId) async {
    final String taskId = actionId.substring(_nextTaskActionPrefix.length);
    final List<Task> tasks = await _taskService.getTasks();
    final Task? task = tasks.cast<Task?>().firstWhere(
      (Task? item) => item?.id == taskId,
      orElse: () => null,
    );

    if (task == null) {
      return;
    }

    await _taskService.setSelectedTaskId(task.id);
    final bool remindersEnabled = await _settingsService.getRemindersEnabled();
    if (!remindersEnabled) {
      await cancelReminder();
      return;
    }

    final int minutes = task.defaultMinutes > 0
        ? task.defaultMinutes
        : _reminderIntervalMinutes;
    await planNextReminder(minutes: minutes);
    await _showActionConfirmation(task, minutes);
    await syncSummaryNotifications();
  }

  static Future<void> planNextReminder({required int minutes}) async {
    await _ensureInitialized();
    await cancelReminder();
    final DateTime now = DateTime.now();
    final int effectiveMinutes = minutes <= 0 ? _reminderIntervalMinutes : minutes;
    final DateTime scheduledAt = await _nextReviewTime(now, effectiveMinutes);
    await _settingsService.setNextReminderAt(scheduledAt);
    await _settingsService.setNextReminderDurationMinutes(effectiveMinutes);
    await _scheduleReviewReminder(
      scheduledAt: scheduledAt,
      durationMinutes: effectiveMinutes,
    );
  }

  static Future<void> _scheduleReviewReminder({
    required DateTime scheduledAt,
    required int durationMinutes,
  }) async {
    final List<AndroidNotificationAction> actions =
        await _buildReminderActions(_reviewTaskActionPrefix);
    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        actions: actions,
      ),
    );
    final DateTime rangeStart =
        scheduledAt.subtract(Duration(minutes: durationMinutes));
    await _notificationsPlugin.zonedSchedule(
      _reviewNotificationId,
      'Time Tracker',
      'What did you do from ${_formatTime(rangeStart)}-${_formatTime(scheduledAt)}?',
      tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: '$_reviewPayloadPrefix${scheduledAt.toIso8601String()}',
    );
  }

  static Future<void> _showNextTaskPrompt() async {
    final List<AndroidNotificationAction> actions =
        await _buildReminderActions(_nextTaskActionPrefix);
    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        actions: actions,
      ),
    );
    await _notificationsPlugin.show(
      _nextPromptNotificationId,
      'Time Tracker',
      'What will you do next?',
      notificationDetails,
      payload: _logPayload,
    );
  }

  static Future<DateTime> _nextReviewTime(DateTime now, int minutes) async {
    final int activeStartHour = await _settingsService.getActiveStartHour();
    final int activeEndHour = await _settingsService.getActiveEndHour();
    DateTime candidate = now.add(Duration(minutes: minutes));
    while (true) {
      if (_isWithinActiveWindow(candidate, activeStartHour, activeEndHour)) {
        return candidate;
      }
      candidate = candidate.add(const Duration(minutes: _reminderIntervalMinutes));
    }
  }

  static bool _isWithinActiveWindow(
    DateTime value,
    int activeStartHour,
    int activeEndHour,
  ) {
    if (_settingsService.isFullDayWindow(activeStartHour, activeEndHour)) {
      return true;
    }

    final DateTime start = DateTime(
      value.year,
      value.month,
      value.day,
      activeStartHour,
    );
    final DateTime end = activeEndHour == 24
        ? DateTime(value.year, value.month, value.day)
            .add(const Duration(days: 1))
        : DateTime(
            value.year,
            value.month,
            value.day,
            activeEndHour,
          );

    if (!end.isAfter(start)) {
      return true;
    }

    return !value.isBefore(start) && value.isBefore(end);
  }

  static Future<void> _showActionConfirmation(Task task, int minutes) async {
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
      _confirmationNotificationId,
      'Next: ${task.name}',
      'I will remind you again in $minutes minutes.',
      notificationDetails,
    );
  }

  static Future<void> _scheduleWeeklySummaryNotification() async {
    final bool enabled = await _settingsService.getWeeklySummaryEnabled();
    await _notificationsPlugin.cancel(_weeklySummaryNotificationId);
    if (!enabled) {
      return;
    }

    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    final DateTime now = DateTime.now();
    final int weekday = await _settingsService.getWeeklySummaryWeekday();
    final int hour = await _settingsService.getWeeklySummaryHour();
    final int minute = await _settingsService.getWeeklySummaryMinute();
    final DateTime scheduledAt = _nextWeekdayAt(
      now,
      weekday: weekday,
      hour: hour,
      minute: minute,
    );
    final String summaryText = await _buildWeeklySummaryText(now);

    await _notificationsPlugin.zonedSchedule(
      _weeklySummaryNotificationId,
      'Your Week Summary',
      summaryText,
      tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: _weeklySummaryPayload,
    );
  }

  static Future<void> _scheduleDailySummaryNotification() async {
    final bool enabled = await _settingsService.getDailySummaryEnabled();
    await _notificationsPlugin.cancel(_dailySummaryNotificationId);
    if (!enabled) {
      return;
    }

    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    final DateTime now = DateTime.now();
    final int hour = await _settingsService.getDailySummaryHour();
    final int minute = await _settingsService.getDailySummaryMinute();
    final DateTime scheduledAt = _nextDayAt(now, hour: hour, minute: minute);
    final String summaryText = await buildDailySummaryText(now);

    await _notificationsPlugin.zonedSchedule(
      _dailySummaryNotificationId,
      'Your Day Summary',
      summaryText,
      tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: _dailySummaryPayload,
    );
  }

  static Future<String> buildDailySummaryText(DateTime now) async {
    final Map<String, Duration> totals =
        await _statsService.getDailyTaskTotals(now);
    return _buildTaskSummaryLines(
      totals: totals,
      emptyText: 'No logged time today',
    );
  }

  static Future<String> _buildWeeklySummaryText(DateTime now) async {
    final Map<String, Duration> totals =
        await _statsService.getWeeklyTaskTotals(now);
    final Map<int, Duration> dailyTotals =
        await _statsService.getWeeklyDailyTotals(now);
    final String taskSummary = await _buildTaskSummaryLines(
      totals: totals,
      emptyText: 'No logged time this week',
    );

    final Duration totalLogged = totals.values.fold(
      Duration.zero,
      (sum, value) => sum + value,
    );
    final MapEntry<int, Duration>? bestDay = dailyTotals.entries.isEmpty
        ? null
        : (dailyTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value))).first;

    final List<String> lines = <String>[
      taskSummary,
      if (bestDay != null) 'Most Productive Day: ${_weekdayName(bestDay.key)}',
      'Total Logged: ${_statsService.formatDuration(totalLogged)}',
    ];

    return lines.join('\n');
  }

  static Future<String> _buildTaskSummaryLines({
    required Map<String, Duration> totals,
    required String emptyText,
  }) async {
    final List<Task> tasks = await _taskService.getTasks();
    final Map<String, String> taskNamesById = <String, String>{
      for (final Task task in tasks) task.id: task.name,
      StatsService.unknownTaskId: 'Unknown',
    };

    final List<MapEntry<String, Duration>> sortedTotals = totals.entries
        .where((entry) => entry.value > Duration.zero)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedTotals.isEmpty) {
      return emptyText;
    }

    return sortedTotals
        .map(
          (entry) =>
              '${taskNamesById[entry.key] ?? 'Unknown'} ${_statsService.formatDuration(entry.value)}',
        )
        .join('\n');
  }

  static DateTime _nextDayAt(
    DateTime now, {
    required int hour,
    required int minute,
  }) {
    DateTime candidate = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  static DateTime _nextWeekdayAt(
    DateTime now, {
    required int weekday,
    required int hour,
    required int minute,
  }) {
    final DateTime todayTarget = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    final int daysToAdd = (weekday - now.weekday + 7) % 7;
    DateTime candidate = todayTarget.add(Duration(days: daysToAdd));
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  static String _weekdayName(int index) {
    const List<String> names = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final int safeIndex = index < 0 ? 0 : (index > 6 ? 6 : index);
    return names[safeIndex];
  }

  static DateTime? _reviewEndFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(_reviewPayloadPrefix)) {
      return null;
    }
    return DateTime.tryParse(payload.substring(_reviewPayloadPrefix.length));
  }

  static String _formatTime(DateTime value) {
    final int hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final String minute = value.minute.toString().padLeft(2, '0');
    final String suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  static Future<void> _openStatsScreen({required int initialIndex}) async {
    final NavigatorState? navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      return;
    }

    await navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            MainNavigationScreen(initialIndex: initialIndex),
      ),
      (Route<dynamic> route) => false,
    );
  }
}
