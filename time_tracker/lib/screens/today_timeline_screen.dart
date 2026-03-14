import 'dart:async';

import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import 'retro_edit_screen.dart';

class TodayTimelineScreen extends StatefulWidget {
  const TodayTimelineScreen({super.key});

  @override
  State<TodayTimelineScreen> createState() => _TodayTimelineScreenState();
}

class _TodayTimelineScreenState extends State<TodayTimelineScreen> {
  final LogService _logService = LogService();
  final TaskService _taskService = TaskService();
  final SettingsService _settingsService = SettingsService();

  List<_TimelineEntry> _entries = const <_TimelineEntry>[];
  int _activeStartHour = 7;
  int _activeEndHour = 23;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTimeline();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        _loadTimeline();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTimeline() async {
    final List<ActivityLog> allLogs = await _logService.getLogs();
    final List<Task> tasks = await _taskService.getTasks();
    final int activeStartHour = await _settingsService.getActiveStartHour();
    final int activeEndHour = await _settingsService.getActiveEndHour();
    final DateTime now = DateTime.now();
    final DateTime windowStart = DateTime(
      now.year,
      now.month,
      now.day,
      activeStartHour,
    );
    final DateTime windowEnd = DateTime(
      now.year,
      now.month,
      now.day,
      activeEndHour,
    );
    final Map<String, Task> tasksById = <String, Task>{
      for (final Task task in tasks) task.id: task,
    };

    final List<_TimelineEntry> entries = allLogs
        .map(
          (ActivityLog log) => _clipLogToWindow(
            log: log,
            tasksById: tasksById,
            now: now,
            windowStart: windowStart,
            windowEnd: windowEnd,
          ),
        )
        .whereType<_TimelineEntry>()
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    if (!mounted) {
      return;
    }

    setState(() {
      _entries = entries;
      _activeStartHour = activeStartHour;
      _activeEndHour = activeEndHour;
      _isLoading = false;
    });
  }

  _TimelineEntry? _clipLogToWindow({
    required ActivityLog log,
    required Map<String, Task> tasksById,
    required DateTime now,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    if (!windowEnd.isAfter(windowStart)) {
      return null;
    }

    final DateTime effectiveEnd = log.endTime ?? now;
    final DateTime clippedStart =
        log.startTime.isBefore(windowStart) ? windowStart : log.startTime;
    final DateTime clippedEnd =
        effectiveEnd.isAfter(windowEnd) ? windowEnd : effectiveEnd;

    if (!clippedEnd.isAfter(clippedStart)) {
      return null;
    }

    final Task? task = tasksById[log.taskId];
    return _TimelineEntry(
      taskId: log.taskId,
      startTime: clippedStart,
      endTime: clippedEnd,
      label: task?.name ?? 'Unknown',
      color: _taskColor(log.taskId),
      isActive: log.endTime == null,
    );
  }

  Color _taskColor(String taskId) {
    const List<Color> palette = <Color>[
      Color(0xFF2E7D6B),
      Color(0xFF2F6DA3),
      Color(0xFFB35C2E),
      Color(0xFF7A4EAB),
      Color(0xFFC74646),
      Color(0xFF597445),
    ];
    final int index = taskId.codeUnits.fold<int>(
          0,
          (int value, int codeUnit) => value + codeUnit,
        ) %
        palette.length;
    return palette[index];
  }

  String _formatTime(DateTime value) {
    return TimeOfDay(hour: value.hour, minute: value.minute).format(context);
  }

  String _formatHour(int hour) {
    return TimeOfDay(hour: hour % 24, minute: 0).format(context);
  }

  List<String> _timelineMarkers() {
    final List<String> markers = <String>[];
    for (int hour = _activeStartHour; hour <= _activeEndHour; hour += 2) {
      markers.add(_formatHour(hour));
    }
    final String endMarker = _formatHour(_activeEndHour);
    if (markers.isEmpty || markers.last != endMarker) {
      markers.add(endMarker);
    }
    return markers;
  }

  Future<void> _openSessionSheet(_TimelineEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatTime(entry.startTime)} - ${_formatTime(entry.endTime)}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF56635D),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '${entry.minutes} minutes',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF7A867F),
                    ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(this.context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            const RetroEditScreen(),
                      ),
                    );
                  },
                  child: const Text('Adjust Last 30 Minutes'),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                      'See today as a visual flow across your active hours.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_formatHour(_activeStartHour)} - ${_formatHour(_activeEndHour)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF7A867F),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_entries.isEmpty)
                      const Expanded(child: _EmptyTimelineState())
                    else
                      Expanded(
                        child: ListView(
                          children: <Widget>[
                            _TimelineStrip(
                              entries: _entries,
                              markers: _timelineMarkers(),
                              onTapEntry: _openSessionSheet,
                            ),
                            const SizedBox(height: 20),
                            _TimelineLegend(entries: _entries),
                            const SizedBox(height: 20),
                            ..._entries.reversed.map(
                              (_TimelineEntry entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _TimelineCard(
                                  timeRange:
                                      '${_formatTime(entry.startTime)} - ${_formatTime(entry.endTime)}',
                                  label: entry.label,
                                  color: entry.color,
                                ),
                              ),
                            ),
                          ],
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
    required this.taskId,
    required this.startTime,
    required this.endTime,
    required this.label,
    required this.color,
    required this.isActive,
  });

  final String taskId;
  final DateTime startTime;
  final DateTime endTime;
  final String label;
  final Color color;
  final bool isActive;

  int get minutes => endTime.difference(startTime).inMinutes.clamp(1, 1440);
}

class _TimelineStrip extends StatelessWidget {
  const _TimelineStrip({
    required this.entries,
    required this.markers,
    required this.onTapEntry,
  });

  final List<_TimelineEntry> entries;
  final List<String> markers;
  final ValueChanged<_TimelineEntry> onTapEntry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E7E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Day Strip',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int index = 0; index < entries.length; index += 1) ...<Widget>[
                    Expanded(
                      flex: entries[index].minutes,
                      child: Tooltip(
                        message:
                            '${entries[index].label}\n${entries[index].minutes} min',
                        child: GestureDetector(
                          onTap: () => onTapEntry(entries[index]),
                          child: Container(
                            decoration: BoxDecoration(
                              color: entries[index].color,
                              borderRadius: BorderRadius.circular(4),
                              border: entries[index].isActive
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (index < entries.length - 1) const SizedBox(width: 2),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: markers
                .map(
                  (String marker) => Text(
                    marker,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF66746C),
                        ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _TimelineLegend extends StatelessWidget {
  const _TimelineLegend({required this.entries});

  final List<_TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final Map<String, _TimelineEntry> uniqueEntries = <String, _TimelineEntry>{
      for (final _TimelineEntry entry in entries) entry.taskId: entry,
    };

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: uniqueEntries.values
          .map(
            (_TimelineEntry entry) => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: entry.color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 6),
                Text(entry.label),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.timeRange,
    required this.label,
    required this.color,
  });

  final String timeRange;
  final String label;
  final Color color;

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
          Container(
            width: 10,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 14),
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
                color: const Color(0xFF15201B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
