import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/models/pomodoro.dart';
import 'package:inklist/services/reminder_schedule_advisor.dart';

void main() {
  final now = DateTime(2026, 7, 13); // a Monday

  PomodoroSession sessionAt(int daysAgo, int hour) => PomodoroSession(
        completedAt: DateTime(now.year, now.month, now.day - daysAgo, hour, 0),
        minutes: 25,
      );

  group('ReminderScheduleAdvisor.suggestCheckInTimes', () {
    test('returns null with fewer than 8 sessions in the window', () {
      final sessions = List.generate(5, (i) => sessionAt(i, 10));
      expect(ReminderScheduleAdvisor.suggestCheckInTimes(sessions, now: now),
          isNull);
    });

    test('ignores sessions outside the 14-day window', () {
      final sessions = List.generate(10, (i) => sessionAt(30 + i, 10));
      expect(ReminderScheduleAdvisor.suggestCheckInTimes(sessions, now: now),
          isNull);
    });

    test('picks the most frequent hour as a suggested time', () {
      final sessions = List.generate(9, (i) => sessionAt(i, 7));
      final result =
          ReminderScheduleAdvisor.suggestCheckInTimes(sessions, now: now);
      expect(result, isNotNull);
      expect(result!.length, 4);
      expect(result.any((t) => t.hour == 7), isTrue);
    });

    test('a real peak takes priority over a fallback hour it would collide with',
        () {
      // 7am is a real peak; 8pm (20) is a smaller real peak. Fallback hour 9
      // is too close to 7 to also be suggested.
      final sessions = [
        ...List.generate(6, (i) => sessionAt(i, 7)),
        ...List.generate(3, (i) => sessionAt(i, 20)),
      ];
      final result =
          ReminderScheduleAdvisor.suggestCheckInTimes(sessions, now: now)!;
      final hours = result.map((t) => t.hour).toList();
      expect(hours, contains(7));
      expect(hours, contains(20));
      expect(hours, isNot(contains(9)));
    });

    test('suggested hours are always sorted and at least 3 hours apart', () {
      final sessions = [
        ...List.generate(4, (i) => sessionAt(i, 6)),
        ...List.generate(4, (i) => sessionAt(i, 7)), // too close to 6am
        ...List.generate(4, (i) => sessionAt(i, 15)),
      ];
      final result =
          ReminderScheduleAdvisor.suggestCheckInTimes(sessions, now: now)!;
      final hours = result.map((t) => t.hour).toList();
      expect(hours, orderedEquals(List.of(hours)..sort()));
      for (var i = 1; i < hours.length; i++) {
        expect(hours[i] - hours[i - 1], greaterThanOrEqualTo(3));
      }
    });

    test('pads with fallback hours when fewer than 4 real peaks exist', () {
      final sessions = List.generate(8, (i) => sessionAt(i, 10));
      final result =
          ReminderScheduleAdvisor.suggestCheckInTimes(sessions, now: now)!;
      expect(result.length, 4);
      expect(result.any((t) => t.hour == 10), isTrue);
    });
  });
}
