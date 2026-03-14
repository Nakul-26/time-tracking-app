import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';
import 'retro_edit_screen.dart';

class LogActivityScreen extends StatefulWidget {
  const LogActivityScreen({super.key});

  @override
  State<LogActivityScreen> createState() => _LogActivityScreenState();
}

class _LogActivityScreenState extends State<LogActivityScreen> {
  final TaskService _taskService = TaskService();
  final LogService _logService = LogService();
  final SettingsService _settingsService = SettingsService();

  List<Task> _tasks = const <Task>[];
  String? _selectedTaskId;
  ActivityLog? _currentActivity;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final List<Task> tasks = await _taskService.getTasks();
    final String? selectedTaskId = await _taskService.getSelectedTaskId();
    final ActivityLog? currentActivity = await _logService.getCurrentActivity();

    if (!mounted) {
      return;
    }

    setState(() {
      _tasks = tasks;
      _selectedTaskId = selectedTaskId;
      _currentActivity = currentActivity;
      _isLoading = false;
    });
  }

  Future<void> _startActivity(Task task) async {
    final ActivityLog log = await _logService.startActivity(task.id);
    await _taskService.setSelectedTaskId(task.id);

    final bool remindersEnabled = await _settingsService.getRemindersEnabled();
    if (remindersEnabled) {
      await NotificationService.scheduleReminder(
        when: DateTime.now().add(Duration(minutes: task.defaultMinutes)),
        minutes: task.defaultMinutes,
        taskName: task.name,
      );
    } else {
      await NotificationService.cancelReminder();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedTaskId = task.id;
      _currentActivity = log;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Started ${task.name}. Next reminder in ${task.defaultMinutes} minutes.',
        ),
      ),
    );
  }

  Future<void> _openRetroEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const RetroEditScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadData();
  }

  String _formatTime(DateTime value) {
    final int hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final String minute = value.minute.toString().padLeft(2, '0');
    final String suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
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
    final Map<String, Task> tasksById = <String, Task>{
      for (final Task task in _tasks) task.id: task,
    };
    final Task? currentTask = _currentActivity == null
        ? null
        : tasksById[_currentActivity!.taskId];

    return Scaffold(
      appBar: AppBar(title: const Text('Log Activity')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_currentActivity != null && currentTask != null)
                      _CurrentActivityCard(
                        taskName: currentTask.name,
                        startedAt: _formatTime(_currentActivity!.startTime),
                        durationLabel: _formatDuration(
                          _logService.durationMinutesForLog(_currentActivity!),
                        ),
                      ),
                    if (_currentActivity != null && currentTask != null)
                      const SizedBox(height: 20),
                    Text(
                      'What are you doing now?',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start a task now, or adjust the last 30 minutes retroactively.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _openRetroEditor,
                      icon: const Icon(Icons.history),
                      label: const Text('Adjust Last 30 Minutes'),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _tasks.isEmpty
                          ? const _EmptyLoggerState()
                          : ListView.separated(
                              itemCount: _tasks.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (BuildContext context, int index) {
                                final Task task = _tasks[index];
                                return _TaskChoiceCard(
                                  task: task,
                                  isRecommended: task.id == _selectedTaskId,
                                  onTap: () => _startActivity(task),
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

class _TaskChoiceCard extends StatelessWidget {
  const _TaskChoiceCard({
    required this.task,
    required this.isRecommended,
    required this.onTap,
  });

  final Task task;
  final bool isRecommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: isRecommended ? const Color(0xFFD8F1E6) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isRecommended
                  ? const Color(0xFF1E847F)
                  : const Color(0xFFE1E7E2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        task.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (task.category.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          task.category,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF56635D),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'Next reminder in ${task.defaultMinutes} min',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF56635D),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isRecommended)
                  const Icon(Icons.check_circle, color: Color(0xFF1E847F))
                else
                  const Icon(Icons.bolt, color: Color(0xFF1E847F)),
              ],
            ),
          ),
        ),
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

class _EmptyLoggerState extends StatelessWidget {
  const _EmptyLoggerState();

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
            const Icon(Icons.timer_outlined, size: 48, color: Color(0xFF1E847F)),
            const SizedBox(height: 16),
            Text(
              'No tasks to log yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create at least one task first, then come back to start tracking.',
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
