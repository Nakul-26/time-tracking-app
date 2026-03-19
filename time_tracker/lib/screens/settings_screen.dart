import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();

  bool _remindersEnabled = true;
  bool _dailySummaryEnabled = true;
  bool _weeklySummaryEnabled = true;
  int _activeStartHour = 7;
  int _activeEndHour = 24;
  int _dailySummaryHour = 22;
  int _dailySummaryMinute = 30;
  int _weeklySummaryWeekday = 7;
  int _weeklySummaryHour = 21;
  int _weeklySummaryMinute = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final bool remindersEnabled = await _settingsService.getRemindersEnabled();
    final bool dailySummaryEnabled =
        await _settingsService.getDailySummaryEnabled();
    final bool weeklySummaryEnabled =
        await _settingsService.getWeeklySummaryEnabled();
    final int activeStartHour = await _settingsService.getActiveStartHour();
    final int activeEndHour = await _settingsService.getActiveEndHour();
    final int dailySummaryHour = await _settingsService.getDailySummaryHour();
    final int dailySummaryMinute =
        await _settingsService.getDailySummaryMinute();
    final int weeklySummaryWeekday =
        await _settingsService.getWeeklySummaryWeekday();
    final int weeklySummaryHour = await _settingsService.getWeeklySummaryHour();
    final int weeklySummaryMinute =
        await _settingsService.getWeeklySummaryMinute();

    if (!mounted) {
      return;
    }

    setState(() {
      _remindersEnabled = remindersEnabled;
      _dailySummaryEnabled = dailySummaryEnabled;
      _weeklySummaryEnabled = weeklySummaryEnabled;
      _activeStartHour = activeStartHour;
      _activeEndHour = activeEndHour;
      _dailySummaryHour = dailySummaryHour;
      _dailySummaryMinute = dailySummaryMinute;
      _weeklySummaryWeekday = weeklySummaryWeekday;
      _weeklySummaryHour = weeklySummaryHour;
      _weeklySummaryMinute = weeklySummaryMinute;
      _isLoading = false;
    });
  }

  Future<void> _toggleReminders(bool enabled) async {
    setState(() {
      _remindersEnabled = enabled;
    });

    await _settingsService.setRemindersEnabled(enabled);

    if (enabled) {
      await NotificationService.syncReminders();
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

  Future<void> _toggleDailySummary(bool enabled) async {
    setState(() {
      _dailySummaryEnabled = enabled;
    });
    await _settingsService.setDailySummaryEnabled(enabled);
    await NotificationService.syncSummaryNotifications();
  }

  Future<void> _toggleWeeklySummary(bool enabled) async {
    setState(() {
      _weeklySummaryEnabled = enabled;
    });
    await _settingsService.setWeeklySummaryEnabled(enabled);
    await NotificationService.syncSummaryNotifications();
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
    try {
      final String status = await NotificationService.reminderDebugStatus();

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Reminder Status'),
            content: SelectableText(status),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Reminder Status Failed'),
            content: SelectableText(error.toString()),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _requestExactAlarmPermission() async {
    try {
      final bool granted =
          await NotificationService.requestExactAlarmPermission();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'Exact alarm access enabled'
                : 'Exact alarm access is still disabled',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Exact Alarm Failed'),
            content: SelectableText(error.toString()),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _pickActiveStartHour() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _activeStartHour, minute: 0),
    );

    if (!mounted) {
      return;
    }

    if (pickedTime == null) {
      return;
    }

    if (_activeEndHour != 24 && pickedTime.hour >= _activeEndHour) {
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
    final bool? useFullDay = await showModalBottomSheet<bool>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Pick End Time'),
                onTap: () => Navigator.of(context).pop(false),
              ),
              ListTile(
                leading: const Icon(Icons.all_inclusive),
                title: const Text('Set to 24:00'),
                onTap: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        );
      },
    );

    if (useFullDay == null) {
      return;
    }

    if (useFullDay) {
      await _settingsService.setActiveEndHour(24);

      if (!mounted) {
        return;
      }

      setState(() {
        _activeEndHour = 24;
      });
      return;
    }

    if (!mounted) {
      return;
    }

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _activeEndHour == 24 ? 23 : _activeEndHour, minute: 0),
    );

    if (!mounted) {
      return;
    }

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
    if (hour == 24) {
      return '24:00';
    }
    return TimeOfDay(hour: hour % 24, minute: 0).format(context);
  }

  String _formatTimeOfDay(int hour, int minute) {
    return TimeOfDay(hour: hour, minute: minute).format(context);
  }

  String _weekdayLabel(int weekday) {
    const List<String> labels = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return labels[(weekday - 1).clamp(0, 6)];
  }

  int _trackingWindowHours() {
    if (_settingsService.isFullDayWindow(_activeStartHour, _activeEndHour)) {
      return 24;
    }
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
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1F8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD5E1EE)),
                  ),
                  child: const Text(
                    'Use this page only for reminders and active hours. Manage tasks from the Tasks tab.',
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE1E7E2)),
                  ),
                  child: SwitchListTile(
                    title: const Text('Reminder Notifications'),
                    subtitle: const Text(
                      'Primary workflow: wait for the notification, review the last interval, then choose what is next.',
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
                  child: Column(
                    children: <Widget>[
                      SwitchListTile(
                        title: const Text('Enable Daily Summary'),
                        subtitle: Text(
                          'Daily Summary: ${_formatTimeOfDay(_dailySummaryHour, _dailySummaryMinute)}',
                        ),
                        value: _dailySummaryEnabled,
                        onChanged: _toggleDailySummary,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.today),
                        title: const Text('Daily Summary Time'),
                        subtitle: Text(
                          _formatTimeOfDay(
                            _dailySummaryHour,
                            _dailySummaryMinute,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final TimeOfDay? picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: _dailySummaryHour,
                              minute: _dailySummaryMinute,
                            ),
                          );
                          if (picked == null) {
                            return;
                          }
                          await _settingsService.setDailySummaryTime(
                            hour: picked.hour,
                            minute: picked.minute,
                          );
                          await NotificationService.syncSummaryNotifications();
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _dailySummaryHour = picked.hour;
                            _dailySummaryMinute = picked.minute;
                          });
                        },
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
                  child: Column(
                    children: <Widget>[
                      SwitchListTile(
                        title: const Text('Enable Weekly Summary'),
                        subtitle: Text(
                          'Weekly Summary: ${_weekdayLabel(_weeklySummaryWeekday)} ${_formatTimeOfDay(_weeklySummaryHour, _weeklySummaryMinute)}',
                        ),
                        value: _weeklySummaryEnabled,
                        onChanged: _toggleWeeklySummary,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.date_range),
                        title: const Text('Weekly Summary Day'),
                        subtitle: Text(_weekdayLabel(_weeklySummaryWeekday)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final int? selected = await showModalBottomSheet<int>(
                            context: context,
                            builder: (BuildContext context) {
                              return SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List<Widget>.generate(7, (index) {
                                    final int weekday = index + 1;
                                    return ListTile(
                                      title: Text(_weekdayLabel(weekday)),
                                      onTap: () =>
                                          Navigator.of(context).pop(weekday),
                                    );
                                  }),
                                ),
                              );
                            },
                          );
                          if (selected == null) {
                            return;
                          }
                          await _settingsService.setWeeklySummarySchedule(
                            weekday: selected,
                            hour: _weeklySummaryHour,
                            minute: _weeklySummaryMinute,
                          );
                          await NotificationService.syncSummaryNotifications();
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _weeklySummaryWeekday = selected;
                          });
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.query_builder),
                        title: const Text('Weekly Summary Time'),
                        subtitle: Text(
                          _formatTimeOfDay(
                            _weeklySummaryHour,
                            _weeklySummaryMinute,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final TimeOfDay? picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: _weeklySummaryHour,
                              minute: _weeklySummaryMinute,
                            ),
                          );
                          if (picked == null) {
                            return;
                          }
                          await _settingsService.setWeeklySummarySchedule(
                            weekday: _weeklySummaryWeekday,
                            hour: picked.hour,
                            minute: picked.minute,
                          );
                          await NotificationService.syncSummaryNotifications();
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _weeklySummaryHour = picked.hour;
                            _weeklySummaryMinute = picked.minute;
                          });
                        },
                      ),
                    ],
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
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _requestExactAlarmPermission,
                  child: const Text('Enable Exact Alarm Access'),
                ),
              ],
            ),
    );
  }
}
