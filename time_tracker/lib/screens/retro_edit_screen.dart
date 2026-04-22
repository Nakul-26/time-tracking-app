import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../services/task_service.dart';

class RetroEditScreen extends StatefulWidget {
  const RetroEditScreen({super.key});

  @override
  State<RetroEditScreen> createState() => _RetroEditScreenState();
}

class _RetroEditScreenState extends State<RetroEditScreen> {
  final LogService _logService = LogService();
  final TaskService _taskService = TaskService();
  final SettingsService _settingsService = SettingsService();

  List<Task> _tasks = const <Task>[];
  List<String> _quickPickTaskIds = const <String>[];
  List<String?> _assignments = const <String?>[];
  DateTime? _dayStart;
  DateTime? _dayEnd;
  int _selectedBlockIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final List<Task> tasks = await _taskService.getTasks();
    final List<ActivityLog> logs = await _logService.getLogs();
    final int activeStartHour = await _settingsService.getActiveStartHour();
    final int activeEndHour = await _settingsService.getActiveEndHour();
    final DateTime now = DateTime.now();
    final DateTime dayStart = DateTime(
      now.year,
      now.month,
      now.day,
      activeStartHour,
    );
    final DateTime configuredDayEnd = activeEndHour == 24
        ? DateTime(now.year, now.month, now.day).add(const Duration(days: 1))
        : DateTime(now.year, now.month, now.day, activeEndHour);
    final DateTime currentBlockEnd = _logService
        .subslotStartFor(now)
        .add(LogService.retroBlockSize);
    final DateTime dayEnd = currentBlockEnd.isBefore(configuredDayEnd)
        ? currentBlockEnd
        : configuredDayEnd;
    final int blockCount = dayEnd.isAfter(dayStart)
        ? dayEnd.difference(dayStart).inMinutes ~/
              LogService.retroBlockSize.inMinutes
        : 0;
    final List<String?> assignments = blockCount == 0
        ? const <String?>[]
        : _logService.buildAssignmentsForRange(logs, dayStart, blockCount);

    if (!mounted) {
      return;
    }

    setState(() {
      _tasks = tasks;
      _quickPickTaskIds = _buildQuickPickTaskIds(tasks, logs);
      _dayStart = dayStart;
      _dayEnd = dayEnd;
      _assignments = assignments;
      _selectedBlockIndex = _initialSelectedBlockIndex(assignments);
      _isLoading = false;
    });
  }

  int _initialSelectedBlockIndex(List<String?> assignments) {
    for (int index = assignments.length - 1; index >= 0; index -= 1) {
      if (assignments[index] != null) {
        return index;
      }
    }

    return assignments.isEmpty ? 0 : assignments.length - 1;
  }

  Future<void> _showTaskPickerSheet(int blockIndex) async {
    if (_assignments.isEmpty) {
      return;
    }

    setState(() {
      _selectedBlockIndex = blockIndex;
    });

    final String? selectedTaskId = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return TaskPickerSheet(
          tasks: _tasks,
          quickPickTaskIds: _quickPickTaskIds,
          selectedTaskId: _assignments[blockIndex],
          blockLabel:
              '${_formatTime(_blockStartAt(blockIndex))} - ${_formatTime(_blockEndAt(blockIndex))}',
          onSelect: (String? taskId) => Navigator.of(context).pop(taskId),
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (selectedTaskId == _assignments[blockIndex]) {
      return;
    }

    setState(() {
      _selectedBlockIndex = blockIndex;
      _assignments = List<String?>.from(_assignments)
        ..[blockIndex] = selectedTaskId;
    });
  }

  List<String> _buildQuickPickTaskIds(
    List<Task> tasks,
    List<ActivityLog> logs,
  ) {
    final List<String> quickPickIds = <String>[];
    final Set<String> seen = <String>{};
    final Set<String> taskIds = tasks.map((Task task) => task.id).toSet();

    for (final ActivityLog log in logs) {
      if (!taskIds.contains(log.taskId)) {
        continue;
      }

      if (seen.add(log.taskId)) {
        quickPickIds.add(log.taskId);
      }

      if (quickPickIds.length >= 5) {
        return quickPickIds;
      }
    }

    for (final Task task in tasks) {
      if (seen.add(task.id)) {
        quickPickIds.add(task.id);
      }

      if (quickPickIds.length >= 5) {
        break;
      }
    }

    return quickPickIds;
  }

  void _assignTaskToSelectedWindow(String? taskId) {
    if (_assignments.isEmpty) {
      return;
    }

    final int startIndex =
        (_selectedBlockIndex ~/ LogService.retroBlockCount) *
        LogService.retroBlockCount;
    final int endIndex = (startIndex + LogService.retroBlockCount).clamp(
      0,
      _assignments.length,
    );
    final List<String?> nextAssignments = List<String?>.from(_assignments);

    for (int index = startIndex; index < endIndex; index += 1) {
      nextAssignments[index] = taskId;
    }

    setState(() {
      _assignments = nextAssignments;
    });
  }

  Future<void> _save() async {
    final DateTime? dayStart = _dayStart;
    if (dayStart == null) {
      return;
    }

    await _logService.assignSlots(dayStart, _assignments);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Updated today\'s timeline')));
    Navigator.of(context).pop();
  }

  String _formatTime(DateTime value) {
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

  DateTime _blockStartAt(int index) {
    return _dayStart!.add(
      Duration(minutes: index * LogService.retroBlockSize.inMinutes),
    );
  }

  DateTime _blockEndAt(int index) {
    return _blockStartAt(index).add(LogService.retroBlockSize);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? dayStart = _dayStart;
    final DateTime? dayEnd = _dayEnd;
    final Map<String, Task> tasksById = <String, Task>{
      for (final Task task in _tasks) task.id: task,
    };
    final bool hasBlocks = _assignments.isNotEmpty;
    final String? selectedTaskId = hasBlocks
        ? _assignments[_selectedBlockIndex]
        : null;
    final DateTime? selectedBlockStart = hasBlocks
        ? _blockStartAt(_selectedBlockIndex)
        : null;
    final DateTime? selectedBlockEnd = hasBlocks
        ? _blockEndAt(_selectedBlockIndex)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Today')),
      body: _isLoading || dayStart == null || dayEnd == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Log missing time or revise anything already logged for today.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF56635D),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatTime(dayStart)} - ${_formatTime(dayEnd)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF7A867F),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!hasBlocks)
                      const Expanded(child: _EmptyRetroEditState())
                    else
                      Expanded(
                        child: ListView(
                          children: <Widget>[
                            _SelectedBlockCard(
                              timeRange:
                                  '${_formatTime(selectedBlockStart!)} - ${_formatTime(selectedBlockEnd!)}',
                              taskName: selectedTaskId == null
                                  ? 'Unassigned'
                                  : tasksById[selectedTaskId]?.name ??
                                        'Unknown',
                              windowRange: _selectedWindowRangeLabel(),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: <Widget>[
                                OutlinedButton(
                                  onPressed: selectedTaskId == null
                                      ? null
                                      : () => _assignTaskToSelectedWindow(
                                          selectedTaskId,
                                        ),
                                  child: const Text('Fill 30-Min Window'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _assignTaskToSelectedWindow(null),
                                  child: const Text('Clear 30-Min Window'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Today By 30-Minute Window',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap any 5-minute block below to assign a task instantly.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF56635D),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._buildWindowCards(theme, tasksById),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    if (hasBlocks) ...<Widget>[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _save,
                          child: const Text('Save Changes'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _buildWindowCards(ThemeData theme, Map<String, Task> tasksById) {
    final List<Widget> cards = <Widget>[];

    for (
      int startIndex = 0;
      startIndex < _assignments.length;
      startIndex += LogService.retroBlockCount
    ) {
      final int endIndex = (startIndex + LogService.retroBlockCount).clamp(
        0,
        _assignments.length,
      );
      final DateTime windowStart = _blockStartAt(startIndex);
      final DateTime windowEnd = _blockEndAt(endIndex - 1);

      cards.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE1E7E2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_formatTime(windowStart)} - ${_formatTime(windowEnd)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _windowSummary(startIndex, endIndex, tasksById),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF56635D),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List<Widget>.generate(endIndex - startIndex, (
                    int offset,
                  ) {
                    final int blockIndex = startIndex + offset;
                    final DateTime blockStart = _blockStartAt(blockIndex);
                    final DateTime blockEnd = _blockEndAt(blockIndex);
                    final String? taskId = _assignments[blockIndex];
                    final bool isSelected = blockIndex == _selectedBlockIndex;

                    return GestureDetector(
                      onTap: () => _showTaskPickerSheet(blockIndex),
                      child: Container(
                        width: 112,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFD8F1E6)
                              : const Color(0xFFF8FAF8),
                          borderRadius: BorderRadius.circular(16),
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              taskId == null
                                  ? 'Unassigned'
                                  : tasksById[taskId]?.name ?? 'Unknown',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return cards;
  }

  String _selectedWindowRangeLabel() {
    if (_assignments.isEmpty) {
      return '';
    }

    final int startIndex =
        (_selectedBlockIndex ~/ LogService.retroBlockCount) *
        LogService.retroBlockCount;
    final int endIndex = (startIndex + LogService.retroBlockCount).clamp(
      0,
      _assignments.length,
    );

    return '${_formatTime(_blockStartAt(startIndex))} - ${_formatTime(_blockEndAt(endIndex - 1))}';
  }

  String _windowSummary(
    int startIndex,
    int endIndex,
    Map<String, Task> tasksById,
  ) {
    final Map<String, int> minutesByTask = <String, int>{};
    int unassignedMinutes = 0;

    for (int index = startIndex; index < endIndex; index += 1) {
      final String? taskId = _assignments[index];
      if (taskId == null) {
        unassignedMinutes += LogService.retroBlockSize.inMinutes;
        continue;
      }

      minutesByTask[taskId] =
          (minutesByTask[taskId] ?? 0) + LogService.retroBlockSize.inMinutes;
    }

    final List<String> parts = minutesByTask.entries
        .map(
          (MapEntry<String, int> entry) =>
              '${tasksById[entry.key]?.name ?? 'Unknown'} ${_formatDuration(entry.value)}',
        )
        .toList();

    if (unassignedMinutes > 0) {
      parts.add('Unassigned ${_formatDuration(unassignedMinutes)}');
    }

    return parts.isEmpty ? 'No time assigned yet' : parts.join('  •  ');
  }
}

class TaskPickerSheet extends StatelessWidget {
  const TaskPickerSheet({
    super.key,
    required this.tasks,
    required this.quickPickTaskIds,
    required this.selectedTaskId,
    required this.blockLabel,
    required this.onSelect,
    this.allowClear = true,
  });

  final List<Task> tasks;
  final List<String> quickPickTaskIds;
  final String? selectedTaskId;
  final String blockLabel;
  final ValueChanged<String?> onSelect;
  final bool allowClear;

  Future<void> _showAllTasks(BuildContext context) async {
    final String? selected = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return _AllTasksSheet(
          tasks: tasks,
          selectedTaskId: selectedTaskId,
          onSelect: (String? taskId) => Navigator.of(context).pop(taskId),
        );
      },
    );

    if (!context.mounted || selected == null) {
      return;
    }

    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, Task> tasksById = <String, Task>{
      for (final Task task in tasks) task.id: task,
    };
    final List<Task> quickPicks = quickPickTaskIds
        .map((String id) => tasksById[id])
        .whereType<Task>()
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'What did you do?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              blockLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF56635D),
              ),
            ),
            const SizedBox(height: 12),
            if (quickPicks.isEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('No tasks yet'),
                subtitle: const Text('Add tasks from the task list first.'),
              )
            else
              ...quickPicks.map(
                (Task task) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => onSelect(task.id),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: selectedTaskId == task.id
                            ? const Color(0xFF1E847F)
                            : const Color(0xFFEAF5EF),
                        foregroundColor: selectedTaskId == task.id
                            ? Colors.white
                            : const Color(0xFF15201B),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              task.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: selectedTaskId == task.id
                                    ? Colors.white
                                    : const Color(0xFF15201B),
                              ),
                            ),
                          ),
                          if (selectedTaskId == task.id)
                            const Icon(Icons.check_circle)
                          else
                            const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAllTasks(context),
                icon: const Icon(Icons.more_horiz),
                label: const Text('More'),
              ),
            ),
            if (allowClear)
              TextButton(
                onPressed: () => onSelect(null),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text('Clear block'),
                    if (selectedTaskId == null) ...<Widget>[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.check,
                        size: 18,
                        color: Color(0xFF1E847F),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AllTasksSheet extends StatelessWidget {
  const _AllTasksSheet({
    required this.tasks,
    required this.selectedTaskId,
    required this.onSelect,
  });

  final List<Task> tasks;
  final String? selectedTaskId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'All Tasks',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  ...tasks.map(
                    (Task task) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(task.name),
                      trailing: selectedTaskId == task.id
                          ? const Icon(Icons.check, color: Color(0xFF1E847F))
                          : null,
                      onTap: () => onSelect(task.id),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedBlockCard extends StatelessWidget {
  const _SelectedBlockCard({
    required this.timeRange,
    required this.taskName,
    required this.windowRange,
  });

  final String timeRange;
  final String taskName;
  final String windowRange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

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
            'Selected Block',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF56635D),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timeRange,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            taskName,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF33413A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Window: $windowRange',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF7A867F),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRetroEditState extends StatelessWidget {
  const _EmptyRetroEditState();

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
            const Icon(Icons.history, size: 48, color: Color(0xFF1E847F)),
            const SizedBox(height: 16),
            Text(
              'No editable blocks yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Once today enters your active tracking window, this screen will let you edit the day block by block.',
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
