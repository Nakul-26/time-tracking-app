import 'dart:async';

import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import 'daily_stats_screen.dart';
import 'log_activity_screen.dart';
import 'retro_edit_screen.dart';
import 'settings_screen.dart';
import 'task_list_screen.dart';
import 'today_timeline_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final LogService _logService = LogService();
  final TaskService _taskService = TaskService();
  final SettingsService _settingsService = SettingsService();

  List<_ActivitySummary> _topActivities = const <_ActivitySummary>[];
  _CurrentActivitySummary? _currentActivity;
  int _loggedMinutes = 0;
  int _missingMinutes = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    await _loadDashboard();

    unawaited(_syncReminders());
  }

  Future<void> _syncReminders() async {
    try {
      final bool remindersEnabled = await _settingsService.getRemindersEnabled();

      if (remindersEnabled) {
        final ActivityLog? currentActivity = await _logService.getCurrentActivity();
        if (currentActivity == null) {
          await NotificationService.cancelReminder();
          return;
        }

        final List<Task> tasks = await _taskService.getTasks();
        final Task? task = tasks.cast<Task?>().firstWhere(
          (Task? item) => item?.id == currentActivity.taskId,
          orElse: () => null,
        );

        if (task == null) {
          await NotificationService.cancelReminder();
          return;
        }

        await NotificationService.scheduleReminder(
          when: DateTime.now().add(Duration(minutes: task.defaultMinutes)),
          minutes: task.defaultMinutes,
          taskName: task.name,
        );
      } else {
        await NotificationService.cancelReminder();
      }
    } catch (_) {
      // Keep the dashboard usable even if notification setup fails.
    }
  }

  Future<void> _loadDashboard() async {
    final List<ActivityLog> logs = await _logService.getLogs();
    final List<Task> tasks = await _taskService.getTasks();
    final DateTime now = DateTime.now();
    final Map<String, String> taskNamesById = <String, String>{
      for (final Task task in tasks) task.id: task.name,
    };
    final Map<String, int> taskMinutes = <String, int>{};
    final ActivityLog? currentActivity = await _logService.getCurrentActivity(now);

    for (final ActivityLog log in logs) {
      final int durationMinutes = _logService.overlapMinutesForDay(log, now, now: now);
      if (durationMinutes <= 0) {
        continue;
      }

      final String taskName = taskNamesById[log.taskId] ?? 'Unknown';
      taskMinutes[taskName] = (taskMinutes[taskName] ?? 0) + durationMinutes;
    }

    final int loggedMinutes = taskMinutes.values.fold(
      0,
      (int total, int value) => total + value,
    );
    final int minutesSinceMidnight = now.difference(
      DateTime(now.year, now.month, now.day),
    ).inMinutes;
    final List<_ActivitySummary> topActivities = taskMinutes.entries
        .map(
          (MapEntry<String, int> entry) => _ActivitySummary(
            taskName: entry.key,
            minutes: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.minutes.compareTo(a.minutes));

    if (!mounted) {
      return;
    }

    setState(() {
      _loggedMinutes = loggedMinutes;
      _missingMinutes = (minutesSinceMidnight - loggedMinutes).clamp(
        0,
        minutesSinceMidnight,
      );
      _topActivities = topActivities.take(3).toList();
      _currentActivity = currentActivity == null
          ? null
          : _CurrentActivitySummary(
              taskName: taskNamesById[currentActivity.taskId] ?? 'Unknown',
              startedAt: currentActivity.startTime,
              durationMinutes:
                  _logService.durationMinutesForLog(currentActivity, now: now),
            );
      _isLoading = false;
    });
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatClock(DateTime value) {
    final int hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final String minute = value.minute.toString().padLeft(2, '0');
    final String suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _formatDuration(int minutes) {
    if (minutes <= 0) {
      return '0m';
    }

    final int hours = minutes ~/ 60;
    final int remainingMinutes = minutes % 60;

    if (hours == 0) {
      return '${remainingMinutes}m';
    }

    if (remainingMinutes == 0) {
      return '${hours}h';
    }

    return '${hours}h ${remainingMinutes}m';
  }

  Color _missingAccentColor() {
    if (_missingMinutes <= 60) {
      return const Color(0xFF1E847F);
    }

    if (_missingMinutes <= 180) {
      return const Color(0xFFB35C2E);
    }

    return const Color(0xFFC74646);
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (BuildContext context) => screen));

    if (!mounted) {
      return;
    }

    await _loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: <Widget>[
          IconButton(
            onPressed: () => _openScreen(const SettingsScreen()),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadDashboard,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    Text(
                      'Your day at a glance.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _SummaryCard(
                            title: 'Logged Time',
                            value: _formatDuration(_loggedMinutes),
                            accentColor: const Color(0xFF1E847F),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            title: 'Missing Time',
                            value: _formatDuration(_missingMinutes),
                            accentColor: _missingAccentColor(),
                          ),
                        ),
                      ],
                    ),
                    if (_currentActivity != null) ...<Widget>[
                      const SizedBox(height: 24),
                      _CurrentActivityCard(
                        taskName: _currentActivity!.taskName,
                        startedAt: _formatClock(_currentActivity!.startedAt),
                        durationLabel:
                            _formatDuration(_currentActivity!.durationMinutes),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Top Activities',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_topActivities.isEmpty)
                      const _EmptyDashboardState()
                    else
                      ..._topActivities.map(
                        (_ActivitySummary activity) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ActivityCard(
                            taskName: activity.taskName,
                            durationLabel: _formatDuration(activity.minutes),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Quick Actions',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        _QuickActionButton(
                          icon: Icons.bolt,
                          label: 'Log Activity',
                          onPressed: () =>
                              _openScreen(const LogActivityScreen()),
                        ),
                        _QuickActionButton(
                          icon: Icons.history,
                          label: 'Retro Edit',
                          onPressed: () =>
                              _openScreen(const RetroEditScreen()),
                        ),
                        _QuickActionButton(
                          icon: Icons.timeline,
                          label: 'Timeline',
                          onPressed: () =>
                              _openScreen(const TodayTimelineScreen()),
                        ),
                        _QuickActionButton(
                          icon: Icons.bar_chart,
                          label: 'Stats',
                          onPressed: () =>
                              _openScreen(const DailyStatsScreen()),
                        ),
                        _QuickActionButton(
                          icon: Icons.checklist,
                          label: 'Tasks',
                          onPressed: () => _openScreen(const TaskListScreen()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ActivitySummary {
  const _ActivitySummary({required this.taskName, required this.minutes});

  final String taskName;
  final int minutes;
}

class _CurrentActivitySummary {
  const _CurrentActivitySummary({
    required this.taskName,
    required this.startedAt,
    required this.durationMinutes,
  });

  final String taskName;
  final DateTime startedAt;
  final int durationMinutes;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.accentColor,
  });

  final String title;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E7E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF56635D),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentActivityCard extends StatelessWidget {
  const _CurrentActivityCard({
    required this.taskName,
    required this.startedAt,
    required this.durationLabel,
  });

  final String taskName;
  final String startedAt;
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E7E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Currently Doing',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF56635D),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            taskName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Started $startedAt · $durationLabel so far',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF56635D),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.taskName, required this.durationLabel});

  final String taskName;
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7E2)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              taskName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            durationLabel,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E847F),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 158,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _EmptyDashboardState extends StatelessWidget {
  const _EmptyDashboardState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E7E2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.today, size: 48, color: Color(0xFF1E847F)),
          const SizedBox(height: 16),
          Text(
            'No activity logged yet',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use Log Activity to start building your day summary.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF56635D),
            ),
          ),
        ],
      ),
    );
  }
}
