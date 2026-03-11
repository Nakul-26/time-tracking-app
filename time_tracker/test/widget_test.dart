import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:time_tracker/main.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  testWidgets('shows empty task state', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Your Tasks'), findsOneWidget);
    expect(find.text('No tasks yet'), findsOneWidget);
    expect(find.text('Add Task'), findsWidgets);
    expect(find.text('Log Current Activity'), findsOneWidget);
  });
}
