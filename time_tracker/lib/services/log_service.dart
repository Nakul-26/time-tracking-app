import 'package:hive/hive.dart';

import '../models/activity_log.dart';

class LogService {
  static const String _logsBoxName = 'logs';
  static const Duration retroBlockSize = Duration(minutes: 5);
  static const int retroBlockCount = 6;

  Future<void> addLog(ActivityLog log) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_logsBoxName);
    await box.put(log.id, log.toMap());
  }

  Future<void> updateLog(ActivityLog log) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_logsBoxName);
    await box.put(log.id, log.toMap());
  }

  Future<void> deleteLog(String logId) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_logsBoxName);
    await box.delete(logId);
  }

  Future<List<ActivityLog>> getLogs() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_logsBoxName);
    final List<ActivityLog> logs = box.keys.map((dynamic key) {
      final dynamic rawLog = box.get(key, defaultValue: <String, dynamic>{});
      final Map<dynamic, dynamic> logMap =
          rawLog is Map<dynamic, dynamic> ? rawLog : <String, dynamic>{};

      return ActivityLog.fromMap(key.toString(), logMap);
    }).toList();

    logs.sort(
      (ActivityLog a, ActivityLog b) => b.startTime.compareTo(a.startTime),
    );
    return logs;
  }

  Future<ActivityLog?> getCurrentActivity([DateTime? now]) async {
    final List<ActivityLog> logs = await getLogs();
    final DateTime effectiveNow = now ?? DateTime.now();

    for (final ActivityLog log in logs) {
      if (log.startTime.isAfter(effectiveNow)) {
        continue;
      }

      if (log.endTime == null || log.endTime!.isAfter(effectiveNow)) {
        return log;
      }
    }

    return null;
  }

  Future<ActivityLog> startActivity(String taskId, [DateTime? now]) async {
    final DateTime startTime = now ?? DateTime.now();
    final ActivityLog? currentActivity = await getCurrentActivity(startTime);

    if (currentActivity != null) {
      await updateLog(
        ActivityLog(
          id: currentActivity.id,
          taskId: currentActivity.taskId,
          startTime: currentActivity.startTime,
          endTime: startTime,
        ),
      );
    }

    final ActivityLog log = ActivityLog(
      id: startTime.toIso8601String(),
      taskId: taskId,
      startTime: startTime,
      endTime: null,
    );

    await addLog(log);
    return log;
  }

  Future<void> scheduleRetroWindow(
    DateTime windowStart,
    List<String?> taskIds,
  ) async {
    final DateTime windowEnd = windowStart.add(
      Duration(minutes: retroBlockSize.inMinutes * taskIds.length),
    );
    final List<ActivityLog> logs = await getLogs();
    final Box<dynamic> box = await Hive.openBox<dynamic>(_logsBoxName);

    final List<ActivityLog> keptLogs = <ActivityLog>[];

    for (final ActivityLog log in logs) {
      final DateTime logEnd = log.endTime ?? DateTime.now();

      if (!log.startTime.isBefore(windowEnd) || !logEnd.isAfter(windowStart)) {
        keptLogs.add(log);
        continue;
      }

      if (log.startTime.isBefore(windowStart)) {
        keptLogs.add(
          ActivityLog(
            id: log.id,
            taskId: log.taskId,
            startTime: log.startTime,
            endTime: windowStart,
          ),
        );
      }

      if (logEnd.isAfter(windowEnd)) {
        keptLogs.add(
          ActivityLog(
            id: '${log.id}_after_${windowEnd.toIso8601String()}',
            taskId: log.taskId,
            startTime: windowEnd,
            endTime: log.endTime,
          ),
        );
      }
    }

    final List<ActivityLog> retroLogs = _buildLogsFromRetroBlocks(
      windowStart,
      taskIds,
    );

    await box.clear();

    for (final ActivityLog log in <ActivityLog>[...keptLogs, ...retroLogs]) {
      await box.put(log.id, log.toMap());
    }
  }

  List<String?> buildRetroBlockAssignments(
    List<ActivityLog> logs,
    DateTime windowStart, {
    DateTime? now,
  }) {
    final DateTime effectiveNow = now ?? DateTime.now();
    final List<String?> assignments = <String?>[];

    for (int index = 0; index < retroBlockCount; index += 1) {
      final DateTime blockStart =
          windowStart.add(Duration(minutes: index * retroBlockSize.inMinutes));
      final DateTime blockEnd = blockStart.add(retroBlockSize);

      String? taskId;

      for (final ActivityLog log in logs) {
        final DateTime logEnd = log.endTime ?? effectiveNow;
        if (log.startTime.isBefore(blockEnd) && logEnd.isAfter(blockStart)) {
          taskId = log.taskId;
          break;
        }
      }

      assignments.add(taskId);
    }

    return assignments;
  }

  int durationMinutesForLog(ActivityLog log, {DateTime? now}) {
    final DateTime effectiveEnd = log.endTime ?? (now ?? DateTime.now());
    final int minutes = effectiveEnd.difference(log.startTime).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  int overlapMinutesForDay(ActivityLog log, DateTime day, {DateTime? now}) {
    final DateTime startOfDay = DateTime(day.year, day.month, day.day);
    final DateTime endOfDay = startOfDay.add(const Duration(days: 1));
    final DateTime effectiveEnd = log.endTime ?? (now ?? DateTime.now());
    final DateTime overlapStart =
        log.startTime.isAfter(startOfDay) ? log.startTime : startOfDay;
    final DateTime overlapEnd =
        effectiveEnd.isBefore(endOfDay) ? effectiveEnd : endOfDay;

    if (!overlapEnd.isAfter(overlapStart)) {
      return 0;
    }

    return overlapEnd.difference(overlapStart).inMinutes;
  }

  DateTime retroWindowStart([DateTime? now]) {
    final DateTime effectiveNow = now ?? DateTime.now();
    return effectiveNow.subtract(
      Duration(minutes: retroBlockSize.inMinutes * retroBlockCount),
    );
  }

  List<ActivityLog> _buildLogsFromRetroBlocks(
    DateTime windowStart,
    List<String?> taskIds,
  ) {
    final List<ActivityLog> logs = <ActivityLog>[];
    String? activeTaskId;
    DateTime? activeStart;

    for (int index = 0; index < taskIds.length; index += 1) {
      final String? taskId = taskIds[index];
      final DateTime blockStart =
          windowStart.add(Duration(minutes: index * retroBlockSize.inMinutes));

      if (taskId == activeTaskId) {
        continue;
      }

      if (activeTaskId != null && activeStart != null) {
        logs.add(
          ActivityLog(
            id: activeStart.toIso8601String(),
            taskId: activeTaskId,
            startTime: activeStart,
            endTime: blockStart,
          ),
        );
      }

      activeTaskId = taskId;
      activeStart = taskId == null ? null : blockStart;
    }

    if (activeTaskId != null && activeStart != null) {
      logs.add(
        ActivityLog(
          id: activeStart.toIso8601String(),
          taskId: activeTaskId,
          startTime: activeStart,
          endTime: windowStart.add(
            Duration(minutes: retroBlockSize.inMinutes * taskIds.length),
          ),
        ),
      );
    }

    return logs;
  }
}
