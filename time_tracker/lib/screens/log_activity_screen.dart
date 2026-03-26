import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
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

  List<Task> _tasks = const <Task>[];
  List<String> _recentTaskIds = const <String>[];
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
    final List<ActivityLog> logs = await _logService.getLogs();
    final String? selectedTaskId = await _taskService.getSelectedTaskId();
    final ActivityLog? currentActivity = await _logService.getCurrentActivity();

    if (!mounted) {
      return;
    }

    setState(() {
      _tasks = tasks;
      _recentTaskIds = _buildRecentTaskIds(logs);
      _selectedTaskId = selectedTaskId;
      _currentActivity = currentActivity;
      _isLoading = false;
    });
  }

  Future<void> _startActivity(Task task) async {
    final ActivityLog log = await _logService.startActivity(task.id);
    await _taskService.setSelectedTaskId(task.id);

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
          'Logged ${task.name} for this check-in block.',
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

  List<Task> _prioritizedTasks() {
    final List<Task> prioritizedTasks = <Task>[];
    final Set<String> addedIds = <String>{};

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
    }

    for (final Task task in _tasks) {
      if (addedIds.add(task.id)) {
        prioritizedTasks.add(task);
      }
    }

    return prioritizedTasks;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final DateTime blockStart = _logService.subslotStartFor(now);
    final DateTime blockEnd = blockStart.add(LogService.retroBlockSize);
    final Map<String, Task> tasksById = <String, Task>{
      for (final Task task in _tasks) task.id: task,
    };
    final List<Task> prioritizedTasks = _prioritizedTasks();
    final Task? currentTask = _currentActivity == null
        ? null
        : tasksById[_currentActivity!.taskId];

    return Scaffold(
      appBar: AppBar(title: const Text('Quick Check-In')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _CheckInHeaderCard(
                      timeRange:
                          '${_formatTime(blockStart)} - ${_formatTime(blockEnd)}',
                    ),
                    const SizedBox(height: 20),
                    if (_currentActivity != null && currentTask != null)
                      _CurrentActivityCard(
                        title: 'Latest Check-In',
                        taskName: currentTask.name,
                        startedAt: _formatTime(_currentActivity!.startTime),
                        durationLabel: _formatDuration(
                          _logService.durationMinutesForLog(_currentActivity!),
                        ),
                      ),
                    if (_currentActivity != null && currentTask != null)
                      const SizedBox(height: 20),
                    Text(
                      'What Did You Do?',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This screen should be the fastest possible answer to your external reminder: open app, tap once, continue.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _LogHintCard(),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _openRetroEditor,
                      icon: const Icon(Icons.history),
                      label: const Text('Edit Today'),
                    ),
                    const SizedBox(height: 20),
                    if (_tasks.isNotEmpty) ...<Widget>[
                      Text(
                        'Fastest Picks',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: prioritizedTasks
                            .take(4)
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
                                        : const Color(0xFFEAF5EF),
                                    foregroundColor: task.id == _selectedTaskId
                                        ? Colors.white
                                        : const Color(0xFF15201B),
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
                      const SizedBox(height: 20),
                      Text(
                        'All Tasks',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: _tasks.isEmpty
                          ? const _EmptyLoggerState()
                          : ListView.separated(
                              itemCount: prioritizedTasks.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (BuildContext context, int index) {
                                final Task task = prioritizedTasks[index];
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
                        'Tap to assign this check-in block',
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

class _LogHintCard extends StatelessWidget {
  const _LogHintCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5EF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCFE4D7)),
      ),
      child: Text(
        'Recommended workflow: set a repeating reminder in Clock or Google Calendar, then use this screen to log what just happened.',
        
        style: theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF56635D),
        ),
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

class _CheckInHeaderCard extends StatelessWidget {
  const _CheckInHeaderCard({required this.timeRange});

  final String timeRange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEFD9B5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Current block',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF7A867F),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timeRange,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
