import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

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

  Future<void> pumpUntilVisible(WidgetTester tester, Finder finder) async {
    for (int i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }

    fail('Timed out waiting for ${finder.description}');
  }

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

  test('logs current 5-minute block from selected task action', () async {
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
    expect(await taskService.getSelectedTaskId(), 'task-3');
  });
}
