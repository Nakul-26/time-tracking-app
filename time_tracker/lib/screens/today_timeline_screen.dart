import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/task_service.dart';

class TodayTimelineScreen extends StatefulWidget {
  const TodayTimelineScreen({super.key});

  @override
  State<TodayTimelineScreen> createState() => _TodayTimelineScreenState();
}

class _TodayTimelineScreenState extends State<TodayTimelineScreen> {
  final LogService _logService = LogService();
  final TaskService _taskService = TaskService();

  List<_TimelineEntry> _entries = const <_TimelineEntry>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    final List<ActivityLog> allLogs = await _logService.getLogs();
    final List<Task> tasks = await _taskService.getTasks();
    final DateTime now = DateTime.now();
    final Map<String, String> taskNamesById = <String, String>{
      for (final Task task in tasks) task.id: task.name,
    };
    final List<_TimelineEntry> entries = allLogs
        .where((ActivityLog log) => _logService.overlapMinutesForDay(log, now, now: now) > 0)
        .map(
          (ActivityLog log) => _TimelineEntry(
            startTime: log.startTime,
            endTime: log.endTime ?? now,
            label: taskNamesById[log.taskId] ?? 'Unknown',
            isLogged: true,
          ),
        )
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    if (!mounted) {
      return;
    }

    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatTime(DateTime value) {
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Today's Timeline")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'See today as real activity sessions instead of fixed blocks.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _entries.isEmpty
                          ? const _EmptyTimelineState()
                          : ListView.separated(
                              itemCount: _entries.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (BuildContext context, int index) {
                                final _TimelineEntry entry = _entries[index];
                                return _TimelineCard(
                                  timeRange:
                                      '${_formatTime(entry.startTime)} - ${_formatTime(entry.endTime)}',
                                  label: entry.label,
                                  isLogged: entry.isLogged,
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

class _EmptyTimelineState extends StatelessWidget {
  const _EmptyTimelineState();

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
            const Icon(Icons.timeline, size: 48, color: Color(0xFF1E847F)),
            const SizedBox(height: 16),
            Text(
              'No timeline yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start an activity or retroactively edit the last 30 minutes.',
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

class _TimelineEntry {
  const _TimelineEntry({
    required this.startTime,
    required this.endTime,
    required this.label,
    required this.isLogged,
  });

  final DateTime startTime;
  final DateTime endTime;
  final String label;
  final bool isLogged;
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.timeRange,
    required this.label,
    required this.isLogged,
  });

  final String timeRange;
  final String label;
  final bool isLogged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isLogged ? Colors.white : const Color(0xFFEFF3EF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLogged ? const Color(0xFFE1E7E2) : const Color(0xFFD7DFD8),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 118,
            child: Text(
              timeRange,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF33413A),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isLogged
                    ? const Color(0xFF15201B)
                    : const Color(0xFF66746C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
