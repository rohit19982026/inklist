import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inklist/services/ai_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AiFeedbackService.summarize', () {
    test('omits keys with fewer than 3 samples (noise floor)', () async {
      await AiFeedbackService.logAlarmTimeOutcome(accepted: true);
      await AiFeedbackService.logAlarmTimeOutcome(accepted: false, deltaMinutes: 10);
      final summary = await AiFeedbackService.summarize();
      expect(summary.containsKey('alarmTimeSuggestions'), isFalse);
    });

    test('computes acceptedPercent and avgEditMinutes once there are enough samples',
        () async {
      await AiFeedbackService.logAlarmTimeOutcome(accepted: true, deltaMinutes: 0);
      await AiFeedbackService.logAlarmTimeOutcome(accepted: false, deltaMinutes: 20);
      await AiFeedbackService.logAlarmTimeOutcome(accepted: false, deltaMinutes: 40);
      final summary = await AiFeedbackService.summarize();
      final alarm = summary['alarmTimeSuggestions'] as Map<String, dynamic>;
      expect(alarm['total'], 3);
      expect(alarm['acceptedPercent'], 33);
      expect(alarm['avgEditMinutes'], 20); // (0 + 20 + 40) / 3
    });

    test('priority and habit suggestions are tracked independently', () async {
      await AiFeedbackService.logPriorityOutcome(accepted: true);
      await AiFeedbackService.logPriorityOutcome(accepted: true);
      await AiFeedbackService.logPriorityOutcome(accepted: false, changedDirection: 'higher');
      await AiFeedbackService.logHabitSuggestionOutcome(accepted: false);
      await AiFeedbackService.logHabitSuggestionOutcome(accepted: false);
      await AiFeedbackService.logHabitSuggestionOutcome(accepted: true);

      final summary = await AiFeedbackService.summarize();
      final priority = summary['prioritySuggestions'] as Map<String, dynamic>;
      expect(priority['total'], 3);
      expect(priority['acceptedPercent'], 67);

      final habits = summary['habitSuggestions'] as Map<String, dynamic>;
      expect(habits['total'], 3);
      expect(habits['acceptedPercent'], 33);
    });

    test('empty log returns an empty map', () async {
      final summary = await AiFeedbackService.summarize();
      expect(summary, isEmpty);
    });

    test('log is bounded and keeps the most recent entries', () async {
      for (var i = 0; i < 60; i++) {
        await AiFeedbackService.logAlarmTimeOutcome(
            accepted: i.isEven, deltaMinutes: i);
      }
      final summary = await AiFeedbackService.summarize();
      final alarm = summary['alarmTimeSuggestions'] as Map<String, dynamic>;
      expect(alarm['total'], 50); // capped, not 60
    });
  });
}
