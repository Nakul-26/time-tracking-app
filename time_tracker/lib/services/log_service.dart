import 'package:hive/hive.dart';

import '../models/activity_log.dart';

class LogService {
  static const String _logsBoxName = 'logs';

  Future<void> addLog(ActivityLog log) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_logsBoxName);
    await box.put(log.id, log.toMap());
  }

  Future<List<ActivityLog>> getLogs() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_logsBoxName);
    final List<ActivityLog> logs = box.keys.map((dynamic key) {
      final dynamic rawLog = box.get(key, defaultValue: <String, String>{});
      final Map<dynamic, dynamic> logMap =
          rawLog is Map<dynamic, dynamic> ? rawLog : <String, String>{};

      return ActivityLog.fromMap(key.toString(), logMap);
    }).toList();

    logs.sort((ActivityLog a, ActivityLog b) => b.startTime.compareTo(a.startTime));
    return logs;
  }

  DateTime currentBlockStart([DateTime? now]) {
    final DateTime value = now ?? DateTime.now();
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      (value.minute ~/ 30) * 30,
    );
  }

  ActivityLog createCurrentBlockLog(String taskId, [DateTime? now]) {
    final DateTime startTime = currentBlockStart(now);
    final DateTime endTime = startTime.add(const Duration(minutes: 30));

    return ActivityLog(
      id: startTime.toIso8601String(),
      taskId: taskId,
      startTime: startTime,
      endTime: endTime,
    );
  }
}
