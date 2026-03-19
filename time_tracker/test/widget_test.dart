import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:time_tracker/screens/task_list_screen.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'time_tracker_test',
  );
  Hive.init(tempDir.path);

  testWidgets('shows empty task state', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TaskListScreen(),
      ),
    );

    bool foundTaskHeading = false;
    for (int i = 0; i < 20; i += 1) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      if (find.text('Your Tasks').evaluate().isNotEmpty) {
        foundTaskHeading = true;
        break;
      }
    }

    expect(foundTaskHeading, isTrue, reason: 'Task list did not finish loading');
    expect(tester.takeException(), isNull);

    expect(find.text('Your Tasks'), findsOneWidget);
    expect(find.text('No tasks yet'), findsOneWidget);
    expect(find.text('Add Task'), findsWidgets);
    expect(find.text('Manage Tasks'), findsOneWidget);
  });
}
