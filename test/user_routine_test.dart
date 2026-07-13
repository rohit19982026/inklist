import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/models/todo_task.dart';
import 'package:inklist/models/user_routine.dart';

void main() {
  group('UserRoutine', () {
    test('isEmpty is true only when every field is unset', () {
      expect(const UserRoutine().isEmpty, isTrue);
      expect(
        const UserRoutine(wakeTime: TimeOfDayMs(hour: 7, minute: 0)).isEmpty,
        isFalse,
      );
    });

    test('toPromptContext only includes fields that are set, as HH:MM', () {
      const routine = UserRoutine(
        wakeTime: TimeOfDayMs(hour: 7, minute: 0),
        sleepTime: TimeOfDayMs(hour: 23, minute: 30),
      );
      final ctx = routine.toPromptContext();
      expect(ctx['wakeTime'], '07:00');
      expect(ctx['sleepTime'], '23:30');
      expect(ctx.containsKey('workStart'), isFalse);
      expect(ctx.containsKey('workEnd'), isFalse);
    });

    test('empty routine produces an empty prompt context', () {
      expect(const UserRoutine().toPromptContext(), isEmpty);
    });

    test('copyWith sets a field without disturbing the others', () {
      const routine = UserRoutine(wakeTime: TimeOfDayMs(hour: 7, minute: 0));
      final updated = routine.copyWith(sleepTime: const TimeOfDayMs(hour: 22, minute: 0));
      expect(updated.wakeTime?.hour, 7);
      expect(updated.sleepTime?.hour, 22);
    });

    test('copyWith with a clear flag removes just that field', () {
      const routine = UserRoutine(
        wakeTime: TimeOfDayMs(hour: 7, minute: 0),
        sleepTime: TimeOfDayMs(hour: 22, minute: 0),
      );
      final updated = routine.copyWith(clearWakeTime: true);
      expect(updated.wakeTime, isNull);
      expect(updated.sleepTime?.hour, 22);
    });

    test('JSON round-trips all four fields', () {
      const routine = UserRoutine(
        wakeTime: TimeOfDayMs(hour: 6, minute: 30),
        sleepTime: TimeOfDayMs(hour: 23, minute: 0),
        workStart: TimeOfDayMs(hour: 9, minute: 0),
        workEnd: TimeOfDayMs(hour: 18, minute: 0),
      );
      final decoded = UserRoutine.fromJson(routine.toJson());
      expect(decoded.wakeTime?.hour, 6);
      expect(decoded.wakeTime?.minute, 30);
      expect(decoded.sleepTime?.hour, 23);
      expect(decoded.workStart?.hour, 9);
      expect(decoded.workEnd?.hour, 18);
    });

    test('fromJson on an empty map yields an empty routine', () {
      expect(UserRoutine.fromJson(const {}).isEmpty, isTrue);
    });
  });
}
