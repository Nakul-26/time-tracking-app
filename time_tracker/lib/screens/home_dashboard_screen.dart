import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import 'daily_stats_screen.dart';
import 'log_activity_screen.dart';
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
  int _loggedMinutes = 0;
  int _missingMinutes = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    final bool remindersEnabled =
        await _settingsService.getRemindersEnabled();

    if (remindersEnabled) {
      await NotificationService.scheduleTodayReminders();
    } else {
      await NotificationService.cancelAll();
    }

    await _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final List<ActivityLog> logs = await _logService.getLogs();
    final List<Task> tasks = await _taskService.getTasks();
    final DateTime now = DateTime.now();
    final Map<String, String> taskNamesById = <String, String>{
      for (final Task task in tasks) task.id: task.name,
    };
    final Map<String, int> taskMinutes = <String, int>{};
    final Set<String> loggedBlockIds = <String>{};

    for (final ActivityLog log in logs) {
      if (!_isSameDay(log.startTime, now)) {
        continue;
      }

      final int durationMinutes = log.endTime.difference(log.startTime).inMinutes;
      final String taskName = taskNamesById[log.taskId] ?? 'Unknown';
      taskMinutes[taskName] = (taskMinutes[taskName] ?? 0) + durationMinutes;
      loggedBlockIds.add(log.id);
    }

    final int loggedMinutes = taskMinutes.values.fold(
      0,
      (int total, int value) => total + value,
    );
    final int totalSlotsSoFar = _totalSlotsSoFar(now);
    final int missingSlots =
        (totalSlotsSoFar - loggedBlockIds.length).clamp(0, totalSlotsSoFar);
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
      _missingMinutes = missingSlots * 30;
      _topActivities = topActivities.take(3).toList();
      _isLoading = false;
    });
  }

  int _totalSlotsSoFar(DateTime now) {
    return (now.hour * 2) + (now.minute ~/ 30);
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
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
