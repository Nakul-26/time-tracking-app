import 'package:hive/hive.dart';

import '../models/task.dart';

class TaskService {
  static const String _tasksBoxName = 'tasks';
  static const String _settingsBoxName = 'task_settings';
  static const String _selectedTaskIdKey = 'selected_task_id';

  Future<void> addTask(Task task) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_tasksBoxName);
    await box.put(task.id, task.toMap());
  }

  Future<List<Task>> getTasks() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_tasksBoxName);
    final List<Task> tasks = box.keys.map((dynamic key) {
      final dynamic rawTask = box.get(key, defaultValue: <String, String>{});
      final Map<dynamic, dynamic> taskMap = rawTask is Map<dynamic, dynamic>
          ? rawTask
          : <String, String>{};

      return Task.fromMap(key.toString(), taskMap);
    }).toList();

    tasks.sort(
      (Task a, Task b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return tasks;
  }

  Future<void> setSelectedTaskId(String? taskId) async {
    final Box<dynamic> settingsBox = await Hive.openBox<dynamic>(
      _settingsBoxName,
    );

    if (taskId == null || taskId.isEmpty) {
      await settingsBox.delete(_selectedTaskIdKey);
      return;
    }

    await settingsBox.put(_selectedTaskIdKey, taskId);
  }

  Future<String?> getSelectedTaskId() async {
    final Box<dynamic> settingsBox = await Hive.openBox<dynamic>(
      _settingsBoxName,
    );
    final dynamic value = settingsBox.get(_selectedTaskIdKey);
    return value is String ? value : null;
  }
}
