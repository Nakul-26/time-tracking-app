import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/task_service.dart';

class DailyStatsScreen extends StatefulWidget {
  const DailyStatsScreen({super.key});

  @override
  State<DailyStatsScreen> createState() => _DailyStatsScreenState();
}

class _DailyStatsScreenState extends State<DailyStatsScreen> {
  final LogService _logService = LogService();
  final TaskService _taskService = TaskService();

  List<_TaskStat> _taskStats = const <_TaskStat>[];
  int _loggedMinutes = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final List<ActivityLog> logs = await _logService.getLogs();
    final List<Task> tasks = await _taskService.getTasks();
    final DateTime now = DateTime.now();
    final Map<String, String> taskNamesById = <String, String>{
      for (final Task task in tasks) task.id: task.name,
    };
    final Map<String, int> taskMinutes = <String, int>{};

    for (final ActivityLog log in logs) {
      if (!_isSameDay(log.startTime, now)) {
        continue;
      }

      final String taskName = taskNamesById[log.taskId] ?? 'Unknown';
      final int durationMinutes = log.endTime.difference(log.startTime).inMinutes;
      taskMinutes[taskName] = (taskMinutes[taskName] ?? 0) + durationMinutes;
    }

    final List<_TaskStat> stats = taskMinutes.entries
        .map(
          (MapEntry<String, int> entry) => _TaskStat(
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
      _taskStats = stats;
      _loggedMinutes = taskMinutes.values.fold(
        0,
        (int total, int value) => total + value,
      );
      _isLoading = false;
    });
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatDuration(int minutes) {
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Today's Stats")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
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
                            'Logged today',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF56635D),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatDuration(_loggedMinutes),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Time spent by activity',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _taskStats.isEmpty
                          ? const _EmptyStatsState()
                          : ListView.separated(
                              itemCount: _taskStats.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (BuildContext context, int index) {
                                final _TaskStat stat = _taskStats[index];
                                return _StatsCard(
                                  taskName: stat.taskName,
                                  durationLabel: _formatDuration(stat.minutes),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _TaskStat {
  const _TaskStat({required this.taskName, required this.minutes});

  final String taskName;
  final int minutes;
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.taskName, required this.durationLabel});

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

class _EmptyStatsState extends StatelessWidget {
  const _EmptyStatsState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Container(
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
            const Icon(Icons.bar_chart, size: 48, color: Color(0xFF1E847F)),
            const SizedBox(height: 16),
            Text(
              'No stats for today',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Log a few activities and this screen will show where your time went.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF56635D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
