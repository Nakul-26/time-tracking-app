import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  final LogService _logService = LogService();
  final TaskService _taskService = TaskService();

  bool _remindersEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final bool remindersEnabled =
        await _settingsService.getRemindersEnabled();

    if (!mounted) {
      return;
    }

    setState(() {
      _remindersEnabled = remindersEnabled;
      _isLoading = false;
    });
  }

  Future<void> _toggleReminders(bool enabled) async {
    setState(() {
      _remindersEnabled = enabled;
    });

    await _settingsService.setRemindersEnabled(enabled);

    if (enabled) {
      final currentActivity = await _logService.getCurrentActivity();
      if (currentActivity != null) {
        final List<Task> tasks = await _taskService.getTasks();
        final Task? task = tasks.cast<Task?>().firstWhere(
          (Task? item) => item?.id == currentActivity.taskId,
          orElse: () => null,
        );

        if (task != null) {
          await NotificationService.scheduleReminder(
            when: DateTime.now().add(Duration(minutes: task.defaultMinutes)),
            minutes: task.defaultMinutes,
            taskName: task.name,
          );
        }
      }
    } else {
      await NotificationService.cancelReminder();
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Reminder notifications enabled'
              : 'Reminder notifications disabled',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE1E7E2)),
                  ),
                  child: SwitchListTile(
                    title: const Text('Reminder Notifications'),
                    subtitle: const Text(
                      'Use each task’s default reminder length for the next check-in.',
                    ),
                    value: _remindersEnabled,
                    onChanged: _toggleReminders,
                  ),
                ),
              ],
            ),
    );
  }
}
