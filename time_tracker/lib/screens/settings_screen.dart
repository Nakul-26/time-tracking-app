import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import 'task_list_screen.dart';

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
  int _activeStartHour = 7;
  int _activeEndHour = 23;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final bool remindersEnabled = await _settingsService.getRemindersEnabled();
    final int activeStartHour = await _settingsService.getActiveStartHour();
    final int activeEndHour = await _settingsService.getActiveEndHour();

    if (!mounted) {
      return;
    }

    setState(() {
      _remindersEnabled = remindersEnabled;
      _activeStartHour = activeStartHour;
      _activeEndHour = activeEndHour;
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
            when: currentActivity.startTime.add(
              Duration(minutes: task.defaultMinutes),
            ),
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

  Future<void> _sendTestNotification() async {
    await NotificationService.showTestNotification();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Test notification sent. Check your notification tray.'),
      ),
    );
  }

  Future<void> _showPendingCount() async {
    final int pendingCount = await NotificationService.pendingReminderCount();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pending notifications: $pendingCount'),
      ),
    );
  }

  Future<void> _openTaskListScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const TaskListScreen(),
      ),
    );
  }

  Future<void> _pickActiveStartHour() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _activeStartHour, minute: 0),
    );

    if (pickedTime == null) {
      return;
    }

    if (pickedTime.hour >= _activeEndHour) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start time must be before end time'),
        ),
      );
      return;
    }

    await _settingsService.setActiveStartHour(pickedTime.hour);

    if (!mounted) {
      return;
    }

    setState(() {
      _activeStartHour = pickedTime.hour;
    });
  }

  Future<void> _pickActiveEndHour() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _activeEndHour, minute: 0),
    );

    if (pickedTime == null) {
      return;
    }

    if (pickedTime.hour <= _activeStartHour) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time'),
        ),
      );
      return;
    }

    await _settingsService.setActiveEndHour(pickedTime.hour);

    if (!mounted) {
      return;
    }

    setState(() {
      _activeEndHour = pickedTime.hour;
    });
  }

  String _formatHour(int hour) {
    return TimeOfDay(hour: hour % 24, minute: 0).format(context);
  }

  int _trackingWindowHours() {
    return _activeEndHour - _activeStartHour;
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
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE1E7E2)),
                  ),
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('Active Start Time'),
                        subtitle: Text(_formatHour(_activeStartHour)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _pickActiveStartHour,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.nightlight_round),
                        title: const Text('Active End Time'),
                        subtitle: Text(_formatHour(_activeEndHour)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _pickActiveEndHour,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Tracking window: ${_trackingWindowHours()} hours',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF56635D),
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE1E7E2)),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.checklist),
                    title: const Text('Manage Tasks'),
                    subtitle: const Text(
                      'Add, edit, delete, and organize reusable tasks.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openTaskListScreen,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sendTestNotification,
                  child: const Text('Send Test Notification'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _showPendingCount,
                  child: const Text('Show Pending Notification Count'),
                ),
              ],
            ),
    );
  }
}
