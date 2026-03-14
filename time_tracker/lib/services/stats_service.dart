import '../models/activity_log.dart';
import 'log_service.dart';
import 'settings_service.dart';

class StatsTimelineSegment {
  const StatsTimelineSegment({
    required this.taskId,
    required this.startTime,
    required this.endTime,
    required this.isActive,
  });

  final String taskId;
  final DateTime startTime;
  final DateTime endTime;
  final bool isActive;

  int get minutes => endTime.difference(startTime).inMinutes.clamp(1, 1440);
}

class StatsWeekdayTimeline {
  const StatsWeekdayTimeline({
    required this.day,
    required this.segments,
  });

  final DateTime day;
  final List<StatsTimelineSegment> segments;
}

class StatsHeatmapDay {
  const StatsHeatmapDay({
    required this.date,
    required this.logged,
    required this.intensity,
  });

  final DateTime date;
  final Duration logged;
  final double intensity;
}

class StatsService {
  StatsService(this._logService, this._settingsService);

  final LogService _logService;
  final SettingsService _settingsService;

  Duration clipSession(
    DateTime start,
    DateTime end,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final DateTime clippedStart =
        start.isBefore(rangeStart) ? rangeStart : start;
    final DateTime clippedEnd = end.isAfter(rangeEnd) ? rangeEnd : end;

    if (!clippedEnd.isAfter(clippedStart)) {
      return Duration.zero;
    }

    return clippedEnd.difference(clippedStart);
  }

  DateTime startOfWeek(DateTime date) {
    final DateTime start = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(start.year, start.month, start.day);
  }

  Future<Map<String, Duration>> getDailyTaskTotals(DateTime day) async {
    final List<ActivityLog> logs = await _logService.getLogs();
    final DateTime start = DateTime(day.year, day.month, day.day);
    final DateTime end = start.add(const Duration(days: 1));
    return _aggregateTaskTotals(logs, start, end, day);
  }

  Future<Map<String, Duration>> getWeeklyTaskTotals(DateTime date) async {
    final List<ActivityLog> logs = await _logService.getLogs();
    final DateTime weekStart = startOfWeek(date);
    final DateTime weekEnd = weekStart.add(const Duration(days: 7));
    return _aggregateTaskTotals(logs, weekStart, weekEnd, date);
  }

  Future<Map<int, Duration>> getWeeklyDailyTotals(DateTime date) async {
    final List<ActivityLog> logs = await _logService.getLogs();
    final DateTime weekStart = startOfWeek(date);
    final Map<int, Duration> totals = <int, Duration>{};

    for (int dayIndex = 0; dayIndex < 7; dayIndex += 1) {
      final DateTime dayStart = weekStart.add(Duration(days: dayIndex));
      final DateTime dayEnd = dayStart.add(const Duration(days: 1));
      Duration dayTotal = Duration.zero;

      for (final ActivityLog log in logs) {
        final DateTime sessionEnd = log.endTime ?? DateTime.now();
        dayTotal += clipSession(log.startTime, sessionEnd, dayStart, dayEnd);
      }

      totals[dayIndex] = dayTotal;
    }

    return totals;
  }

  Future<List<StatsWeekdayTimeline>> getWeeklyTimeline(DateTime date) async {
    final List<ActivityLog> logs = await _logService.getLogs();
    final int startHour = await _settingsService.getActiveStartHour();
    final int endHour = await _settingsService.getActiveEndHour();
    final DateTime weekStart = startOfWeek(date);
    final DateTime now = DateTime.now();
    final List<StatsWeekdayTimeline> timeline = <StatsWeekdayTimeline>[];

    for (int dayIndex = 0; dayIndex < 7; dayIndex += 1) {
      final DateTime day = weekStart.add(Duration(days: dayIndex));
      final DateTime windowStart = DateTime(day.year, day.month, day.day, startHour);
      final DateTime windowEnd = DateTime(day.year, day.month, day.day, endHour);
      final List<StatsTimelineSegment> segments = logs
          .map(
            (ActivityLog log) => _clipLogToSegment(
              log,
              windowStart,
              windowEnd,
              now,
            ),
          )
          .whereType<StatsTimelineSegment>()
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      timeline.add(
        StatsWeekdayTimeline(
          day: day,
          segments: segments,
        ),
      );
    }

    return timeline;
  }

  Future<List<StatsHeatmapDay>> getMonthlyHeatmap(DateTime month) async {
    final List<ActivityLog> logs = await _logService.getLogs();
    final DateTime monthStart = DateTime(month.year, month.month, 1);
    final DateTime monthEnd = DateTime(month.year, month.month + 1, 1);
    final Duration activeDuration = await activeWindowDuration();
    final DateTime now = DateTime.now();
    final List<StatsHeatmapDay> days = <StatsHeatmapDay>[];

    for (DateTime day = monthStart;
        day.isBefore(monthEnd);
        day = day.add(const Duration(days: 1))) {
      final DateTime dayStart = DateTime(day.year, day.month, day.day);
      final DateTime dayEnd = dayStart.add(const Duration(days: 1));
      Duration total = Duration.zero;

      for (final ActivityLog log in logs) {
        final DateTime end = log.endTime ?? now;
        total += clipSession(log.startTime, end, dayStart, dayEnd);
      }

      final double intensity = activeDuration.inMinutes <= 0
          ? 0
          : (total.inMinutes / activeDuration.inMinutes).clamp(0.0, 1.0);

      days.add(
        StatsHeatmapDay(
          date: day,
          logged: total,
          intensity: intensity,
        ),
      );
    }

    return days;
  }

  Future<Duration> getDailyMissingTime(DateTime date) async {
    final Map<String, Duration> totals = await getDailyTaskTotals(date);
    final int loggedMinutes = totals.values.fold<int>(
      0,
      (int sum, Duration value) => sum + value.inMinutes,
    );
    final int expectedMinutes = await _expectedActiveMinutesForDay(date);
    return Duration(
      minutes: (expectedMinutes - loggedMinutes).clamp(0, expectedMinutes),
    );
  }

  Future<Duration> getWeeklyMissingTime(DateTime date) async {
    final Map<String, Duration> totals = await getWeeklyTaskTotals(date);
    final int loggedMinutes = totals.values.fold<int>(
      0,
      (int sum, Duration value) => sum + value.inMinutes,
    );
    final int expectedMinutes = await _expectedActiveMinutesForWeek(date);
    return Duration(
      minutes: (expectedMinutes - loggedMinutes).clamp(0, expectedMinutes),
    );
  }

  String formatDuration(Duration duration) {
    final int totalMinutes = duration.inMinutes;
    if (totalMinutes <= 0) {
      return '0m';
    }

    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;

    if (hours == 0) {
      return '${minutes}m';
    }

    if (minutes == 0) {
      return '${hours}h';
    }

    return '${hours}h ${minutes}m';
  }

  Future<Duration> activeWindowDuration() async {
    final int startHour = await _settingsService.getActiveStartHour();
    final int endHour = await _settingsService.getActiveEndHour();
    if (endHour <= startHour) {
      return Duration.zero;
    }

    return Duration(hours: endHour - startHour);
  }

  Future<Map<String, Duration>> _aggregateTaskTotals(
    List<ActivityLog> logs,
    DateTime rangeStart,
    DateTime rangeEnd,
    DateTime now,
  ) async {
    final Map<String, Duration> totals = <String, Duration>{};

    for (final ActivityLog log in logs) {
      final DateTime sessionEnd = log.endTime ?? now;
      final Duration duration = clipSession(
        log.startTime,
        sessionEnd,
        rangeStart,
        rangeEnd,
      );

      if (duration <= Duration.zero) {
        continue;
      }

      totals.update(
        log.taskId,
        (Duration value) => value + duration,
        ifAbsent: () => duration,
      );
    }

    return totals;
  }

  StatsTimelineSegment? _clipLogToSegment(
    ActivityLog log,
    DateTime rangeStart,
    DateTime rangeEnd,
    DateTime now,
  ) {
    final DateTime effectiveEnd = log.endTime ?? now;
    final DateTime clippedStart =
        log.startTime.isBefore(rangeStart) ? rangeStart : log.startTime;
    final DateTime clippedEnd =
        effectiveEnd.isAfter(rangeEnd) ? rangeEnd : effectiveEnd;

    if (!clippedEnd.isAfter(clippedStart)) {
      return null;
    }

    return StatsTimelineSegment(
      taskId: log.taskId,
      startTime: clippedStart,
      endTime: clippedEnd,
      isActive: log.endTime == null,
    );
  }

  Future<int> _expectedActiveMinutesForDay(DateTime date) async {
    final int startHour = await _settingsService.getActiveStartHour();
    final int endHour = await _settingsService.getActiveEndHour();
    final DateTime dayStart = DateTime(date.year, date.month, date.day, startHour);
    final DateTime dayEnd = DateTime(date.year, date.month, date.day, endHour);

    if (!dayEnd.isAfter(dayStart)) {
      return 0;
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime targetDay = DateTime(date.year, date.month, date.day);

    if (targetDay.isAfter(today)) {
      return 0;
    }

    final int expectedMinutes;
    if (targetDay == today) {
      if (now.isBefore(dayStart)) {
        expectedMinutes = 0;
      } else if (now.isAfter(dayEnd)) {
        expectedMinutes = dayEnd.difference(dayStart).inMinutes;
      } else {
        expectedMinutes = now.difference(dayStart).inMinutes;
      }
    } else {
      expectedMinutes = dayEnd.difference(dayStart).inMinutes;
    }

    return expectedMinutes;
  }

  Future<int> _expectedActiveMinutesForWeek(DateTime date) async {
    final DateTime weekStart = startOfWeek(date);
    int totalMinutes = 0;

    for (int dayIndex = 0; dayIndex < 7; dayIndex += 1) {
      totalMinutes += await _expectedActiveMinutesForDay(
        weekStart.add(Duration(days: dayIndex)),
      );
    }

    return totalMinutes;
  }
}
