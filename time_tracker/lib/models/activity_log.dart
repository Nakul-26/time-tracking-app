class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.taskId,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String taskId;
  final DateTime startTime;
  final DateTime endTime;

  Map<String, String> toMap() {
    return <String, String>{
      'taskId': taskId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
    };
  }

  factory ActivityLog.fromMap(String id, Map<dynamic, dynamic> map) {
    return ActivityLog(
      id: id,
      taskId: map['taskId'] as String? ?? '',
      startTime: DateTime.parse(map['startTime'] as String),
      endTime: DateTime.parse(map['endTime'] as String),
    );
  }
}
