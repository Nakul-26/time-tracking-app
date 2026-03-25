import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../services/stats_service.dart';
import '../services/task_service.dart';

class DailyStatsScreen extends StatefulWidget {
  const DailyStatsScreen({super.key});

  @override
  State<DailyStatsScreen> createState() => _DailyStatsScreenState();
}

class _DailyStatsScreenState extends State<DailyStatsScreen> {
  final TaskService _taskService = TaskService();
  late final StatsService _statsService;

  List<_TaskStat> _dailyTaskStats = const <_TaskStat>[];
  List<_TaskStat> _weeklyTaskStats = const <_TaskStat>[];
  List<_DayTotal> _weeklyDailyTotals = const <_DayTotal>[];
  List<StatsWeekdayTimeline> _weeklyTimeline = const <StatsWeekdayTimeline>[];
  List<StatsHeatmapDay> _monthlyHeatmap = const <StatsHeatmapDay>[];
  Map<String, String> _taskNamesById = const <String, String>{};
  Duration _dailyLogged = Duration.zero;
  Duration _dailyMissing = Duration.zero;
  Duration _weeklyLogged = Duration.zero;
  Duration _weeklyMissing = Duration.zero;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _statsService = StatsService(LogService(), SettingsService());
    _loadStats();
  }

  Future<void> _loadStats() async {
    final List<Task> tasks = await _taskService.getTasks();
    final Map<String, String> taskNamesById = <String, String>{
      for (final Task task in tasks) task.id: task.name,
    };
    final DateTime now = DateTime.now();

    final Map<String, Duration> dailyTaskTotals =
        await _statsService.getDailyTaskTotals(now);
    final Map<String, Duration> weeklyTaskTotals =
        await _statsService.getWeeklyTaskTotals(now);
    final Map<int, Duration> weeklyDailyTotals =
        await _statsService.getWeeklyDailyTotals(now);
    final List<StatsWeekdayTimeline> weeklyTimeline =
        await _statsService.getWeeklyTimeline(now);
    final List<StatsHeatmapDay> monthlyHeatmap =
        await _statsService.getMonthlyHeatmap(now);
    final Duration dailyMissing = await _statsService.getDailyMissingTime(now);
    final Duration weeklyMissing = await _statsService.getWeeklyMissingTime(now);

    if (!mounted) {
      return;
    }

    setState(() {
      _dailyTaskStats = _mapTaskTotals(
        dailyTaskTotals,
        taskNamesById,
      );
      _taskNamesById = taskNamesById;
      _weeklyTaskStats = _mapTaskTotals(
        weeklyTaskTotals,
        taskNamesById,
      );
      _weeklyDailyTotals = <_DayTotal>[
        for (int index = 0; index < 7; index += 1)
          _DayTotal(
            label: _weekdayLabel(index),
            duration: weeklyDailyTotals[index] ?? Duration.zero,
          ),
      ];
      _dailyLogged = dailyTaskTotals.values.fold(
        Duration.zero,
        (Duration total, Duration value) => total + value,
      );
      _dailyMissing = dailyMissing;
      _weeklyLogged = weeklyTaskTotals.values.fold(
        Duration.zero,
        (Duration total, Duration value) => total + value,
      );
      _weeklyTimeline = weeklyTimeline;
      _monthlyHeatmap = monthlyHeatmap;
      _weeklyMissing = weeklyMissing;
      _isLoading = false;
    });
  }

  List<_TaskStat> _mapTaskTotals(
    Map<String, Duration> totals,
    Map<String, String> taskNamesById,
  ) {
    final List<_TaskStat> stats = totals.entries
        .map(
          (MapEntry<String, Duration> entry) => _TaskStat(
            taskName: taskNamesById[entry.key] ?? 'Unknown',
            duration: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.duration.compareTo(a.duration));
    return stats;
  }

  String _weekdayLabel(int index) {
    const List<String> labels = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    return labels[index];
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

  Color _heatmapColor(double intensity) {
    if (intensity <= 0) {
      return const Color(0xFFE8EDE9);
    }
    if (intensity < 0.25) {
      return const Color(0xFFBFD4F4);
    }
    if (intensity < 0.5) {
      return const Color(0xFF7FA7E8);
    }
    if (intensity < 0.75) {
      return const Color(0xFF467FD9);
    }
    return const Color(0xFF1F56B5);
  }

  List<Widget> _buildHeatmapCells() {
    if (_monthlyHeatmap.isEmpty) {
      return const <Widget>[];
    }

    final DateTime monthStart = DateTime(
      _monthlyHeatmap.first.date.year,
      _monthlyHeatmap.first.date.month,
      1,
    );
    final int leadingBlanks = monthStart.weekday - 1;
    final List<Widget> cells = <Widget>[
      for (int index = 0; index < leadingBlanks; index += 1)
        const SizedBox.shrink(),
    ];

    cells.addAll(
      _monthlyHeatmap.map(
        (StatsHeatmapDay day) => Tooltip(
          message:
              '${day.date.day}/${day.date.month}\n${_statsService.formatDuration(day.logged)}',
          child: Container(
            decoration: BoxDecoration(
              color: _heatmapColor(day.intensity),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              '${day.date.day}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: day.intensity >= 0.5
                        ? Colors.white
                        : const Color(0xFF33413A),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );

    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  Text(
                    'Daily Overview',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _SummaryCard(
                          title: 'Logged Today',
                          value: _statsService.formatDuration(_dailyLogged),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          title: 'Missing Today',
                          value: _statsService.formatDuration(_dailyMissing),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Today by Activity',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_dailyTaskStats.isEmpty)
                    const _EmptyStatsState(
                      title: 'No stats for today',
                      message:
                          'Log a few activities and this section will show where your time went.',
                    )
                  else
                    ..._dailyTaskStats.map(
                      (_TaskStat stat) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _StatsCard(
                          taskName: stat.taskName,
                          durationLabel:
                              _statsService.formatDuration(stat.duration),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'This Week',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _SummaryCard(
                          title: 'Logged This Week',
                          value: _statsService.formatDuration(_weeklyLogged),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          title: 'Missing This Week',
                          value: _statsService.formatDuration(_weeklyMissing),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Weekly Timeline',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._weeklyTimeline.map(
                    (StatsWeekdayTimeline dayTimeline) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _WeeklyTimelineRow(
                        label: _weekdayLabel(dayTimeline.day.weekday - 1),
                        segments: dayTimeline.segments
                            .map(
                              (StatsTimelineSegment segment) => _WeekSegmentView(
                                label: segment.taskId == StatsService.unknownTaskId
                                    ? 'Unknown'
                                    : _taskNamesById[segment.taskId] ?? 'Unknown',
                                minutes: segment.minutes,
                                color: segment.taskId == StatsService.unknownTaskId
                                    ? const Color(0xFFD7DCD8)
                                    : _taskColor(segment.taskId),
                                isActive: segment.isActive,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Top Activities This Week',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_weeklyTaskStats.isEmpty)
                    const _EmptyStatsState(
                      title: 'No weekly stats yet',
                      message:
                          'Keep logging activities and this week view will start to fill in.',
                    )
                  else
                    ..._weeklyTaskStats.take(5).map(
                      (_TaskStat stat) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _StatsCard(
                          taskName: stat.taskName,
                          durationLabel:
                              _statsService.formatDuration(stat.duration),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Daily Breakdown',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._weeklyDailyTotals.map(
                    (_DayTotal total) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _StatsCard(
                        taskName: total.label,
                        durationLabel:
                            _statsService.formatDuration(total.duration),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'This Month',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MonthlyHeatmap(
                    weekdayLabels: const <String>[
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                      'Sun',
                    ],
                    cells: _buildHeatmapCells(),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TaskStat {
  const _TaskStat({required this.taskName, required this.duration});

  final String taskName;
  final Duration duration;
}

class _DayTotal {
  const _DayTotal({required this.label, required this.duration});

  final String label;
  final Duration duration;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value});

  final String title;
  final String value;

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
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekSegmentView {
  const _WeekSegmentView({
    required this.label,
    required this.minutes,
    required this.color,
    required this.isActive,
  });

  final String label;
  final int minutes;
  final Color color;
  final bool isActive;
}

class _WeeklyTimelineRow extends StatelessWidget {
  const _WeeklyTimelineRow({
    required this.label,
    required this.segments,
  });

  final String label;
  final List<_WeekSegmentView> segments;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7E2)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 22,
                child: segments.isEmpty
                    ? Container(color: const Color(0xFFE8EDE9))
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (int index = 0;
                              index < segments.length;
                              index += 1) ...<Widget>[
                            Expanded(
                              flex: segments[index].minutes,
                              child: Tooltip(
                                message:
                                    '${segments[index].label}\n${segments[index].minutes} min',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: segments[index].color,
                                    border: segments[index].isActive
                                        ? Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                            if (index < segments.length - 1)
                              const SizedBox(width: 2),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyHeatmap extends StatelessWidget {
  const _MonthlyHeatmap({
    required this.weekdayLabels,
    required this.cells,
  });

  final List<String> weekdayLabels;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weekdayLabels
                .map(
                  (String label) => Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: const Color(0xFF66746C),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1,
            children: cells,
          ),
        ],
      ),
    );
  }
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
  const _EmptyStatsState({required this.title, required this.message});

  final String title;
  final String message;

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
          const Icon(Icons.bar_chart, size: 48, color: Color(0xFF1E847F)),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
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
