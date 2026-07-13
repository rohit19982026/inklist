import '../models/pomodoro.dart';
import '../models/todo_task.dart'; // TimeOfDayMs

/// Suggests Smart Reminders check-in times from the user's own Pomodoro
/// session history, instead of the same fixed 9am/1pm/6pm/9pm for everyone.
/// Local, offline statistics — not an AI call — since "what hours is this
/// person usually active" is a histogram, not a judgment call. Always a
/// suggestion, never auto-applied: Settings shows it with a "Use These"
/// button, same as every other AI-adjacent suggestion in this app.
class ReminderScheduleAdvisor {
  ReminderScheduleAdvisor._();

  static const windowDays = 14;
  static const _minSessionsForSignal = 8;
  static const _maxSuggestions = 4;
  static const _minHourSpacing = 3;
  static const _fallbackHours = [9, 13, 18, 21];

  /// Returns up to 4 suggested check-in times, or null if there isn't
  /// enough Pomodoro session history yet to say anything meaningful.
  static List<TimeOfDayMs>? suggestCheckInTimes(
    List<PomodoroSession> sessions, {
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final windowStart = today.subtract(const Duration(days: windowDays - 1));
    final windowSessions = sessions.where((s) {
      final d = _dateOnly(s.completedAt);
      return !d.isBefore(windowStart) && !d.isAfter(today);
    }).toList();

    if (windowSessions.length < _minSessionsForSignal) return null;

    final counts = List<int>.filled(24, 0);
    for (final s in windowSessions) {
      counts[s.completedAt.hour]++;
    }

    final hoursByCount = List<int>.generate(24, (h) => h)
      ..sort((a, b) => counts[b].compareTo(counts[a]));

    final picked = <int>[];
    for (final hour in hoursByCount) {
      if (counts[hour] == 0) break;
      final tooClose = picked.any((p) => (p - hour).abs() < _minHourSpacing);
      if (tooClose) continue;
      picked.add(hour);
      if (picked.length == _maxSuggestions) break;
    }

    for (final fallback in _fallbackHours) {
      if (picked.length == _maxSuggestions) break;
      final tooClose =
          picked.any((p) => (p - fallback).abs() < _minHourSpacing);
      if (tooClose || picked.contains(fallback)) continue;
      picked.add(fallback);
    }

    picked.sort();
    return picked.map((h) => TimeOfDayMs(hour: h, minute: 0)).toList();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
