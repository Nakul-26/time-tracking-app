import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

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
    final DateTime windowStart = logService.slotStartFor(now);

    await taskService.setSelectedTaskId('task-3');
    await logService.startActivity('task-3', now);

    final Box<dynamic> logsBox = await Hive.openBox<dynamic>('logs');
    for (int index = 0; index < LogService.retroBlockCount; index += 1) {
      final DateTime slotStart = windowStart.add(
        Duration(minutes: index * LogService.retroBlockSize.inMinutes),
      );
      final dynamic rawLog = logsBox.get(slotStart.toIso8601String());

      expect(rawLog, isA<Map<dynamic, dynamic>>());
      expect((rawLog as Map<dynamic, dynamic>)['taskId'], 'task-3');
    }

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

    final DateTime windowStart = logService.slotStartFor(DateTime.now());
    final Box<dynamic> logsBox = await Hive.openBox<dynamic>('logs');
    for (int index = 0; index < LogService.retroBlockCount; index += 1) {
      final DateTime slotStart = windowStart.add(
        Duration(minutes: index * LogService.retroBlockSize.inMinutes),
      );
      final dynamic rawLog = logsBox.get(slotStart.toIso8601String());

      expect(rawLog, isA<Map<dynamic, dynamic>>());
      expect((rawLog as Map<dynamic, dynamic>)['taskId'], 'task-2');
    }

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(find.text('test2'), findsOneWidget);
    expect(find.text('test3'), findsOneWidget);
  });
}
