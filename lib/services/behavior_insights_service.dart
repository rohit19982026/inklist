import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/todo_task.dart';
import 'recurrence_rule.dart';

/// Computes a compact, local-only summary of the user's actual behavior —
/// completion rates, timing patterns, streaks — so the AI prompts in
/// [GroqService] have real signal to reason about instead of just today's
/// task snapshot. Pure and network-free: everything here is arithmetic over
/// data the app already persists (tasks, habits, Pomodoro sessions).
class BehaviorInsightsService {
  BehaviorInsightsService._();

  static const windowDays = 14;

  // Below this many occurrences a rate is noise, not signal — omit the key
  // entirely rather than let the AI over-read a tiny sample.
  static const _minOccurrencesForRate = 3;
  static const _chronicThresholdPercent = 50;

  static const _weekdayNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  /// Builds the behavior snapshot. All lists should be the FULL history
  /// (e.g. `TodoService.getAll()`) — this method does its own windowing.
  static Map<String, dynamic> summarize({
    required List<TodoTask> tasks,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final windowStart = today.subtract(const Duration(days: windowDays - 1));

    final occurrences = _buildOccurrenceStream(tasks, windowStart, today);

    final out = <String, dynamic>{'windowDays': windowDays};

    final overall = _rate(occurrences.map((o) => o.done));
    if (overall != null && occurrences.length >= _minOccurrencesForRate) {
      out['completionRatePercent'] = overall;
    }

    final byWeekday = _groupRatePercent(
      occurrences,
      keyOf: (o) => _weekdayNames[o.weekday - 1],
    );
    if (byWeekday.isNotEmpty) out['completionRateByWeekday'] = byWeekday;

    final byPriority = _groupRatePercent(
      occurrences,
      keyOf: (o) => o.priority,
    );
    if (byPriority.isNotEmpty) out['completionRateByPriority'] = byPriority;

    final chronic = _chronicallyMissedTasks(tasks, windowStart, today);
    if (chronic.isNotEmpty) out['chronicallyMissedTasks'] = chronic;

    final streaks = _habitStreaks(habits, today, windowStart);
    if (streaks.isNotEmpty) out['habitStreaks'] = streaks;

    final windowSessions = sessions.where(
      (s) => !_dateOnly(s.completedAt).isBefore(windowStart) &&
          !_dateOnly(s.completedAt).isAfter(today),
    );
    if (windowSessions.isNotEmpty) {
      out['pomodoroSessionsPerDayAvg'] =
          double.parse((windowSessions.length / windowDays).toStringAsFixed(1));
      final topTasks = _topFocusedTasks(windowSessions.toList());
      if (topTasks.isNotEmpty) out['pomodoroTopFocusedTasks'] = topTasks;
    }

    return out;
  }

  // ── Occurrence stream: one (weekday, priority, done) tuple per relevant
  // day in the window, across both one-off and recurring tasks. ───────────

  static List<_Occurrence> _buildOccurrenceStream(
    List<TodoTask> tasks, DateTime windowStart, DateTime today,
  ) {
    final out = <_Occurrence>[];
    for (final t in tasks) {
      if (t.isRecurring) {
        var day = windowStart;
        while (!day.isAfter(today)) {
          if (RecurrenceRule.occursOn(t.recurrenceRule, day)) {
            out.add(_Occurrence(
              weekday: day.weekday,
              priority: t.priority,
              done: t.completedDates.contains(TodoTask.dateKey(day)),
            ));
          }
          day = day.add(const Duration(days: 1));
        }
      } else {
        final due = _dateOnly(t.dueDate);
        if (!due.isBefore(windowStart) && !due.isAfter(today)) {
          out.add(_Occurrence(
            weekday: due.weekday,
            priority: t.priority,
            done: t.isCompleted,
          ));
        }
      }
    }
    return out;
  }

  static Map<String, int> _groupRatePercent(
    List<_Occurrence> occurrences, {
    required String Function(_Occurrence) keyOf,
  }) {
    final buckets = <String, List<bool>>{};
    for (final o in occurrences) {
      buckets.putIfAbsent(keyOf(o), () => []).add(o.done);
    }
    final out = <String, int>{};
    buckets.forEach((key, doneList) {
      if (doneList.length < _minOccurrencesForRate) return;
      final rate = _rate(doneList);
      if (rate != null) out[key] = rate;
    });
    return out;
  }

  static int? _rate(Iterable<bool> doneList) {
    final list = doneList.toList();
    if (list.isEmpty) return null;
    final doneCount = list.where((d) => d).length;
    return ((doneCount / list.length) * 100).round();
  }

  // ── Chronically-missed recurring tasks ───────────────────────────────────

  static List<String> _chronicallyMissedTasks(
    List<TodoTask> tasks, DateTime windowStart, DateTime today,
  ) {
    final scored = <(String title, int rate, int occurrences)>[];
    for (final t in tasks) {
      if (!t.isRecurring) continue;
      var occurrences = 0, done = 0;
      var day = windowStart;
      while (!day.isAfter(today)) {
        if (RecurrenceRule.occursOn(t.recurrenceRule, day)) {
          occurrences++;
          if (t.completedDates.contains(TodoTask.dateKey(day))) done++;
        }
        day = day.add(const Duration(days: 1));
      }
      if (occurrences < _minOccurrencesForRate) continue;
      final rate = ((done / occurrences) * 100).round();
      if (rate < _chronicThresholdPercent) {
        scored.add((t.title, rate, occurrences));
      }
    }
    scored.sort((a, b) => a.$2.compareTo(b.$2));
    return scored.take(5).map((s) => s.$1).toList();
  }

  // ── Habit streaks ────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _habitStreaks(
    List<Habit> habits, DateTime today, DateTime windowStart,
  ) {
    final scored = habits.map((h) {
      final streak = h.currentStreak(today);
      var done = 0;
      var day = windowStart;
      while (!day.isAfter(today)) {
        if (h.isDoneOn(day)) done++;
        day = day.add(const Duration(days: 1));
      }
      final rate = ((done / windowDays) * 100).round();
      return (title: h.title, streak: streak, rate: rate);
    }).toList()
      ..sort((a, b) => b.streak.compareTo(a.streak));
    return scored
        .take(5)
        .map((s) => {
              'title': s.title,
              'streak': s.streak,
              'completionRatePercent': s.rate,
            })
        .toList();
  }

  // ── Pomodoro ──────────────────────────────────────────────────────────────

  static List<String> _topFocusedTasks(List<PomodoroSession> windowSessions) {
    final minutesByTask = <String, int>{};
    for (final s in windowSessions) {
      final title = s.taskTitle?.trim();
      if (title == null || title.isEmpty) continue;
      minutesByTask[title] = (minutesByTask[title] ?? 0) + s.minutes;
    }
    final entries = minutesByTask.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(3).map((e) => e.key).toList();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

class _Occurrence {
  final int weekday; // DateTime.weekday: 1=Mon..7=Sun
  final String priority;
  final bool done;
  const _Occurrence({
    required this.weekday,
    required this.priority,
    required this.done,
  });
}
