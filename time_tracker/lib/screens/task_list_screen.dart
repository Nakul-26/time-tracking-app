import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/task_service.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final TaskService _taskService = TaskService();

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
        title: const Text('Manage Tasks'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _TaskHintCard(theme: theme),
                    const SizedBox(height: 20),
                    Text(
                      'Your Tasks',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
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

                                return _TaskCard(
                                  task: task,
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
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onEdit,
    required this.onDelete,
  });

  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFE1E7E2),
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
                      'Next reminder: ${task.defaultMinutes} min',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
    );
  }
}

class _TaskHintCard extends StatelessWidget {
  const _TaskHintCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5EF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFCFE4D7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'This page is only for managing task labels.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF15201B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add, edit, or delete tasks here. Use Home or Timeline to log what you are doing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF56635D),
            ),
          ),
        ],
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
  static const List<String> _categoryOptions = <String>[
    'Work',
    'Study',
    'Personal',
    'Health',
    'Break',
    'Other',
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _durationController;
  late String _selectedCategory;

  bool get _isEditing => widget.task != null;

  List<String> get _availableCategories {
    final String existingCategory = widget.task?.category.trim() ?? '';
    if (existingCategory.isEmpty ||
        _categoryOptions.contains(existingCategory)) {
      return _categoryOptions;
    }

    return <String>[existingCategory, ..._categoryOptions];
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.task?.name ?? '');
    _durationController = TextEditingController(
      text: (widget.task?.defaultMinutes ?? 30).toString(),
    );
    final String existingCategory = widget.task?.category.trim() ?? '';
    _selectedCategory = existingCategory.isEmpty ? _categoryOptions.first : existingCategory;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
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
        category: _selectedCategory,
        defaultMinutes: int.tryParse(_durationController.text.trim()) ?? 30,
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
            DropdownButtonFormField<String>(
              value: _availableCategories.contains(_selectedCategory)
                  ? _selectedCategory
                  : _availableCategories.first,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: _availableCategories
                  .map(
                    (String category) => DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _selectedCategory = value;
                });
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Next reminder after (minutes)',
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
            const SizedBox(height: 12),
            Text(
              'Used for the "What will you do next?" reminder. The tracking view still supports 5-minute blocks.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF56635D),
                  ),
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
