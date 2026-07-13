import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/models/habit.dart';
import 'package:inklist/models/pomodoro.dart';
import 'package:inklist/models/todo_task.dart';
import 'package:inklist/services/behavior_insights_service.dart';

void main() {
  final now = DateTime(2026, 7, 13);

  TodoTask oneOff({
    required String title,
    required DateTime due,
    String priority = 'medium',
    bool done = false,
  }) =>
      TodoTask(
        id: title,
        title: title,
        dueDate: due,
        priority: priority,
        isCompleted: done,
        createdAt: due,
      );

  TodoTask recurring({
    required String title,
    required String rule,
    Set<String> completedDates = const {},
    String priority = 'medium',
  }) =>
      TodoTask(
        id: title,
        title: title,
        dueDate: DateTime(2026, 1, 1),
        priority: priority,
        recurrenceRule: rule,
        completedDates: completedDates,
        createdAt: DateTime(2026, 1, 1),
      );

  Habit habit({required String title, required Set<String> completedDates}) =>
      Habit(
        id: title,
        title: title,
        colorValue: 0xFFCDEFD8,
        completedDates: completedDates,
        createdAt: DateTime(2026, 1, 1),
      );

  Set<String> lastNDays(int n, {DateTime? end}) {
    final e = end ?? now;
    return {
      for (var i = 0; i < n; i++) TodoTask.dateKey(e.subtract(Duration(days: i))),
    };
  }

  group('BehaviorInsightsService.summarize', () {
    test('returns just windowDays when there is no data', () {
      final result = BehaviorInsightsService.summarize(
        tasks: const [],
        habits: const [],
        sessions: const [],
        now: now,
      );
      expect(result, {'windowDays': 14});
    });

    test('computes overall + per-priority completion rate from one-off tasks', () {
      final tasks = [
        oneOff(title: 'High 1', due: now, priority: 'high', done: true),
        oneOff(title: 'High 2', due: now.subtract(const Duration(days: 1)),
            priority: 'high', done: true),
        oneOff(title: 'High 3', due: now.subtract(const Duration(days: 2)),
            priority: 'high', done: true),
        oneOff(title: 'Low 1', due: now, priority: 'low', done: false),
        oneOff(title: 'Low 2', due: now.subtract(const Duration(days: 1)),
            priority: 'low', done: false),
        oneOff(title: 'Low 3', due: now.subtract(const Duration(days: 2)),
            priority: 'low', done: false),
      ];
      final result = BehaviorInsightsService.summarize(
        tasks: tasks, habits: const [], sessions: const [], now: now,
      );
      expect(result['completionRatePercent'], 50);
      expect(result['completionRateByPriority'], {'high': 100, 'low': 0});
    });

    test('computes completion rate by weekday from recurring daily tasks', () {
      // Two daily tasks over a 14-day window: every weekday occurs exactly
      // twice per task (4 samples per weekday bucket, clearing the min-3
      // guard). Task A always done, Task B never done -> 50% every weekday.
      final windowDates = {
        for (var i = 0; i < 14; i++) TodoTask.dateKey(now.subtract(Duration(days: i))),
      };
      final tasks = [
        recurring(title: 'Always done', rule: 'daily', completedDates: windowDates),
        recurring(title: 'Never done', rule: 'daily'),
      ];
      final result = BehaviorInsightsService.summarize(
        tasks: tasks, habits: const [], sessions: const [], now: now,
      );
      expect(result['completionRatePercent'], 50);
      final byWeekday = result['completionRateByWeekday'] as Map;
      expect(byWeekday.length, 7);
      expect(byWeekday.values.toSet(), {50});
    });

    test('flags a chronically missed recurring task (>=3 occurrences, <50%)', () {
      final tasks = [
        recurring(
          title: 'Evening workout',
          rule: 'daily',
          completedDates: {TodoTask.dateKey(now)}, // 1 of 14 days
        ),
      ];
      final result = BehaviorInsightsService.summarize(
        tasks: tasks, habits: const [], sessions: const [], now: now,
      );
      expect(result['chronicallyMissedTasks'], ['Evening workout']);
    });

    test('does not flag a recurring task with a healthy completion rate', () {
      final windowDates = {
        for (var i = 0; i < 12; i++) TodoTask.dateKey(now.subtract(Duration(days: i))),
      };
      final tasks = [
        recurring(title: 'Mostly done', rule: 'daily', completedDates: windowDates),
      ];
      final result = BehaviorInsightsService.summarize(
        tasks: tasks, habits: const [], sessions: const [], now: now,
      );
      expect(result.containsKey('chronicallyMissedTasks'), isFalse);
    });

    test('does not flag a recurring task with too few occurrences in the window', () {
      // A single weekly slot occurs exactly twice in any 14-day window --
      // below the min-3-occurrences guard, however bad its rate is.
      final tasks = [
        recurring(title: 'Rare task', rule: 'weekly:MON'),
      ];
      final result = BehaviorInsightsService.summarize(
        tasks: tasks, habits: const [], sessions: const [], now: now,
      );
      expect(result.containsKey('chronicallyMissedTasks'), isFalse);
    });

    test('ranks habit streaks by streak length, includes completion rate', () {
      final habits = [
        habit(title: 'Weak habit', completedDates: {TodoTask.dateKey(now)}),
        habit(title: 'Strong habit', completedDates: lastNDays(10, end: now)),
      ];
      final result = BehaviorInsightsService.summarize(
        tasks: const [], habits: habits, sessions: const [], now: now,
      );
      final streaks = result['habitStreaks'] as List;
      expect(streaks.first, {
        'title': 'Strong habit',
        'streak': 10,
        'completionRatePercent': ((10 / 14) * 100).round(),
      });
      expect(streaks.last['title'], 'Weak habit');
    });

    test('computes pomodoro sessions-per-day average and top focused tasks', () {
      final sessions = [
        PomodoroSession(completedAt: now, minutes: 25, taskTitle: 'Write report'),
        PomodoroSession(completedAt: now, minutes: 25, taskTitle: 'Write report'),
        PomodoroSession(
            completedAt: now.subtract(const Duration(days: 1)),
            minutes: 25,
            taskTitle: 'Study'),
      ];
      final result = BehaviorInsightsService.summarize(
        tasks: const [], habits: const [], sessions: sessions, now: now,
      );
      expect(result['pomodoroSessionsPerDayAvg'], 0.2); // 3 / 14
      expect(result['pomodoroTopFocusedTasks'], ['Write report', 'Study']);
    });

    test('omits pomodoro keys entirely when there are no sessions in the window', () {
      final sessions = [
        PomodoroSession(
          completedAt: now.subtract(const Duration(days: 30)),
          minutes: 25,
          taskTitle: 'Old task',
        ),
      ];
      final result = BehaviorInsightsService.summarize(
        tasks: const [], habits: const [], sessions: sessions, now: now,
      );
      expect(result.containsKey('pomodoroSessionsPerDayAvg'), isFalse);
      expect(result.containsKey('pomodoroTopFocusedTasks'), isFalse);
    });
  });
}
