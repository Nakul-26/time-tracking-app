import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:time_tracker/screens/home_dashboard_screen.dart';
import 'package:time_tracker/screens/task_list_screen.dart';
import 'package:time_tracker/services/log_service.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'time_tracker_test',
  );
  Hive.init(tempDir.path);

  tearDown(() async {
    await Hive.deleteBoxFromDisk('logs');
    await Hive.deleteBoxFromDisk('tasks');
    await Hive.deleteBoxFromDisk('task_settings');
    await Hive.deleteBoxFromDisk('settings');
  });

  Future<void> pumpUntilVisible(WidgetTester tester, Finder finder) async {
    for (int i = 0; i < 20; i += 1) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
  }

  testWidgets('shows empty task state', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TaskListScreen()));

    await pumpUntilVisible(tester, find.text('Your Tasks'));
    expect(tester.takeException(), isNull);

    expect(find.text('Your Tasks'), findsOneWidget);
    expect(find.text('No tasks yet'), findsOneWidget);
    expect(find.text('Add Task'), findsWidgets);
    expect(find.text('Manage Tasks'), findsOneWidget);
  });

  testWidgets('logs current 5-minute block from top quick action', (
    WidgetTester tester,
  ) async {
    final Box<dynamic> tasksBox = await Hive.openBox<dynamic>('tasks');
    await tasksBox.put('task-1', <String, dynamic>{
      'name': 'test',
      'category': 'General',
      'defaultMinutes': 30,
    });
    await tasksBox.put('task-2', <String, dynamic>{
      'name': 'test2',
      'category': 'General',
      'defaultMinutes': 30,
    });
    await tasksBox.put('task-3', <String, dynamic>{
      'name': 'test3',
      'category': 'General',
      'defaultMinutes': 30,
    });

    final Box<dynamic> taskSettingsBox = await Hive.openBox<dynamic>(
      'task_settings',
    );
    await taskSettingsBox.put('selected_task_id', 'task-3');

    await tester.pumpWidget(const MaterialApp(home: HomeDashboardScreen()));

    await pumpUntilVisible(tester, find.text('What are you doing right now?'));
    await pumpUntilVisible(tester, find.widgetWithText(FilledButton, 'test3'));

    expect(find.widgetWithText(FilledButton, 'test3'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'test'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'test2'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'test3'));
    await tester.pumpAndSettle();

    final DateTime slotStart = LogService().subslotStartFor(DateTime.now());
    final Box<dynamic> logsBox = await Hive.openBox<dynamic>('logs');
    final dynamic rawLog = logsBox.get(slotStart.toIso8601String());

    expect(rawLog, isA<Map<dynamic, dynamic>>());
    expect((rawLog as Map<dynamic, dynamic>)['taskId'], 'task-3');
  });
}
