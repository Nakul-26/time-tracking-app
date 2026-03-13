import 'package:hive/hive.dart';

class SettingsService {
  static const String _boxName = 'settings';
  static const String _remindersEnabledKey = 'reminders_enabled';

  Future<bool> getRemindersEnabled() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_remindersEnabledKey, defaultValue: true);
    return value is bool ? value : true;
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_remindersEnabledKey, enabled);
  }
}
