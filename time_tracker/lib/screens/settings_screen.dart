import 'package:flutter/material.dart';

import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();

  int _activeStartHour = 7;
  int _activeEndHour = 24;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final int activeStartHour = await _settingsService.getActiveStartHour();
    final int activeEndHour = await _settingsService.getActiveEndHour();

    if (!mounted) {
      return;
    }

    setState(() {
      _activeStartHour = activeStartHour;
      _activeEndHour = activeEndHour;
      _isLoading = false;
    });
  }

  Future<void> _pickActiveStartHour() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _activeStartHour, minute: 0),
    );

    if (!mounted || pickedTime == null) {
      return;
    }

    if (_activeEndHour != 24 && pickedTime.hour >= _activeEndHour) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start time must be before end time')),
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
      initialTime: TimeOfDay(
        hour: _activeEndHour == 24 ? 23 : _activeEndHour,
        minute: 0,
      ),
    );

    if (!mounted || pickedTime == null) {
      return;
    }

    if (pickedTime.hour <= _activeStartHour) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
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
                    'Reminders are intentionally out of scope here. Use an external app like Clock, Calendar, or Keep, then come back here only for logging and review.',
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE1E7E2)),
                  ),
                  child: const ListTile(
                    leading: Icon(Icons.alarm),
                    title: Text('Reminders'),
                    subtitle: Text(
                      'Use an external app to get notified. Recommended cadence: every 30 minutes.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE1E7E2)),
                  ),
                  child: const Column(
                    children: <Widget>[
                      ListTile(
                        leading: Icon(Icons.build_circle_outlined),
                        title: Text('How To Set Reminders'),
                        subtitle: Text(
                          'Recommended apps: Google Clock, Google Calendar, Google Keep.',
                        ),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.looks_one_outlined),
                        title: Text('Step 1'),
                        subtitle: Text(
                          'Open Clock or your preferred reminder app.',
                        ),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.looks_two_outlined),
                        title: Text('Step 2'),
                        subtitle: Text(
                          'Create a repeating reminder every 30 minutes.',
                        ),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.looks_3_outlined),
                        title: Text('Step 3'),
                        subtitle: Text(
                          'Label it "Log Time" so the intent is obvious.',
                        ),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.looks_4_outlined),
                        title: Text('Step 4'),
                        subtitle: Text(
                          'When it rings, open Time Tracker and log what you just did.',
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
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF56635D)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
