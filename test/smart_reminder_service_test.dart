import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inklist/services/smart_reminder_service.dart';
import 'package:inklist/models/todo_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartReminderService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getCheckInTimes returns the default 4 times when unset', () async {
      final times = await SmartReminderService.getCheckInTimes();
      expect(times.length, 4);
      expect(times[0].hour, 9);
      expect(times[0].minute, 0);
      expect(times[1].hour, 13);
      expect(times[2].hour, 18);
      expect(times[3].hour, 21);
    });

    test('setCheckInTimes then getCheckInTimes round-trips correctly', () async {
      const custom = [
        TimeOfDayMs(hour: 7, minute: 30),
        TimeOfDayMs(hour: 12, minute: 15),
        TimeOfDayMs(hour: 20, minute: 0),
      ];
      await SmartReminderService.setCheckInTimes(custom);
      final times = await SmartReminderService.getCheckInTimes();
      expect(times.length, 3);
      expect(times[0].hour, 7);
      expect(times[0].minute, 30);
      expect(times[1].hour, 12);
      expect(times[1].minute, 15);
      expect(times[2].hour, 20);
      expect(times[2].minute, 0);
    });

    test('isEnabled defaults to false', () async {
      expect(await SmartReminderService.isEnabled(), isFalse);
    });

    test('setEnabled then isEnabled round-trips correctly', () async {
      await SmartReminderService.setEnabled(true);
      expect(await SmartReminderService.isEnabled(), isTrue);
      await SmartReminderService.setEnabled(false);
      expect(await SmartReminderService.isEnabled(), isFalse);
    });

    test('syncSchedule does not throw when the native MethodChannel is unavailable', () async {
      // No platform channel mock is registered in this test environment,
      // so invokeMethod will throw a MissingPluginException internally —
      // syncSchedule must swallow that, never propagate it.
      await expectLater(SmartReminderService.syncSchedule(), completes);
    });
  });
}
