import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:time_tracker/models/activity_log.dart';
import 'package:time_tracker/models/task.dart';
import 'package:time_tracker/screens/home_dashboard_screen.dart';
import 'package:time_tracker/screens/task_list_screen.dart';
import 'package:time_tracker/services/log_service.dart';
import 'package:time_tracker/services/task_service.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'time_tracker_test',
  );
  Hive.init(tempDir.path);

  tearDown(() async {
    await Hive.close();
    await Hive.deleteBoxFromDisk('logs');
    await Hive.deleteBoxFromDisk('tasks');
    await Hive.deleteBoxFromDisk('task_settings');
    await Hive.deleteBoxFromDisk('settings');
    Hive.init(tempDir.path);
  });

  testWidgets('renders task management screen shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TaskListScreen()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Manage Tasks'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Add Task'),
      findsOneWidget,
    );
  });

  test('logs current 30-minute block from selected task action', () async {
    final LogService logService = LogService();
    final TaskService taskService = TaskService();
    final DateTime now = DateTime.now();
    final DateTime slotStart = logService.subslotStartFor(now);

    await taskService.setSelectedTaskId('task-3');
    await logService.startActivity('task-3', now);

    final Box<dynamic> logsBox = await Hive.openBox<dynamic>('logs');
    final dynamic rawLog = logsBox.get(slotStart.toIso8601String());

    expect(rawLog, isA<Map<dynamic, dynamic>>());
    expect((rawLog as Map<dynamic, dynamic>)['taskId'], 'task-3');
    expect(logsBox.length, 1);

    expect(await taskService.getSelectedTaskId(), 'task-3');
  });

  testWidgets('check-in auto logs top task and reveals choices on change', (
    WidgetTester tester,
  ) async {
    final TaskService taskService = TaskService();
    final LogService logService = LogService();

    await taskService.addTask(
      const Task(
        id: 'task-2',
        name: 'test2',
        category: 'Work',
        defaultMinutes: 30,
      ),
    );
    await taskService.addTask(
      const Task(
        id: 'task-3',
        name: 'test3',
        category: 'Work',
        defaultMinutes: 30,
      ),
    );
    await taskService.setSelectedTaskId('task-2');

    await tester.pumpWidget(const MaterialApp(home: HomeDashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('What are you doing right now?'), findsNothing);
    expect(find.text('Logged: test2'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('test3'), findsNothing);

    final DateTime slotStart = logService.subslotStartFor(DateTime.now());
    final Box<dynamic> logsBox = await Hive.openBox<dynamic>('logs');
    final dynamic rawLog = logsBox.get(slotStart.toIso8601String());

    expect(rawLog, isA<Map<dynamic, dynamic>>());
    expect((rawLog as Map<dynamic, dynamic>)['taskId'], 'task-2');
    expect(logsBox.length, 1);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(find.text('test2'), findsOneWidget);
    expect(find.text('test3'), findsOneWidget);
  });

  testWidgets('check-in does not overwrite an already logged current block', (
    WidgetTester tester,
  ) async {
    final TaskService taskService = TaskService();
    final LogService logService = LogService();
    final DateTime now = DateTime.now();
    final DateTime currentBlockStart = logService.subslotStartFor(now);

    await taskService.addTask(
      const Task(
        id: 'task-2',
        name: 'test2',
        category: 'Work',
        defaultMinutes: 30,
      ),
    );
    await taskService.addTask(
      const Task(
        id: 'task-3',
        name: 'test3',
        category: 'Work',
        defaultMinutes: 30,
      ),
    );
    await taskService.setSelectedTaskId('task-2');
    await logService.addLog(
      ActivityLog(
        id: currentBlockStart.toIso8601String(),
        taskId: 'task-3',
        startTime: currentBlockStart,
        endTime: currentBlockStart.add(LogService.retroBlockSize),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: HomeDashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Already logged: test3'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);

    final Box<dynamic> logsBox = await Hive.openBox<dynamic>('logs');
    final dynamic rawLog = logsBox.get(currentBlockStart.toIso8601String());

    expect(rawLog, isA<Map<dynamic, dynamic>>());
    expect((rawLog as Map<dynamic, dynamic>)['taskId'], 'task-3');
  });

  testWidgets('manual change keeps showing logged briefly before reverting', (
    WidgetTester tester,
  ) async {
    final TaskService taskService = TaskService();

    await taskService.addTask(
      const Task(
        id: 'task-2',
        name: 'test2',
        category: 'Work',
        defaultMinutes: 30,
      ),
    );
    await taskService.addTask(
      const Task(
        id: 'task-3',
        name: 'test3',
        category: 'Work',
        defaultMinutes: 30,
      ),
    );
    await taskService.setSelectedTaskId('task-2');

    await tester.pumpWidget(const MaterialApp(home: HomeDashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Logged: test2'), findsOneWidget);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('test3'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Logged: test3'), findsOneWidget);
    expect(find.text('Already logged: test3'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Already logged: test3'), findsOneWidget);
  });

  test('startActivity preserves earlier blocks in the same 30-minute window', () async {
    final LogService logService = LogService();
    final DateTime now = DateTime.now();
    final DateTime slotStart = logService.subslotStartFor(now);
    final DateTime earlierBlockStart = slotStart.subtract(
      LogService.retroBlockSize,
    );

    await logService.addLog(
      ActivityLog(
        id: earlierBlockStart.toIso8601String(),
        taskId: 'task-1',
        startTime: earlierBlockStart,
        endTime: earlierBlockStart.add(LogService.retroBlockSize),
      ),
    );

    await logService.startActivity('task-2', now);

    final Box<dynamic> logsBox = await Hive.openBox<dynamic>('logs');
    final dynamic earlierRawLog = logsBox.get(earlierBlockStart.toIso8601String());
    final dynamic currentRawLog = logsBox.get(slotStart.toIso8601String());

    expect(earlierRawLog, isA<Map<dynamic, dynamic>>());
    expect((earlierRawLog as Map<dynamic, dynamic>)['taskId'], 'task-1');
    expect(currentRawLog, isA<Map<dynamic, dynamic>>());
    expect((currentRawLog as Map<dynamic, dynamic>)['taskId'], 'task-2');
    expect(logsBox.length, 2);
  });

  testWidgets('continue fills forward empty blocks without overwriting logs', (
    WidgetTester tester,
  ) async {
    final TaskService taskService = TaskService();
    final LogService logService = LogService();
    final DateTime now = DateTime.now();
    final DateTime currentBlockStart = logService.subslotStartFor(now);
    final DateTime nextBlockStart = currentBlockStart.add(
      LogService.retroBlockSize,
    );
    final DateTime secondFutureBlockStart = nextBlockStart.add(
      LogService.retroBlockSize,
    );

    await taskService.addTask(
      const Task(
        id: 'task-2',
        name: 'test2',
        category: 'Work',
        defaultMinutes: 30,
      ),
    );
    await taskService.addTask(
      const Task(
        id: 'task-3',
        name: 'test3',
        category: 'Work',
        defaultMinutes: 30,
      ),
    );
    await taskService.setSelectedTaskId('task-2');
    await logService.addLog(
      ActivityLog(
        id: secondFutureBlockStart.toIso8601String(),
        taskId: 'task-2',
        startTime: secondFutureBlockStart,
        endTime: secondFutureBlockStart.add(LogService.retroBlockSize),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: HomeDashboardScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('test3'));
    await tester.pumpAndSettle();

    expect(find.text('test3 logged'), findsOneWidget);
    expect(find.text('Continue 15 min'), findsOneWidget);
    expect(find.text('Continue 30 min'), findsOneWidget);

    await tester.tap(find.text('Continue 15 min'));
    await tester.pump();
    await tester.pumpAndSettle();

    final Box<dynamic> logsBox = await Hive.openBox<dynamic>('logs');
    final dynamic currentRawLog = logsBox.get(currentBlockStart.toIso8601String());
    final dynamic nextRawLog = logsBox.get(nextBlockStart.toIso8601String());
    final dynamic secondFutureRawLog = logsBox.get(
      secondFutureBlockStart.toIso8601String(),
    );

    expect(currentRawLog, isA<Map<dynamic, dynamic>>());
    expect((currentRawLog as Map<dynamic, dynamic>)['taskId'], 'task-3');
    expect(nextRawLog, isA<Map<dynamic, dynamic>>());
    expect((nextRawLog as Map<dynamic, dynamic>)['taskId'], 'task-3');
    expect(secondFutureRawLog, isA<Map<dynamic, dynamic>>());
    expect((secondFutureRawLog as Map<dynamic, dynamic>)['taskId'], 'task-2');
    expect(logsBox.length, 3);
  });
}
