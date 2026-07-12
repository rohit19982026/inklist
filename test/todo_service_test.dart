import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/models/todo_task.dart';
import 'package:inklist/services/recurrence_rule.dart';
import 'package:inklist/services/todo_service.dart';

void main() {
  group('RecurrenceRule.occursOn', () {
    test('none never occurs', () {
      expect(RecurrenceRule.occursOn('none', DateTime(2026, 1, 1)), isFalse);
    });

    test('daily occurs every day', () {
      for (var d = 1; d <= 28; d++) {
        expect(RecurrenceRule.occursOn('daily', DateTime(2026, 3, d)), isTrue);
      }
    });

    test('weekly occurs only on selected weekdays across a full week', () {
      const rule = 'weekly:MON,WED,FRI';
      // 2026-03-02 is a Monday.
      final monday = DateTime(2026, 3, 2);
      final expected = [true, false, true, false, true, false, false];
      for (var i = 0; i < 7; i++) {
        expect(RecurrenceRule.occursOn(rule, monday.add(Duration(days: i))),
            expected[i],
            reason: 'day offset $i');
      }
    });

    test('monthly:N occurs only on that day of month, across a month boundary', () {
      const rule = 'monthly:1';
      expect(RecurrenceRule.occursOn(rule, DateTime(2026, 2, 1)), isTrue);
      expect(RecurrenceRule.occursOn(rule, DateTime(2026, 3, 1)), isTrue);
      expect(RecurrenceRule.occursOn(rule, DateTime(2026, 2, 28)), isFalse);
    });

    test('monthly:last occurs on the last day of variable-length months', () {
      const rule = 'monthly:last';
      expect(RecurrenceRule.occursOn(rule, DateTime(2026, 2, 28)), isTrue); // Feb, non-leap
      expect(RecurrenceRule.occursOn(rule, DateTime(2024, 2, 29)), isTrue); // Feb, leap year
      expect(RecurrenceRule.occursOn(rule, DateTime(2024, 2, 28)), isFalse);
      expect(RecurrenceRule.occursOn(rule, DateTime(2026, 4, 30)), isTrue); // 30-day month
      expect(RecurrenceRule.occursOn(rule, DateTime(2026, 12, 31)), isTrue);
    });
  });

  group('TodoService query helpers', () {
    final fixture = <TodoTask>[
      TodoTask(
        id: 'one-off-today',
        title: 'One-off today',
        dueDate: DateTime(2026, 3, 10),
        createdAt: DateTime(2026, 3, 1),
      ),
      TodoTask(
        id: 'one-off-past',
        title: 'One-off overdue',
        dueDate: DateTime(2026, 3, 5),
        createdAt: DateTime(2026, 3, 1),
      ),
      TodoTask(
        id: 'one-off-past-done',
        title: 'One-off overdue but completed',
        dueDate: DateTime(2026, 3, 5),
        isCompleted: true,
        createdAt: DateTime(2026, 3, 1),
      ),
      TodoTask(
        id: 'daily-recurring',
        title: 'Daily habit',
        dueDate: DateTime(2026, 3, 1),
        recurrenceRule: 'daily',
        completedDates: {'2026-03-10'},
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    test('tasksForDay includes matching one-off and recurring tasks', () {
      final day = DateTime(2026, 3, 10);
      final result = TodoService.tasksForDay(fixture, day);
      final ids = result.map((t) => t.id).toSet();
      expect(ids, containsAll(['one-off-today', 'daily-recurring']));
      expect(ids, isNot(contains('one-off-past')));
    });

    test(
        'a completed recurring occurrence still appears in tasksForDay, '
        'but reports isCompletedOn == true', () {
      final day = DateTime(2026, 3, 10);
      final result = TodoService.tasksForDay(fixture, day);
      final daily = result.firstWhere((t) => t.id == 'daily-recurring');
      expect(daily.isCompletedOn(day), isTrue);
      final otherDay = DateTime(2026, 3, 11);
      final dailyOther = TodoService.tasksForDay(fixture, otherDay)
          .firstWhere((t) => t.id == 'daily-recurring');
      expect(dailyOther.isCompletedOn(otherDay), isFalse);
    });

    test('tasksForWeek returns tasks spanning all 7 days including a month boundary', () {
      final weekStart = DateTime(2026, 2, 23); // Mon 23 Feb -> Sun 1 Mar
      final result = TodoService.tasksForWeek(fixture, weekStart);
      // 'daily-recurring' occurs every day in that window (7 hits), plus
      // 'one-off-today' due 2026-03-10 which is NOT inside this window.
      expect(result.where((t) => t.id == 'daily-recurring').length, 7);
      expect(result.any((t) => t.id == 'one-off-today'), isFalse);
    });

    test('overdueTasks returns only non-recurring, past-due, incomplete tasks', () {
      final asOf = DateTime(2026, 3, 10);
      final result = TodoService.overdueTasks(fixture, asOf: asOf);
      final ids = result.map((t) => t.id).toSet();
      expect(ids, {'one-off-past'});
      expect(ids, isNot(contains('one-off-past-done')));
      expect(ids, isNot(contains('daily-recurring')),
          reason: 'recurring tasks have no overdue concept');
    });

    test('startOfWeek returns the Monday of the given date\'s week', () {
      final wed = DateTime(2026, 3, 11); // Wednesday
      final start = TodoService.startOfWeek(wed);
      expect(start.weekday, DateTime.monday);
      expect(start.isBefore(wed) || start.isAtSameMomentAs(wed), isTrue);
    });
  });

  group('TodoTask JSON round-trip', () {
    test('round-trips all fields including subtasks and completedDates', () {
      final original = TodoTask(
        id: 'abc123',
        title: 'Pay rent',
        description: 'Every 1st of the month',
        dueDate: DateTime(2026, 4, 1),
        alarmTime: const TimeOfDayMs(hour: 9, minute: 30),
        priority: 'high',
        isCompleted: false,
        alarmEnabled: true,
        recurrenceRule: 'monthly:1',
        completedDates: {'2026-03-01', '2026-02-01'},
        subtasks: const [
          TodoSubtask(id: 's1', title: 'Transfer to landlord', done: true),
          TodoSubtask(id: 's2', title: 'Get receipt', done: false),
        ],
        aiGenerated: true,
        createdAt: DateTime(2026, 1, 1),
      );

      final decoded = TodoTask.fromJson(original.toJson());

      expect(decoded.id, original.id);
      expect(decoded.title, original.title);
      expect(decoded.description, original.description);
      expect(decoded.dueDate, original.dueDate);
      expect(decoded.alarmTime?.hour, 9);
      expect(decoded.alarmTime?.minute, 30);
      expect(decoded.priority, 'high');
      expect(decoded.alarmEnabled, isTrue);
      expect(decoded.recurrenceRule, 'monthly:1');
      expect(decoded.completedDates, {'2026-03-01', '2026-02-01'});
      expect(decoded.subtasks.length, 2);
      expect(decoded.subtasks[0].title, 'Transfer to landlord');
      expect(decoded.subtasks[0].done, isTrue);
      expect(decoded.aiGenerated, isTrue);
      expect(decoded.createdAt, original.createdAt);
    });
  });
}
