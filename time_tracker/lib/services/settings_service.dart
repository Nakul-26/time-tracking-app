import 'package:hive/hive.dart';

class SettingsService {
  static const String _boxName = 'settings';
  static const String _remindersEnabledKey = 'reminders_enabled';
  static const String _activeStartHourKey = 'active_start_hour';
  static const String _activeEndHourKey = 'active_end_hour';
  static const String _nextReminderAtKey = 'next_reminder_at';
  static const String _nextReminderDurationMinutesKey =
      'next_reminder_duration_minutes';
  static const String _dailySummaryEnabledKey = 'daily_summary_enabled';
  static const String _dailySummaryHourKey = 'daily_summary_hour';
  static const String _dailySummaryMinuteKey = 'daily_summary_minute';
  static const String _weeklySummaryEnabledKey = 'weekly_summary_enabled';
  static const String _weeklySummaryWeekdayKey = 'weekly_summary_weekday';
  static const String _weeklySummaryHourKey = 'weekly_summary_hour';
  static const String _weeklySummaryMinuteKey = 'weekly_summary_minute';

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
    final dynamic value = box.get(_activeEndHourKey, defaultValue: 24);
    final int hour = value is int ? value : int.tryParse(value.toString()) ?? 24;
    return hour.clamp(0, 24);
  }

  Future<void> setActiveStartHour(int hour) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_activeStartHourKey, hour.clamp(0, 23));
  }

  Future<void> setActiveEndHour(int hour) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_activeEndHourKey, hour.clamp(0, 24));
  }

  Future<DateTime?> getNextReminderAt() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_nextReminderAtKey);
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  Future<void> setNextReminderAt(DateTime? value) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    if (value == null) {
      await box.delete(_nextReminderAtKey);
      return;
    }

    await box.put(_nextReminderAtKey, value.toIso8601String());
  }

  Future<int> getNextReminderDurationMinutes() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(
      _nextReminderDurationMinutesKey,
      defaultValue: 30,
    );
    final int minutes =
        value is int ? value : int.tryParse(value.toString()) ?? 30;
    return minutes <= 0 ? 30 : minutes;
  }

  Future<void> setNextReminderDurationMinutes(int minutes) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(
      _nextReminderDurationMinutesKey,
      minutes <= 0 ? 30 : minutes,
    );
  }

  bool isFullDayWindow(int startHour, int endHour) {
    return startHour == 0 && endHour == 24;
  }

  Future<bool> getDailySummaryEnabled() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_dailySummaryEnabledKey, defaultValue: true);
    return value is bool ? value : true;
  }

  Future<void> setDailySummaryEnabled(bool enabled) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_dailySummaryEnabledKey, enabled);
  }

  Future<int> getDailySummaryHour() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_dailySummaryHourKey, defaultValue: 22);
    final int hour = value is int ? value : int.tryParse(value.toString()) ?? 22;
    return hour.clamp(0, 23);
  }

  Future<int> getDailySummaryMinute() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_dailySummaryMinuteKey, defaultValue: 30);
    final int minute =
        value is int ? value : int.tryParse(value.toString()) ?? 30;
    return minute.clamp(0, 59);
  }

  Future<void> setDailySummaryTime({
    required int hour,
    required int minute,
  }) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_dailySummaryHourKey, hour.clamp(0, 23));
    await box.put(_dailySummaryMinuteKey, minute.clamp(0, 59));
  }

  Future<bool> getWeeklySummaryEnabled() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_weeklySummaryEnabledKey, defaultValue: true);
    return value is bool ? value : true;
  }

  Future<void> setWeeklySummaryEnabled(bool enabled) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_weeklySummaryEnabledKey, enabled);
  }

  Future<int> getWeeklySummaryWeekday() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_weeklySummaryWeekdayKey, defaultValue: 7);
    final int weekday =
        value is int ? value : int.tryParse(value.toString()) ?? 7;
    return weekday.clamp(1, 7);
  }

  Future<int> getWeeklySummaryHour() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_weeklySummaryHourKey, defaultValue: 21);
    final int hour = value is int ? value : int.tryParse(value.toString()) ?? 21;
    return hour.clamp(0, 23);
  }

  Future<int> getWeeklySummaryMinute() async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    final dynamic value = box.get(_weeklySummaryMinuteKey, defaultValue: 0);
    final int minute =
        value is int ? value : int.tryParse(value.toString()) ?? 0;
    return minute.clamp(0, 59);
  }

  Future<void> setWeeklySummarySchedule({
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    final Box<dynamic> box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_weeklySummaryWeekdayKey, weekday.clamp(1, 7));
    await box.put(_weeklySummaryHourKey, hour.clamp(0, 23));
    await box.put(_weeklySummaryMinuteKey, minute.clamp(0, 59));
  }
}
