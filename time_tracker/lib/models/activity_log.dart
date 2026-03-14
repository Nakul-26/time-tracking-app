class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.taskId,
    required this.startTime,
    this.endTime,
  });

  final String id;
  final String taskId;
  final DateTime startTime;
  final DateTime? endTime;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'taskId': taskId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
    };
  }

  factory ActivityLog.fromMap(String id, Map<dynamic, dynamic> map) {
    final String? rawStartTime = map['startTime'] as String?;
    final String? rawEndTime = map['endTime'] as String?;

    return ActivityLog(
      id: id,
      taskId: map['taskId'] as String? ?? '',
      startTime: DateTime.tryParse(rawStartTime ?? '') ?? DateTime.now(),
      endTime: rawEndTime == null || rawEndTime.isEmpty
          ? null
          : DateTime.tryParse(rawEndTime),
    );
  }
}
