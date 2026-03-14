import 'package:hive/hive.dart';

class SettingsService {
  static const String _boxName = 'settings';
  static const String _remindersEnabledKey = 'reminders_enabled';
  static const String _activeStartHourKey = 'active_start_hour';
  static const String _activeEndHourKey = 'active_end_hour';

  Future<bool> getRemindersEnabled() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_remindersEnabledKey, defaultValue: true);
    return value is bool ? value : true;
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_remindersEnabledKey, enabled);
  }

  Future<int> getActiveStartHour() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_activeStartHourKey, defaultValue: 7);
    final int hour = value is int ? value : int.tryParse(value.toString()) ?? 7;
    return hour.clamp(0, 23);
  }

  Future<int> getActiveEndHour() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_activeEndHourKey, defaultValue: 23);
    final int hour = value is int ? value : int.tryParse(value.toString()) ?? 23;
    return hour.clamp(0, 23);
  }

  Future<void> setActiveStartHour(int hour) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_activeStartHourKey, hour.clamp(0, 23));
  }

  Future<void> setActiveEndHour(int hour) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_activeEndHourKey, hour.clamp(0, 23));
  }
}
