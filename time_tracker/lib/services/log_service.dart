import 'package:hive/hive.dart';

import '../models/activity_log.dart';

class LogService {
  static const String _logsBoxName = 'logs';
  static const Duration slotDuration = Duration(minutes: 30);
  static const Duration retroBlockSize = Duration(minutes: 5);
  static const int retroBlockCount = 6;
  static const Duration minimumLogDuration = Duration(seconds: 5);

  Future<void> addLog(ActivityLog log) async {
    if (!_isLogLongEnough(log)) {
      return;
    }

    final Box<dynamic> box = await Hive.openBox<dynamic>(_logsBoxName);
    await box.put(log.id, log.toMap());
  }

  Future<void> updateLog(ActivityLog log) async {
    if (!_isLogLongEnough(log)) {
      return;
    }

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

      return _normalizeLog(ActivityLog.fromMap(key.toString(), logMap));
    }).where(_isLogLongEnough).toList();

    logs.sort(
      (ActivityLog a, ActivityLog b) => b.startTime.compareTo(a.startTime),
    );
    return logs;
  }

  Future<ActivityLog?> getCurrentActivity([DateTime? now]) async {
    final DateTime effectiveNow = now ?? DateTime.now();
    final DateTime slotStart = subslotStartFor(effectiveNow);
    final DateTime slotEnd = slotStart.add(retroBlockSize);
    final List<ActivityLog> logs = await getLogs();

    for (final ActivityLog log in logs) {
      if (log.startTime.isAtSameMomentAs(slotStart) &&
          effectiveEndTime(log).isAtSameMomentAs(slotEnd)) {
        return log;
      }
    }

    return null;
  }

  Future<ActivityLog?> getLatestOpenActivity([DateTime? now]) {
    return getCurrentActivity(now);
  }

  Future<ActivityLog> startActivity(String taskId, [DateTime? now]) async {
    final DateTime effectiveNow = now ?? DateTime.now();
    final DateTime windowStart = slotStartFor(effectiveNow);
    final DateTime slotStart = subslotStartFor(effectiveNow);
    final List<ActivityLog> logs = await getLogs();
    final List<String?> existingAssignments = buildRetroBlockAssignments(
      logs,
      windowStart,
    );

    final bool alreadyFilled = existingAssignments.length == retroBlockCount &&
        existingAssignments.every((String? existingTaskId) => existingTaskId == taskId);
    if (!alreadyFilled) {
      await assignSlots(
        windowStart,
        List<String?>.filled(retroBlockCount, taskId),
      );
    }

    return ActivityLog(
      id: slotStart.toIso8601String(),
      taskId: taskId,
      startTime: slotStart,
      endTime: slotStart.add(retroBlockSize),
    );
  }

  Future<void> assignSlots(
    DateTime windowStart,
    List<String?> taskIds,
  ) async {
    final DateTime normalizedStart = subslotStartFor(windowStart);
    final DateTime windowEnd = normalizedStart.add(
      Duration(minutes: retroBlockSize.inMinutes * taskIds.length),
    );
    final List<ActivityLog> logs = await getLogs();
    final Box<dynamic> box = await Hive.openBox<dynamic>(_logsBoxName);
    final List<ActivityLog> rewrittenLogs = <ActivityLog>[];

    for (final ActivityLog log in logs) {
      final DateTime logEnd = effectiveEndTime(log);
      if (!log.startTime.isBefore(windowEnd) || !logEnd.isAfter(normalizedStart)) {
        rewrittenLogs.add(
          ActivityLog(
            id: log.startTime.toIso8601String(),
            taskId: log.taskId,
            startTime: log.startTime,
            endTime: logEnd,
          ),
        );
      }
    }

    for (int index = 0; index < taskIds.length; index += 1) {
      final String? taskId = taskIds[index];
      if (taskId == null) {
        continue;
      }

      final DateTime slotStart = normalizedStart.add(
        Duration(minutes: index * retroBlockSize.inMinutes),
      );
      rewrittenLogs.add(
        ActivityLog(
          id: slotStart.toIso8601String(),
          taskId: taskId,
          startTime: slotStart,
          endTime: slotStart.add(retroBlockSize),
        ),
      );
    }

    rewrittenLogs.sort(
      (ActivityLog a, ActivityLog b) => a.startTime.compareTo(b.startTime),
    );

    await box.clear();
    for (final ActivityLog log in rewrittenLogs) {
      await box.put(log.id, log.toMap());
    }
  }

  Future<void> scheduleRetroWindow(
    DateTime windowStart,
    List<String?> taskIds,
  ) async {
    await assignSlots(windowStart, taskIds);
  }

  List<String?> buildRetroBlockAssignments(
    List<ActivityLog> logs,
    DateTime windowStart, {
    DateTime? now,
  }) {
    return buildAssignmentsForRange(
      logs,
      windowStart,
      retroBlockCount,
      now: now,
    );
  }

  List<String?> buildAssignmentsForRange(
    List<ActivityLog> logs,
    DateTime rangeStart,
    int blockCount, {
    DateTime? now,
  }) {
    final DateTime normalizedStart = subslotStartFor(rangeStart);
    final List<String?> assignments = <String?>[];

    for (int index = 0; index < blockCount; index += 1) {
      final DateTime blockStart = normalizedStart.add(
        Duration(minutes: index * retroBlockSize.inMinutes),
      );
      final DateTime blockEnd = blockStart.add(retroBlockSize);

      String? taskId;
      for (final ActivityLog log in logs) {
        if (log.startTime.isAtSameMomentAs(blockStart) &&
            effectiveEndTime(log).isAtSameMomentAs(blockEnd)) {
          taskId = log.taskId;
          break;
        }
      }

      assignments.add(taskId);
    }

    return assignments;
  }

  int durationMinutesForLog(ActivityLog log, {DateTime? now}) {
    final int minutes = effectiveEndTime(log).difference(log.startTime).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  int overlapMinutesForDay(ActivityLog log, DateTime day, {DateTime? now}) {
    final DateTime startOfDay = DateTime(day.year, day.month, day.day);
    final DateTime endOfDay = startOfDay.add(const Duration(days: 1));
    final DateTime overlapStart =
        log.startTime.isAfter(startOfDay) ? log.startTime : startOfDay;
    final DateTime overlapEnd =
        effectiveEndTime(log).isBefore(endOfDay) ? effectiveEndTime(log) : endOfDay;

    if (!overlapEnd.isAfter(overlapStart)) {
      return 0;
    }

    return overlapEnd.difference(overlapStart).inMinutes;
  }

  DateTime effectiveEndTime(ActivityLog log, {DateTime? now}) {
    return log.endTime ?? log.startTime.add(retroBlockSize);
  }

  bool isActivityActive(ActivityLog log, {DateTime? now}) {
    final DateTime effectiveNow = now ?? DateTime.now();
    return !effectiveNow.isBefore(log.startTime) &&
        effectiveNow.isBefore(effectiveEndTime(log));
  }

  DateTime retroWindowStart([DateTime? now]) {
    final DateTime effectiveNow = now ?? DateTime.now();
    return slotStartFor(effectiveNow);
  }

  DateTime slotStartFor(DateTime value) {
    final int minute = value.minute < 30 ? 0 : 30;
    return DateTime(value.year, value.month, value.day, value.hour, minute);
  }

  DateTime slotEndFor(DateTime value) {
    return slotStartFor(value).add(slotDuration);
  }

  DateTime subslotStartFor(DateTime value) {
    final int flooredMinute = (value.minute ~/ retroBlockSize.inMinutes) *
        retroBlockSize.inMinutes;
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      flooredMinute,
    );
  }

  ActivityLog _normalizeLog(ActivityLog log) {
    final DateTime normalizedStart = subslotStartFor(log.startTime);
    final DateTime normalizedEnd = normalizedStart.add(retroBlockSize);
    final DateTime? endTime = log.endTime;

    if (endTime == null ||
        !log.startTime.isAtSameMomentAs(normalizedStart) ||
        !endTime.isAtSameMomentAs(normalizedEnd)) {
      return ActivityLog(
        id: normalizedStart.toIso8601String(),
        taskId: log.taskId,
        startTime: normalizedStart,
        endTime: normalizedEnd,
      );
    }

    return log;
  }

  bool _isLogLongEnough(ActivityLog log) {
    return effectiveEndTime(log).difference(log.startTime) >= minimumLogDuration;
  }
}
