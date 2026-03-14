import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/task_service.dart';

class RetroEditScreen extends StatefulWidget {
  const RetroEditScreen({super.key});

  @override
  State<RetroEditScreen> createState() => _RetroEditScreenState();
}

class _RetroEditScreenState extends State<RetroEditScreen> {
  final LogService _logService = LogService();
  final TaskService _taskService = TaskService();

  List<Task> _tasks = const <Task>[];
  List<String?> _assignments = List<String?>.filled(LogService.retroBlockCount, null);
  DateTime? _windowStart;
  int _selectedBlockIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final DateTime windowStart = _logService.retroWindowStart();
    final List<Task> tasks = await _taskService.getTasks();
    final List<ActivityLog> logs = await _logService.getLogs();
    final List<String?> assignments = _logService.buildRetroBlockAssignments(
      logs,
      windowStart,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _tasks = tasks;
      _windowStart = windowStart;
      _assignments = assignments;
      _isLoading = false;
    });
  }

  void _assignTask(String? taskId) {
    setState(() {
      _assignments[_selectedBlockIndex] = taskId;
    });
  }

  Future<void> _save() async {
    final DateTime? windowStart = _windowStart;
    if (windowStart == null) {
      return;
    }

    await _logService.scheduleRetroWindow(windowStart, _assignments);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Updated the last 30 minutes')),
    );
    Navigator.of(context).pop();
  }

  String _formatTime(DateTime value) {
    final int hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final String minute = value.minute.toString().padLeft(2, '0');
    final String suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? windowStart = _windowStart;
    final Map<String, Task> tasksById = <String, Task>{
      for (final Task task in _tasks) task.id: task,
    };
    final String? selectedTaskId = _assignments[_selectedBlockIndex];

    return Scaffold(
      appBar: AppBar(title: const Text('Adjust Last 30 Minutes')),
      body: _isLoading || windowStart == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Pick a block, then assign the task you were doing.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: List<Widget>.generate(
                        _assignments.length,
                        (int index) {
                          final DateTime blockStart = windowStart.add(
                            Duration(
                              minutes: index * LogService.retroBlockSize.inMinutes,
                            ),
                          );
                          final DateTime blockEnd =
                              blockStart.add(LogService.retroBlockSize);
                          final String? taskId = _assignments[index];
                          final bool isSelected = index == _selectedBlockIndex;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedBlockIndex = index;
                              });
                            },
                            child: Container(
                              width: 150,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFD8F1E6)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF1E847F)
                                      : const Color(0xFFE1E7E2),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '${_formatTime(blockStart)} - ${_formatTime(blockEnd)}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    taskId == null
                                        ? 'Unassigned'
                                        : tasksById[taskId]?.name ?? 'Unknown',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Selected block',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedTaskId == null
                          ? 'No task assigned'
                          : tasksById[selectedTaskId]?.name ?? 'Unknown',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        ChoiceChip(
                          label: const Text('Clear'),
                          selected: selectedTaskId == null,
                          onSelected: (_) => _assignTask(null),
                        ),
                        ..._tasks.map(
                          (Task task) => ChoiceChip(
                            label: Text(task.name),
                            selected: selectedTaskId == task.id,
                            onSelected: (_) => _assignTask(task.id),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
