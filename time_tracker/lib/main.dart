import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'screens/main_navigation_screen.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  await NotificationService.handleNotificationResponse(response);
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((String task, Map<String, dynamic>? inputData) async {
    await NotificationService.runBackgroundTask(task, inputData);
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );
  await NotificationService.init(appNavigatorKey);
  await NotificationService.initForegroundTask();
  runApp(const MyApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(NotificationService.handleAppLaunchNotification());
  });
  unawaited(_syncRemindersSafely());
}

Future<void> _syncRemindersSafely() async {
  try {
    await NotificationService.syncReminders();
  } catch (_) {
    // Keep startup resilient if Android notification scheduling fails.
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'Time Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E847F),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF4F7F3),
          useMaterial3: true,
        ),
        home: const MainNavigationScreen(),
      ),
    );
  }
}
