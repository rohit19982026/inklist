import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/models/habit.dart';

void main() {
  Habit habitWith(Set<String> dates) => Habit(
        id: 'h1',
        title: 'Drink water',
        colorValue: 0xFFCDEFD8,
        completedDates: dates,
        createdAt: DateTime(2026, 1, 1),
      );

  String key(DateTime d) => Habit.dateKey(d);

  group('Habit.currentStreak', () {
    test('counts consecutive days ending today', () {
      final today = DateTime(2026, 7, 13);
      final h = habitWith({
        key(today),
        key(today.subtract(const Duration(days: 1))),
        key(today.subtract(const Duration(days: 2))),
      });
      expect(h.currentStreak(today), 3);
    });

    test('stays alive when today is not done but yesterday was', () {
      final today = DateTime(2026, 7, 13);
      final h = habitWith({
        key(today.subtract(const Duration(days: 1))),
        key(today.subtract(const Duration(days: 2))),
      });
      expect(h.currentStreak(today), 2);
    });

    test('is zero when neither today nor yesterday is done', () {
      final today = DateTime(2026, 7, 13);
      final h = habitWith({key(today.subtract(const Duration(days: 3)))});
      expect(h.currentStreak(today), 0);
    });

    test('breaks on the first missed day', () {
      final today = DateTime(2026, 7, 13);
      final h = habitWith({
        key(today),
        key(today.subtract(const Duration(days: 1))),
        // gap at day 2
        key(today.subtract(const Duration(days: 3))),
      });
      expect(h.currentStreak(today), 2);
    });

    test('empty history is a zero streak', () {
      expect(habitWith({}).currentStreak(DateTime(2026, 7, 13)), 0);
    });
  });

  group('Habit.completionsInWeek', () {
    test('counts only days inside the 7-day window', () {
      final weekStart = DateTime(2026, 7, 13); // a Monday
      final h = habitWith({
        key(weekStart),
        key(weekStart.add(const Duration(days: 2))),
        key(weekStart.add(const Duration(days: 6))),
        key(weekStart.subtract(const Duration(days: 1))), // previous week
        key(weekStart.add(const Duration(days: 7))), // next week
      });
      expect(h.completionsInWeek(weekStart), 3);
    });
  });

  group('Habit.isDoneOn', () {
    test('reflects membership in completedDates', () {
      final day = DateTime(2026, 7, 13);
      expect(habitWith({key(day)}).isDoneOn(day), isTrue);
      expect(habitWith({}).isDoneOn(day), isFalse);
    });
  });

  group('Habit JSON', () {
    test('round-trips including completedDates', () {
      final h = Habit(
        id: 'abc',
        title: 'Read',
        emoji: '📚',
        colorValue: 0xFFE6DBFF,
        completedDates: {'2026-07-12', '2026-07-13'},
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final r = Habit.fromJson(h.toJson());
      expect(r.id, 'abc');
      expect(r.title, 'Read');
      expect(r.emoji, '📚');
      expect(r.colorValue, 0xFFE6DBFF);
      expect(r.completedDates, {'2026-07-12', '2026-07-13'});
      expect(r.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('tolerates a malformed/empty map with sensible defaults', () {
      final r = Habit.fromJson(const {'id': 'x'});
      expect(r.id, 'x');
      expect(r.emoji, '🌱');
      expect(r.completedDates, isEmpty);
    });
  });
}
