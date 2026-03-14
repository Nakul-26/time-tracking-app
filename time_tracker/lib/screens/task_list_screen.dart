import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/task_service.dart';
import 'daily_stats_screen.dart';
import 'log_activity_screen.dart';
import 'today_timeline_screen.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final TaskService _taskService = TaskService();

  List<Task> _tasks = const <Task>[];
  String? _selectedTaskId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final List<Task> tasks = await _taskService.getTasks();
    final String? selectedTaskId = await _taskService.getSelectedTaskId();

    if (!mounted) {
      return;
    }

    setState(() {
      _tasks = tasks;
      _selectedTaskId = selectedTaskId;
      _isLoading = false;
    });
  }

  Future<void> _selectTask(Task task) async {
    await _taskService.setSelectedTaskId(task.id);

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedTaskId = task.id;
    });
  }

  Future<void> _showAddTaskSheet() async {
    final Task? task = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _TaskEditorSheet(),
    );

    if (task == null) {
      return;
    }

    await _taskService.addTask(task);
    await _taskService.setSelectedTaskId(task.id);
    await _loadTasks();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${task.name} added')));
  }

  Future<void> _showEditTaskSheet(Task task) async {
    final Task? updatedTask = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _TaskEditorSheet(task: task),
    );

    if (updatedTask == null) {
      return;
    }

    await _taskService.updateTask(updatedTask);
    await _loadTasks();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${updatedTask.name} updated')),
    );
  }

  Future<void> _deleteTask(Task task) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete task?'),
          content: Text(
            'Delete "${task.name}"? Existing logs will keep it as Unknown.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _taskService.deleteTask(task.id);
    await _loadTasks();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${task.name} deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Tasks'),
        actions: <Widget>[
          IconButton(
            onPressed: _openDailyStatsScreen,
            tooltip: 'View daily stats',
            icon: const Icon(Icons.bar_chart),
          ),
          IconButton(
            onPressed: _openTodayTimelineScreen,
            tooltip: 'View timeline',
            icon: const Icon(Icons.timeline),
          ),
          IconButton(
            onPressed: _openLogActivityScreen,
            tooltip: 'Log activity',
            icon: const Icon(Icons.bolt),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Build the labels you will reuse for logging your day.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _tasks.isEmpty
                          ? _EmptyTaskState(onAddTask: _showAddTaskSheet)
                          : ListView.separated(
                              itemCount: _tasks.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (BuildContext context, int index) {
                                final Task task = _tasks[index];
                                final bool isSelected =
                                    task.id == _selectedTaskId;

                                return _TaskCard(
                                  task: task,
                                  isSelected: isSelected,
                                  onTap: () => _selectTask(task),
                                  onEdit: () => _showEditTaskSheet(task),
                                  onDelete: () => _deleteTask(task),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTaskSheet,
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: FilledButton.icon(
          onPressed: _openLogActivityScreen,
          icon: const Icon(Icons.bolt),
          label: const Text('Log Current Activity'),
        ),
      ),
    );
  }

  void _openLogActivityScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const LogActivityScreen(),
      ),
    );
  }

  void _openTodayTimelineScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const TodayTimelineScreen(),
      ),
    );
  }

  void _openDailyStatsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const DailyStatsScreen(),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Task task;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
            color: isSelected ? const Color(0xFFD8F1E6) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF1E847F)
                  : const Color(0xFFE1E7E2),
              width: isSelected ? 2 : 1,
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
                        'Reminder: every ${task.defaultMinutes} min',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF56635D),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? const Color(0xFF1E847F)
                      : const Color(0xFF8D9A93),
                ),
                PopupMenuButton<_TaskAction>(
                  tooltip: 'Task actions',
                  onSelected: (_TaskAction action) {
                    if (action == _TaskAction.edit) {
                      onEdit();
                    } else {
                      onDelete();
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      const <PopupMenuEntry<_TaskAction>>[
                        PopupMenuItem<_TaskAction>(
                          value: _TaskAction.edit,
                          child: Text('Edit'),
                        ),
                        PopupMenuItem<_TaskAction>(
                          value: _TaskAction.delete,
                          child: Text('Delete'),
                        ),
                      ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTaskState extends StatelessWidget {
  const _EmptyTaskState({required this.onAddTask});

  final VoidCallback onAddTask;

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
            const Icon(Icons.track_changes, size: 48, color: Color(0xFF1E847F)),
            const SizedBox(height: 16),
            Text(
              'No tasks yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first task to start building a trackable day.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF56635D),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddTask,
              icon: const Icon(Icons.add),
              label: const Text('Add Task'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TaskAction { edit, delete }

class _TaskEditorSheet extends StatefulWidget {
  const _TaskEditorSheet({this.task});

  final Task? task;

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _defaultMinutesController;

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.task?.name ?? '');
    _categoryController = TextEditingController(
      text: widget.task?.category ?? '',
    );
    _defaultMinutesController = TextEditingController(
      text: (widget.task?.defaultMinutes ?? 30).toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _defaultMinutesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      Task(
        id: widget.task?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        defaultMinutes: int.parse(_defaultMinutesController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, viewInsets.bottom + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _isEditing ? 'Edit Task' : 'Add Task',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Task name',
                hintText: 'Coding',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a task name';
                }

                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _categoryController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                hintText: 'Productive',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _defaultMinutesController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Default reminder minutes',
                hintText: '30',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) {
                final int? minutes = int.tryParse(value?.trim() ?? '');
                if (minutes == null || minutes <= 0) {
                  return 'Enter reminder minutes';
                }

                if (minutes > 720) {
                  return 'Use 720 minutes or less';
                }

                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: Text(_isEditing ? 'Save Changes' : 'Save Task'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
