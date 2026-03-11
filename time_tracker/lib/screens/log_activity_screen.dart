import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/log_service.dart';
import '../services/task_service.dart';

class LogActivityScreen extends StatefulWidget {
  const LogActivityScreen({super.key});

  @override
  State<LogActivityScreen> createState() => _LogActivityScreenState();
}

class _LogActivityScreenState extends State<LogActivityScreen> {
  final TaskService _taskService = TaskService();
  final LogService _logService = LogService();

  List<Task> _tasks = const <Task>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final List<Task> tasks = await _taskService.getTasks();

    if (!mounted) {
      return;
    }

    setState(() {
      _tasks = tasks;
      _isLoading = false;
    });
  }

  Future<void> _logActivity(Task task) async {
    final log = _logService.createCurrentBlockLog(task.id);
    await _logService.addLog(log);
    await _taskService.setSelectedTaskId(task.id);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Logged ${task.name} for ${_formatTime(log.startTime)} - ${_formatTime(log.endTime)}',
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final int hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final String minute = value.minute.toString().padLeft(2, '0');
    final String suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final DateTime blockStart = _logService.currentBlockStart();
    final DateTime blockEnd = blockStart.add(const Duration(minutes: 30));
    final ThemeData theme = Theme.of(context);

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
                    Text(
                      'What are you doing right now?',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This will log the current 30-minute block: '
                      '${_formatTime(blockStart)} - ${_formatTime(blockEnd)}',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _tasks.isEmpty
                          ? const _EmptyLoggerState()
                          : ListView.separated(
                              itemCount: _tasks.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (BuildContext context, int index) {
                                final Task task = _tasks[index];
                                return _TaskChoiceCard(
                                  task: task,
                                  onTap: () => _logActivity(task),
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
    required this.onTap,
  });

  final Task task;
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE1E7E2)),
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
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.bolt, color: Color(0xFF1E847F)),
              ],
            ),
          ),
        ),
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
              'Create at least one task first, then come back to log your current activity.',
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
