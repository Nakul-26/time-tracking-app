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
      await NotificationService.scheduleTodayReminders();
    } else {
      await NotificationService.cancelAll();
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
                      'Get a reminder every 30 minutes to log your time.',
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
