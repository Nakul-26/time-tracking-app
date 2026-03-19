import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../screens/log_activity_screen.dart';
import 'log_service.dart';
import 'settings_service.dart';
import 'stats_service.dart';
import 'task_service.dart';
import '../models/task.dart';
import '../screens/main_navigation_screen.dart';

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  await NotificationService.handleNotificationResponse(response);
}

@pragma('vm:entry-point')
void reminderServiceStartCallback() {
  FlutterForegroundTask.setTaskHandler(ReminderForegroundTaskHandler());
}

class ReminderForegroundTaskHandler extends TaskHandler {
  FlutterLocalNotificationsPlugin? _notificationsPlugin;

  @override
  void onStart(DateTime timestamp, SendPort? sendPort) async {
    await NotificationService.ensureBackgroundInitialized();
    _notificationsPlugin =
        await NotificationService.createForegroundReminderPlugin();
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final FlutterLocalNotificationsPlugin notificationsPlugin =
        _notificationsPlugin ??
            await NotificationService.createForegroundReminderPlugin();
    _notificationsPlugin = notificationsPlugin;
    await NotificationService.handleForegroundReminderTick(
      timestamp,
      notificationsPlugin,
    );
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static Future<void>? _initializationFuture;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static NotificationResponse? _launchNotificationResponse;
  static final TaskService _taskService = TaskService();
  static final LogService _logService = LogService();
  static final SettingsService _settingsService = SettingsService();
  static final StatsService _statsService = StatsService(
    LogService(),
    SettingsService(),
  );

  static const String _reminderChannelId = 'time_tracker_reminders_v4';
  static const String _reminderChannelName = 'Time Tracker Reminders';
  static const String _reminderChannelDescription =
      'Reminders to log the last 30 minutes.';
  static const String _statusChannelId = 'time_tracker_status_v1';
  static const String _statusChannelName = 'Time Tracker Status';
  static const String _statusChannelDescription =
      'Lower priority confirmations and summaries.';
  static const String _debugChannelId = 'time_tracker_debug_v1';
  static const String _debugChannelName = 'Time Tracker Debug';
  static const String _debugChannelDescription =
      'Manual notification tests for debugging.';
  static const int _reviewNotificationId = 4000;
  static const int _nextPromptNotificationId = 4001;
  static const int _confirmationNotificationId = 4002;
  static const int _dailySummaryNotificationId = 4003;
  static const int _weeklySummaryNotificationId = 4004;
  static const int _scheduledDebugNotificationId = 4999;
  static const int _reminderIntervalMinutes = 30;
  static const int _foregroundServiceIntervalMs = 60000;
  static const String _foregroundServiceChannelId =
      'time_tracker_foreground_service_v1';
  static const String _foregroundServiceChannelName = 'Time Tracker Active';
  static const String _reminderTaskUniqueName = 'time_tracker_reminder';
  static const String _reminderTaskName = 'time_tracker_reminder_task';
  static const String _dailySummaryTaskUniqueName = 'time_tracker_daily_summary';
  static const String _dailySummaryTaskName = 'time_tracker_daily_summary_task';
  static const String _weeklySummaryTaskUniqueName =
      'time_tracker_weekly_summary';
  static const String _weeklySummaryTaskName =
      'time_tracker_weekly_summary_task';
  static const String _debugTaskUniqueName = 'time_tracker_debug';
  static const String _debugTaskName = 'time_tracker_debug_task';
  static const String _scheduledAtInputKey = 'scheduled_at';
  static const String _durationInputKey = 'duration_minutes';
  static const String _taskNameInputKey = 'task_name';
  static const String _activeStartHourInputKey = 'active_start_hour';
  static const String _activeEndHourInputKey = 'active_end_hour';
  static const String _remindersEnabledInputKey = 'reminders_enabled';
  static const String _debugTitleInputKey = 'debug_title';
  static const String _debugBodyInputKey = 'debug_body';
  static const String _logPayload = 'open_log_activity';
  static const String _reviewTaskActionPrefix = 'review:';
  static const String _nextTaskActionPrefix = 'next:';
  static const String _openLogActionId = 'open_log';
  static const String _skipReminderActionId = 'skip_reminder';
  static const String _reviewPayloadPrefix = 'review:';
  static const String _dailySummaryPayload = 'summary:daily';
  static const String _weeklySummaryPayload = 'summary:weekly';
  static const MethodChannel _timezoneChannel = MethodChannel(
    'time_tracker/timezone',
  );

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;
    if (_initializationFuture != null) {
      return _initializationFuture;
    }

    _initializationFuture = _initialize(navigatorKey);
    return _initializationFuture;
  }

  static Future<void> initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _foregroundServiceChannelId,
        channelName: _foregroundServiceChannelName,
        channelDescription: 'Keeps reminder tracking active in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: _foregroundServiceIntervalMs,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<void> _initialize(GlobalKey<NavigatorState> navigatorKey) async {
    await _configureLocalTimeZone();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final NotificationAppLaunchDetails? launchDetails =
        await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _launchNotificationResponse = launchDetails?.notificationResponse;
    }

    await _createAndroidChannels();
    await _requestPermissions();
  }

  static Future<void> handleAppLaunchNotification() async {
    final NotificationResponse? response = _launchNotificationResponse;
    if (response == null) {
      return;
    }
    _launchNotificationResponse = null;
    await handleNotificationResponse(response);
  }

  static Future<void> _createAndroidChannels() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) {
      return;
    }

    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        _reminderChannelId,
        _reminderChannelName,
        description: _reminderChannelDescription,
        importance: Importance.max,
      ),
    );
    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        _statusChannelId,
        _statusChannelName,
        description: _statusChannelDescription,
        importance: Importance.defaultImportance,
      ),
    );
    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        _debugChannelId,
        _debugChannelName,
        description: _debugChannelDescription,
        importance: Importance.max,
      ),
    );
  }

  static Future<void> _configureLocalTimeZone() async {
    tz.initializeTimeZones();
    try {
      final String? timezoneName = await _timezoneChannel.invokeMethod<String>(
        'getLocalTimezone',
      );
      if (timezoneName != null && timezoneName.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(timezoneName));
      }
    } catch (_) {
      // Fall back to the package default if the platform timezone lookup fails.
    }
  }

  static Future<void> _requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();
  }

  static Future<void> ensureBackgroundInitialized() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!Hive.isBoxOpen('settings') && !Hive.isBoxOpen('logs')) {
      await Hive.initFlutter();
    }
    await init(GlobalKey<NavigatorState>());
  }

  @pragma('vm:entry-point')
  static Future<void> runBackgroundTask(
    String task,
    Map<String, dynamic>? inputData,
  ) async {
    await ensureBackgroundInitialized();
    switch (task) {
      case _reminderTaskName:
        await _showReminderNotificationFromWork(inputData);
        break;
      case _dailySummaryTaskName:
        await _showDailySummaryNotification();
        await _scheduleDailySummaryWorker();
        break;
      case _weeklySummaryTaskName:
        await _showWeeklySummaryNotification();
        await _scheduleWeeklySummaryWorker();
        break;
      case _debugTaskName:
        await _showDebugNotification(
          title: inputData?[_debugTitleInputKey] as String? ??
              'Scheduled Test Notification',
          body: inputData?[_debugBodyInputKey] as String? ??
              'If this appears, WorkManager scheduling is working.',
        );
        break;
    }
  }

  static Future<bool> requestExactAlarmPermission() async {
    await _ensureInitialized();
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final bool canScheduleExact =
        await androidImplementation?.canScheduleExactNotifications() ?? false;
    if (canScheduleExact) {
      return true;
    }

    await androidImplementation?.requestExactAlarmsPermission();
    return await androidImplementation?.canScheduleExactNotifications() ?? false;
  }

  static Future<void> cancelReminder() async {
    await _ensureInitialized();
    await _saveReminderServiceData(enabled: false);
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    await _safeCancel(_reviewNotificationId);
    await _safeCancel(_nextPromptNotificationId);
    await _safeCancel(_confirmationNotificationId);
  }

  static Future<void> syncSummaryNotifications() async {
    await _ensureInitialized();
    await _scheduleDailySummaryNotification();
    await _scheduleWeeklySummaryNotification();
  }

  static Future<void> cancelSummaryNotifications() async {
    await _ensureInitialized();
    await Workmanager().cancelByUniqueName(_dailySummaryTaskUniqueName);
    await Workmanager().cancelByUniqueName(_weeklySummaryTaskUniqueName);
    await _safeCancel(_dailySummaryNotificationId);
    await _safeCancel(_weeklySummaryNotificationId);
  }

  static Future<void> scheduleReminder({
    required DateTime when,
    required int minutes,
    required String taskName,
  }) async {
    await _ensureInitialized();
    await cancelReminder();

    if (!when.isAfter(DateTime.now())) {
      await showReminderNotification(
        scheduledAt: when,
        durationMinutes: minutes,
        taskName: taskName,
      );
      return;
    }

    await _startOrUpdateReminderService(
      scheduledAt: when,
      durationMinutes: minutes,
      taskName: taskName,
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
    final int effectiveDuration =
        nextReminderAt != null
            ? (durationMinutes <= 0 ? _reminderIntervalMinutes : durationMinutes)
            : await _currentReminderDurationMinutes();
    final bool hasOverdueReminder =
        nextReminderAt != null && !nextReminderAt.isAfter(now);
    if (hasOverdueReminder) {
      await showReminderNotification(
        scheduledAt: nextReminderAt,
        durationMinutes: effectiveDuration,
        taskName: await _currentReminderTaskName(),
      );
    }
    final DateTime scheduledAt =
        nextReminderAt != null && nextReminderAt.isAfter(now)
            ? nextReminderAt
            : await _nextReviewTime(now, effectiveDuration);

    await _settingsService.setNextReminderAt(scheduledAt);
    await _settingsService.setNextReminderDurationMinutes(effectiveDuration);

    await _scheduleReminderService(
      scheduledAt: scheduledAt,
      durationMinutes: effectiveDuration,
    );
    await syncSummaryNotifications();
  }

  static Future<void> showTestNotification() async {
    await _ensureInitialized();
    await _showDebugNotification(
      title: 'Test Notification',
      body: 'If you see this, notifications are working.',
    );
  }

  static Future<void> scheduleDebugNotification({
    Duration delay = const Duration(seconds: 15),
  }) async {
    await _ensureInitialized();
    await Workmanager().cancelByUniqueName(_debugTaskUniqueName);
    await Workmanager().registerOneOffTask(
      _debugTaskUniqueName,
      _debugTaskName,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      inputData: <String, dynamic>{
        _debugTitleInputKey: 'Scheduled Test Notification',
        _debugBodyInputKey: 'If this appears, WorkManager scheduling is working.',
      },
    );
  }

  static Future<int> pendingReminderCount() async {
    await _ensureInitialized();
    final DateTime? nextReminderAt = await _settingsService.getNextReminderAt();
    return nextReminderAt == null ? 0 : 1;
  }

  static Future<String> reminderDebugStatus() async {
    await _ensureInitialized();
    final DateTime? nextReminderAt = await _settingsService.getNextReminderAt();
    final int durationMinutes =
        await _settingsService.getNextReminderDurationMinutes();
    final bool serviceRunning = await FlutterForegroundTask.isRunningService;
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final bool notificationsEnabled =
        await androidImplementation?.areNotificationsEnabled() ?? true;
    final List<AndroidNotificationChannel> channels =
        await androidImplementation?.getNotificationChannels() ??
            const <AndroidNotificationChannel>[];

    final String nextReminderLabel = nextReminderAt == null
        ? 'none'
        : _formatReminderDateTime(nextReminderAt.toLocal());
    final String nowLabel = _formatReminderDateTime(DateTime.now().toLocal());
    final String timezoneLabel = tz.local.name;
    final String channelSummary = channels
        .where(
          (AndroidNotificationChannel channel) =>
              channel.id == _reminderChannelId ||
              channel.id == _statusChannelId ||
              channel.id == _debugChannelId,
        )
        .map(
          (AndroidNotificationChannel channel) =>
              '${channel.id}:${channel.importance.name}',
        )
        .join(', ');

    return 'notifications=$notificationsEnabled, scheduler=foreground_service, '
        'now=$nowLabel, timezone=$timezoneLabel, '
        'next=$nextReminderLabel, duration=${durationMinutes}m, '
        'serviceRunning=$serviceRunning, pending=${nextReminderAt == null ? 0 : 1}, '
        'channels=${channelSummary.isEmpty ? 'none' : channelSummary}';
  }

  static Future<void> _safeCancel(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
    } on PlatformException catch (error) {
      if (_isCorruptScheduleCacheError(error)) {
        return;
      }
      rethrow;
    }
  }

  static bool _isCorruptScheduleCacheError(PlatformException error) {
    final String message = '${error.code} ${error.message} ${error.details}'
        .toLowerCase();
    return message.contains('missing type parameter');
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
    if (actionId == _openLogActionId) {
      await _openLogActivityScreen();
      return;
    }
    if (actionId == _skipReminderActionId) {
      await _handleSkipReminder();
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
    if (payload != _logPayload &&
        (payload == null || !payload.startsWith(_reviewPayloadPrefix))) {
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
    await _scheduleReminderService(
      scheduledAt: scheduledAt,
      durationMinutes: effectiveMinutes,
    );
  }

  static Future<void> _scheduleReminderService({
    required DateTime scheduledAt,
    required int durationMinutes,
  }) async {
    final String taskName = await _currentReminderTaskName();
    await _startOrUpdateReminderService(
      scheduledAt: scheduledAt,
      durationMinutes: durationMinutes,
      taskName: taskName,
    );
  }

  static Future<void> _showNextTaskPrompt() async {
    final List<AndroidNotificationAction> actions =
        await _buildReminderActions(_nextTaskActionPrefix);
    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId,
        _reminderChannelName,
        channelDescription: _reminderChannelDescription,
        importance: Importance.max,
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
    return _nextReviewTimeForWindow(
      now,
      minutes,
      activeStartHour,
      activeEndHour,
    );
  }

  static DateTime _nextReviewTimeForWindow(
    DateTime now,
    int minutes,
    int activeStartHour,
    int activeEndHour,
  ) {
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
      _statusChannelId,
      _statusChannelName,
      channelDescription: _statusChannelDescription,
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
    await _scheduleWeeklySummaryWorker();
  }

  static Future<void> _scheduleDailySummaryNotification() async {
    await _scheduleDailySummaryWorker();
  }

  static Future<void> showReminderNotification({
    required DateTime scheduledAt,
    required int durationMinutes,
    required String taskName,
  }) async {
    final List<AndroidNotificationAction> taskActions =
        await _buildReminderActions(_reviewTaskActionPrefix);
    final List<AndroidNotificationAction> actions = <AndroidNotificationAction>[
      const AndroidNotificationAction(
        _openLogActionId,
        'Log Now',
        showsUserInterface: true,
      ),
      const AndroidNotificationAction(
        _skipReminderActionId,
        'Skip',
        cancelNotification: true,
      ),
      ...taskActions,
    ];
    final DateTime rangeStart =
        scheduledAt.subtract(Duration(minutes: durationMinutes));
    final String body =
        'What did you do from ${_formatTime(rangeStart)}-${_formatTime(scheduledAt)}?';
    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId,
        _reminderChannelName,
        channelDescription: _reminderChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        ticker: 'Time Tracker reminder',
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        styleInformation: BigTextStyleInformation(
          '$body\nTap to log your activity or pick the task directly.',
        ),
        actions: actions,
      ),
    );
    await _notificationsPlugin.show(
      _reviewNotificationId,
      'Time Tracker',
      body,
      notificationDetails,
      payload: '$_reviewPayloadPrefix${scheduledAt.toIso8601String()}',
    );
  }

  static Future<void> _showBackgroundReminderNotification({
    required DateTime scheduledAt,
    required int durationMinutes,
  }) async {
    final FlutterLocalNotificationsPlugin notificationsPlugin =
        await createForegroundReminderPlugin();
    await _showBackgroundReminderNotificationWithPlugin(
      notificationsPlugin,
      scheduledAt: scheduledAt,
      durationMinutes: durationMinutes,
    );
  }

  static Future<void> _showBackgroundReminderNotificationWithPlugin(
    FlutterLocalNotificationsPlugin notificationsPlugin, {
    required DateTime scheduledAt,
    required int durationMinutes,
  }) async {
    final DateTime rangeStart =
        scheduledAt.subtract(Duration(minutes: durationMinutes));
    final String body =
        'What did you do from ${_formatTime(rangeStart)}-${_formatTime(scheduledAt)}?';
    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId,
        _reminderChannelName,
        channelDescription: _reminderChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        ticker: 'Time Tracker reminder',
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        styleInformation: BigTextStyleInformation(
          '$body\nTap to open Time Tracker and log your activity.',
        ),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            _openLogActionId,
            'Log Now',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            _skipReminderActionId,
            'Skip',
            cancelNotification: true,
          ),
        ],
      ),
    );

    await notificationsPlugin.show(
      _reviewNotificationId,
      'Time Tracker',
      body,
      notificationDetails,
      payload: '$_reviewPayloadPrefix${scheduledAt.toIso8601String()}',
    );
  }

  static Future<String> _currentReminderTaskName() async {
    final List<Task> tasks = await _taskService.getTasks();
    final String? selectedTaskId = await _taskService.getSelectedTaskId();
    if (selectedTaskId != null) {
      final Task? selectedTask = tasks.cast<Task?>().firstWhere(
        (Task? item) => item?.id == selectedTaskId,
        orElse: () => null,
      );
      if (selectedTask != null) {
        return selectedTask.name;
      }
    }

    final currentActivity = await _logService.getCurrentActivity();
    if (currentActivity != null) {
      final Task? currentTask = tasks.cast<Task?>().firstWhere(
        (Task? item) => item?.id == currentActivity.taskId,
        orElse: () => null,
      );
      if (currentTask != null) {
        return currentTask.name;
      }
    }

    return 'your work';
  }

  static Future<int> _currentReminderDurationMinutes() async {
    final List<Task> tasks = await _taskService.getTasks();
    final String? selectedTaskId = await _taskService.getSelectedTaskId();
    if (selectedTaskId != null) {
      final Task? selectedTask = tasks.cast<Task?>().firstWhere(
        (Task? item) => item?.id == selectedTaskId,
        orElse: () => null,
      );
      if (selectedTask != null && selectedTask.defaultMinutes > 0) {
        return selectedTask.defaultMinutes;
      }
    }

    final int savedDuration =
        await _settingsService.getNextReminderDurationMinutes();
    return savedDuration <= 0 ? _reminderIntervalMinutes : savedDuration;
  }

  static Future<void> _showReminderNotificationFromWork(
    Map<String, dynamic>? inputData,
  ) async {
    final DateTime scheduledAt =
        DateTime.tryParse(inputData?[_scheduledAtInputKey] as String? ?? '') ??
            DateTime.now();
    final DateTime firedAt = DateTime.now();
    final int durationMinutes =
        (inputData?[_durationInputKey] as int?) ?? _reminderIntervalMinutes;
    final int activeStartHour =
        (inputData?[_activeStartHourInputKey] as int?) ?? 7;
    final int activeEndHour =
        (inputData?[_activeEndHourInputKey] as int?) ?? 24;
    final DateTime nextReminderAt = _nextReviewTimeForWindow(
      firedAt,
      durationMinutes,
      activeStartHour,
      activeEndHour,
    );
    await _scheduleWorker(
      uniqueName: _reminderTaskUniqueName,
      taskName: _reminderTaskName,
      scheduledAt: nextReminderAt,
      inputData: <String, dynamic>{
        _scheduledAtInputKey: nextReminderAt.toIso8601String(),
        _durationInputKey: durationMinutes,
        _taskNameInputKey:
            inputData?[_taskNameInputKey] as String? ?? 'your work',
        _activeStartHourInputKey: activeStartHour,
        _activeEndHourInputKey: activeEndHour,
      },
    );
    await _persistNextReminderState(
      nextReminderAt: nextReminderAt,
      durationMinutes: durationMinutes,
    );
    await _showBackgroundReminderNotification(
      scheduledAt: scheduledAt,
      durationMinutes: durationMinutes,
    );
  }

  static Future<void> _showDailySummaryNotification() async {
    final bool enabled = await _settingsService.getDailySummaryEnabled();
    if (!enabled) {
      return;
    }

    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _statusChannelId,
        _statusChannelName,
        channelDescription: _statusChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    final String summaryText = await buildDailySummaryText(DateTime.now());
    await _notificationsPlugin.show(
      _dailySummaryNotificationId,
      'Your Day Summary',
      summaryText,
      notificationDetails,
      payload: _dailySummaryPayload,
    );
  }

  static Future<void> _showWeeklySummaryNotification() async {
    final bool enabled = await _settingsService.getWeeklySummaryEnabled();
    if (!enabled) {
      return;
    }

    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _statusChannelId,
        _statusChannelName,
        channelDescription: _statusChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    final String summaryText = await _buildWeeklySummaryText(DateTime.now());
    await _notificationsPlugin.show(
      _weeklySummaryNotificationId,
      'Your Week Summary',
      summaryText,
      notificationDetails,
      payload: _weeklySummaryPayload,
    );
  }

  static Future<void> _showDebugNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _debugChannelId,
      _debugChannelName,
      channelDescription: _debugChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      _scheduledDebugNotificationId,
      title,
      body,
      notificationDetails,
    );
  }

  static Future<void> _handleSkipReminder() async {
    final int durationMinutes =
        await _settingsService.getNextReminderDurationMinutes();
    final int effectiveDuration =
        durationMinutes <= 0 ? _reminderIntervalMinutes : durationMinutes;
    await planNextReminder(minutes: effectiveDuration);
  }

  static Future<void> _openLogActivityScreen() async {
    final NavigatorState? navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      return;
    }

    await navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const LogActivityScreen(),
      ),
    );
  }

  static Future<FlutterLocalNotificationsPlugin>
      createForegroundReminderPlugin() async {
    final FlutterLocalNotificationsPlugin notificationsPlugin =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );
    await notificationsPlugin.initialize(settings);

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannelId,
          _reminderChannelName,
          description: _reminderChannelDescription,
          importance: Importance.max,
        ),
      );
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          _statusChannelId,
          _statusChannelName,
          description: _statusChannelDescription,
          importance: Importance.defaultImportance,
        ),
      );
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          _debugChannelId,
          _debugChannelName,
          description: _debugChannelDescription,
          importance: Importance.max,
        ),
      );
    }

    return notificationsPlugin;
  }

  static Future<void> handleForegroundReminderTick(
    DateTime timestamp,
    FlutterLocalNotificationsPlugin notificationsPlugin,
  ) async {
    final bool remindersEnabled =
        await FlutterForegroundTask.getData<bool>(key: _remindersEnabledInputKey) ??
            false;
    if (!remindersEnabled) {
      return;
    }

    final String? scheduledAtRaw = await FlutterForegroundTask.getData<String>(
      key: _scheduledAtInputKey,
    );
    if (scheduledAtRaw == null) {
      return;
    }

    final DateTime? scheduledAt = DateTime.tryParse(scheduledAtRaw);
    if (scheduledAt == null || timestamp.isBefore(scheduledAt)) {
      return;
    }

    final int durationMinutes =
        await FlutterForegroundTask.getData<int>(key: _durationInputKey) ??
            _reminderIntervalMinutes;
    final String taskName =
        await FlutterForegroundTask.getData<String>(key: _taskNameInputKey) ??
            'your work';
    final int activeStartHour =
        await FlutterForegroundTask.getData<int>(key: _activeStartHourInputKey) ?? 7;
    final int activeEndHour =
        await FlutterForegroundTask.getData<int>(key: _activeEndHourInputKey) ?? 24;

    await _showBackgroundReminderNotificationWithPlugin(
      notificationsPlugin,
      scheduledAt: scheduledAt,
      durationMinutes: durationMinutes,
    );

    final DateTime nextReminderAt = _nextReviewTimeForWindow(
      timestamp,
      durationMinutes,
      activeStartHour,
      activeEndHour,
    );
    await _saveReminderServiceData(
      enabled: true,
      nextReminderAt: nextReminderAt,
      durationMinutes: durationMinutes,
      taskName: taskName,
      activeStartHour: activeStartHour,
      activeEndHour: activeEndHour,
    );
    await _persistNextReminderState(
      nextReminderAt: nextReminderAt,
      durationMinutes: durationMinutes,
    );
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Time Tracker Active',
      notificationText:
          'Next reminder at ${_formatTime(nextReminderAt)} for $taskName',
    );
  }

  static Future<void> _startOrUpdateReminderService({
    required DateTime scheduledAt,
    required int durationMinutes,
    required String taskName,
  }) async {
    final int activeStartHour = await _settingsService.getActiveStartHour();
    final int activeEndHour = await _settingsService.getActiveEndHour();
    await _saveReminderServiceData(
      enabled: true,
      nextReminderAt: scheduledAt,
      durationMinutes: durationMinutes,
      taskName: taskName,
      activeStartHour: activeStartHour,
      activeEndHour: activeEndHour,
    );
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Time Tracker Active',
        notificationText:
            'Next reminder at ${_formatTime(scheduledAt)} for $taskName',
      );
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Time Tracker Active',
        notificationText:
            'Next reminder at ${_formatTime(scheduledAt)} for $taskName',
        callback: reminderServiceStartCallback,
      );
    }
  }

  static Future<void> _saveReminderServiceData({
    required bool enabled,
    DateTime? nextReminderAt,
    int? durationMinutes,
    String? taskName,
    int? activeStartHour,
    int? activeEndHour,
  }) async {
    await FlutterForegroundTask.saveData(
      key: _remindersEnabledInputKey,
      value: enabled,
    );
    if (nextReminderAt != null) {
      await FlutterForegroundTask.saveData(
        key: _scheduledAtInputKey,
        value: nextReminderAt.toIso8601String(),
      );
    }
    if (durationMinutes != null) {
      await FlutterForegroundTask.saveData(
        key: _durationInputKey,
        value: durationMinutes,
      );
    }
    if (taskName != null) {
      await FlutterForegroundTask.saveData(key: _taskNameInputKey, value: taskName);
    }
    if (activeStartHour != null) {
      await FlutterForegroundTask.saveData(
        key: _activeStartHourInputKey,
        value: activeStartHour,
      );
    }
    if (activeEndHour != null) {
      await FlutterForegroundTask.saveData(
        key: _activeEndHourInputKey,
        value: activeEndHour,
      );
    }
  }

  static Future<void> _scheduleWorker({
    required String uniqueName,
    required String taskName,
    required DateTime scheduledAt,
    Map<String, dynamic>? inputData,
  }) async {
    final Duration delay = scheduledAt.difference(DateTime.now());
    await Workmanager().registerOneOffTask(
      uniqueName,
      taskName,
      initialDelay: delay.isNegative ? Duration.zero : delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      inputData: inputData,
    );
  }

  static Future<void> _scheduleDailySummaryWorker() async {
    final bool enabled = await _settingsService.getDailySummaryEnabled();
    await Workmanager().cancelByUniqueName(_dailySummaryTaskUniqueName);
    await _safeCancel(_dailySummaryNotificationId);
    if (!enabled) {
      return;
    }

    final DateTime scheduledAt = _nextDayAt(
      DateTime.now(),
      hour: await _settingsService.getDailySummaryHour(),
      minute: await _settingsService.getDailySummaryMinute(),
    );
    await _scheduleWorker(
      uniqueName: _dailySummaryTaskUniqueName,
      taskName: _dailySummaryTaskName,
      scheduledAt: scheduledAt,
    );
  }

  static Future<void> _scheduleWeeklySummaryWorker() async {
    final bool enabled = await _settingsService.getWeeklySummaryEnabled();
    await Workmanager().cancelByUniqueName(_weeklySummaryTaskUniqueName);
    await _safeCancel(_weeklySummaryNotificationId);
    if (!enabled) {
      return;
    }

    final DateTime scheduledAt = _nextWeekdayAt(
      DateTime.now(),
      weekday: await _settingsService.getWeeklySummaryWeekday(),
      hour: await _settingsService.getWeeklySummaryHour(),
      minute: await _settingsService.getWeeklySummaryMinute(),
    );
    await _scheduleWorker(
      uniqueName: _weeklySummaryTaskUniqueName,
      taskName: _weeklySummaryTaskName,
      scheduledAt: scheduledAt,
    );
  }

  static Future<void> _persistNextReminderState({
    required DateTime nextReminderAt,
    required int durationMinutes,
  }) async {
    try {
      await _settingsService.setNextReminderAt(nextReminderAt);
      await _settingsService.setNextReminderDurationMinutes(durationMinutes);
    } catch (_) {
      // Background reminder delivery should not depend on persistence.
    }
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

  static String _formatReminderDateTime(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String year = value.year.toString();
    return '$day-$month-$year, ${_formatTime(value)}, ${_weekdayName(value.weekday - 1)}';
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
