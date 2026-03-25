import 'dart:async';

import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import 'log_activity_screen.dart';
import 'retro_edit_screen.dart';
import 'task_list_screen.dart';

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
  List<Task> _tasks = const <Task>[];
  List<String> _recentTaskIds = const <String>[];
  _CurrentActivitySummary? _currentActivity;
  String? _selectedTaskId;
  int _loggedMinutes = 0;
  int _missingMinutes = 0;
  int _activeStartHour = 7;
  int _activeEndHour = 24;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final List<ActivityLog> logs = await _logService.getLogs();
    final List<Task> tasks = await _taskService.getTasks();
    final List<String> recentTaskIds = _buildRecentTaskIds(logs);
    final String? selectedTaskId = await _taskService.getSelectedTaskId();
    final int activeStartHour = await _settingsService.getActiveStartHour();
    final int activeEndHour = await _settingsService.getActiveEndHour();
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
    final int missingMinutes = _calculateMissingMinutes(
      now,
      loggedMinutes,
      activeStartHour,
      activeEndHour,
    );
    if (missingMinutes > 0) {
      taskMinutes['Unknown'] = missingMinutes;
    }
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
      _tasks = tasks;
      _recentTaskIds = recentTaskIds;
      _selectedTaskId = selectedTaskId;
      _loggedMinutes = loggedMinutes;
      _activeStartHour = activeStartHour;
      _activeEndHour = activeEndHour;
      _missingMinutes = missingMinutes;
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

  Future<void> _startActivity(Task task) async {
    await _logService.startActivity(task.id);
    await _taskService.setSelectedTaskId(task.id);

    if (!mounted) {
      return;
    }

    await _loadDashboard();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logged ${task.name} for this check-in block.'),
      ),
    );
  }

  int _calculateMissingMinutes(
    DateTime now,
    int loggedMinutes,
    int startHour,
    int endHour,
  ) {
    final DateTime start = DateTime(now.year, now.month, now.day, startHour);
    final DateTime end = endHour == 24
        ? DateTime(now.year, now.month, now.day).add(const Duration(days: 1))
        : DateTime(now.year, now.month, now.day, endHour);

    if (!end.isAfter(start)) {
      return 0;
    }

    final int expectedMinutes;
    if (now.isBefore(start)) {
      expectedMinutes = 0;
    } else if (now.isAfter(end)) {
      expectedMinutes = end.difference(start).inMinutes;
    } else {
      expectedMinutes = now.difference(start).inMinutes;
    }

    return (expectedMinutes - loggedMinutes).clamp(0, expectedMinutes);
  }

  Future<void> _openLogActivityScreen() async {
    await _openScreen(const LogActivityScreen());
  }

  Future<void> _openRetroEditScreen() async {
    await _openScreen(const RetroEditScreen());
  }

  Future<void> _openTaskListScreen() async {
    await _openScreen(const TaskListScreen());
  }

  List<Task> _quickLogTasks() {
    if (_tasks.isEmpty) {
      return const <Task>[];
    }

    final List<Task> prioritizedTasks = <Task>[];
    final Set<String> addedIds = <String>{};

    if (_currentActivity != null) {
      final Task? currentTask = _tasks.cast<Task?>().firstWhere(
        (Task? task) => task?.name == _currentActivity!.taskName,
        orElse: () => null,
      );
      if (currentTask != null) {
        prioritizedTasks.add(currentTask);
        addedIds.add(currentTask.id);
      }
    }

    if (_selectedTaskId != null) {
      final Task? selectedTask = _tasks.cast<Task?>().firstWhere(
        (Task? task) => task?.id == _selectedTaskId,
        orElse: () => null,
      );
      if (selectedTask != null && addedIds.add(selectedTask.id)) {
        prioritizedTasks.add(selectedTask);
      }
    }

    for (final String recentTaskId in _recentTaskIds) {
      final Task? recentTask = _tasks.cast<Task?>().firstWhere(
        (Task? task) => task?.id == recentTaskId,
        orElse: () => null,
      );
      if (recentTask != null && addedIds.add(recentTask.id)) {
        prioritizedTasks.add(recentTask);
      }

      if (prioritizedTasks.length >= 4) {
        break;
      }
    }

    for (final Task task in _tasks) {
      if (addedIds.add(task.id)) {
        prioritizedTasks.add(task);
      }

      if (prioritizedTasks.length >= 4) {
        break;
      }
    }

    return prioritizedTasks;
  }

  List<String> _buildRecentTaskIds(List<ActivityLog> logs) {
    final List<String> taskIds = <String>[];
    final Set<String> seen = <String>{};

    for (final ActivityLog log in logs) {
      if (seen.add(log.taskId)) {
        taskIds.add(log.taskId);
      }

      if (taskIds.length >= 3) {
        break;
      }
    }

    return taskIds;
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

  String _formatHour(int hour) {
    if (hour == 24) {
      return '24:00';
    }
    final int normalizedHour = hour % 24;
    final int displayHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12;
    final String suffix = normalizedHour >= 12 ? 'PM' : 'AM';
    return '$displayHour:00 $suffix';
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

  bool _isWithinActiveWindow(DateTime now) {
    if (_settingsService.isFullDayWindow(_activeStartHour, _activeEndHour)) {
      return true;
    }

    final DateTime start = DateTime(
      now.year,
      now.month,
      now.day,
      _activeStartHour,
    );
    final DateTime end = _activeEndHour == 24
        ? DateTime(now.year, now.month, now.day).add(const Duration(days: 1))
        : DateTime(
            now.year,
            now.month,
            now.day,
            _activeEndHour,
          );

    if (!end.isAfter(start)) {
      return true;
    }

    return !now.isBefore(start) && now.isBefore(end);
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
    final DateTime now = DateTime.now();
    final DateTime currentWindowStart = _logService.slotStartFor(now);
    final DateTime currentWindowEnd = _logService.slotEndFor(now);
    final bool insideActiveWindow = _isWithinActiveWindow(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-In'),
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
                      'Open the app when your external alarm rings and log the last stretch quickly.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Active hours: ${_formatHour(_activeStartHour)} - ${_formatHour(_activeEndHour)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF7A867F),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _CheckInHeroCard(
                      timeRange:
                          '${_formatClock(currentWindowStart)} - ${_formatClock(currentWindowEnd)}',
                      hasTasks: _tasks.isNotEmpty,
                      insideActiveWindow: insideActiveWindow,
                      onPrimaryTap:
                          _tasks.isEmpty ? _openTaskListScreen : _openLogActivityScreen,
                      onSecondaryTap: _openRetroEditScreen,
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
                        title: 'Latest Check-In',
                        taskName: _currentActivity!.taskName,
                        startedAt: _formatClock(_currentActivity!.startedAt),
                        durationLabel:
                            _formatDuration(_currentActivity!.durationMinutes),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _openRetroEditScreen,
                          icon: const Icon(Icons.history),
                          label: const Text('Adjust Recent Slots'),
                        ),
                      ),
                    ],
                    if (_currentActivity == null && insideActiveWindow) ...<Widget>[
                      const SizedBox(height: 24),
                      _CurrentActivityCard(
                        title: 'Ready To Log',
                        taskName: 'Unknown',
                        startedAt: _formatClock(_logService.subslotStartFor(now)),
                        durationLabel:
                            _formatDuration(LogService.retroBlockSize.inMinutes),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nothing is logged for the current check-in block yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF56635D),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Quick Picks',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_tasks.isEmpty)
                      const _EmptyQuickLogState()
                    else ...<Widget>[
                      Text(
                        'Your most likely answers are surfaced first so check-in stays nearly one tap.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF56635D),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _quickLogTasks()
                            .map(
                              (Task task) => SizedBox(
                                width: 172,
                                child: FilledButton.icon(
                                  onPressed: () => _startActivity(task),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 18,
                                    ),
                                    backgroundColor: task.id == _selectedTaskId
                                        ? const Color(0xFF1E847F)
                                        : Colors.white,
                                    foregroundColor: task.id == _selectedTaskId
                                        ? Colors.white
                                        : const Color(0xFF15201B),
                                    side: BorderSide(
                                      color: task.id == _selectedTaskId
                                          ? const Color(0xFF1E847F)
                                          : const Color(0xFFE1E7E2),
                                    ),
                                    alignment: Alignment.centerLeft,
                                  ),
                                  icon: Icon(
                                    task.id == _selectedTaskId
                                        ? Icons.check_circle
                                        : Icons.bolt,
                                  ),
                                  label: Text(
                                    task.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          OutlinedButton(
                            onPressed: _openLogActivityScreen,
                            child: const Text('Open Full Check-In'),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _openTaskListScreen,
                            child: const Text('Manage Tasks'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Today So Far',
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
    required this.title,
    required this.taskName,
    required this.startedAt,
    required this.durationLabel,
  });

  final String title;
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
            title,
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
            '$startedAt for $durationLabel',
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
            'Start with a quick check-in and this screen will turn into your day summary.',
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

class _EmptyQuickLogState extends StatelessWidget {
  const _EmptyQuickLogState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7E2)),
      ),
      child: Text(
        'Create a few tasks first. After that, check-ins from this screen become nearly one tap.',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF56635D),
        ),
      ),
    );
  }
}

class _CheckInHeroCard extends StatelessWidget {
  const _CheckInHeroCard({
    required this.timeRange,
    required this.hasTasks,
    required this.insideActiveWindow,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  final String timeRange;
  final bool hasTasks;
  final bool insideActiveWindow;
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String headline = !insideActiveWindow
        ? 'Outside your tracking window'
        : hasTasks
            ? 'What did you just do?'
            : 'Create tasks before your first check-in';
    final String body = !insideActiveWindow
        ? 'You can still log manually, but the dashboard is currently outside your normal active hours.'
        : hasTasks
            ? 'Review $timeRange, tap the best match, and keep moving.'
            : 'Add a short task list like Coding, Study, Break, and Meetings so logging stays fast.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1E847F), Color(0xFF2F6DA3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Current window',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timeRange,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            headline,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                onPressed: onPrimaryTap,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0E3B39),
                ),
                icon: Icon(hasTasks ? Icons.edit_calendar : Icons.add_task),
                label: Text(hasTasks ? 'Start Check-In' : 'Create Tasks'),
              ),
              OutlinedButton.icon(
                onPressed: onSecondaryTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                icon: const Icon(Icons.history),
                label: const Text('Review Recent Blocks'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
