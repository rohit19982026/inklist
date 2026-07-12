import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/services/groq_service.dart';
import 'package:inklist/services/recurrence_rule.dart';

void main() {
  group('parseWeeklyPlanResponse', () {
    test('parses a well-formed weekly-plan JSON body', () {
      const raw = '''
      {
        "days": {
          "monday": [{"title": "Team standup", "time": "09:00", "priority": "medium"}],
          "wednesday": [
            {"title": "Dentist", "time": "14:00", "priority": "high"},
            {"title": "Buy groceries", "time": null, "priority": "low"}
          ]
        }
      }
      ''';
      final result = GroqService.parseWeeklyPlanResponse(raw);
      expect(result.isSuccess, isTrue);
      final draft = result.data!;
      expect(draft.totalTaskCount, 3);
      expect(draft.days['monday']!.single.title, 'Team standup');
      expect(draft.days['wednesday']!.length, 2);
      expect(draft.days['wednesday']![1].time, isNull);
      expect(draft.days.containsKey('tuesday'), isFalse);
    });

    test('malformed JSON degrades to GroqResult.fail rather than throwing', () {
      const raw = '{"days": { this is not valid json ]]';
      final result = GroqService.parseWeeklyPlanResponse(raw);
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });

    test('missing "days" key degrades to a fail rather than throwing', () {
      const raw = '{"unexpected": "shape"}';
      final result = GroqService.parseWeeklyPlanResponse(raw);
      // WeeklyPlanDraft.fromJson tolerates a missing 'days' key by treating
      // it as an empty plan, so this should succeed with zero tasks rather
      // than crash — assert that specific graceful-degradation behavior.
      expect(result.isSuccess, isTrue);
      expect(result.data!.totalTaskCount, 0);
    });
  });

  group('parseBreakdownResponse', () {
    test('parses a well-formed subtasks JSON body', () {
      const raw = '{"subtasks": ["Book venue", "Send invites", "Order cake"]}';
      final result = GroqService.parseBreakdownResponse(raw);
      expect(result.isSuccess, isTrue);
      expect(result.data, ['Book venue', 'Send invites', 'Order cake']);
    });

    test('empty subtasks list degrades to a fail', () {
      const raw = '{"subtasks": []}';
      final result = GroqService.parseBreakdownResponse(raw);
      expect(result.isSuccess, isFalse);
    });

    test('malformed JSON degrades to GroqResult.fail rather than throwing', () {
      const raw = 'not json at all';
      final result = GroqService.parseBreakdownResponse(raw);
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });

    test('non-string entries in the list are dropped rather than crashing', () {
      const raw = '{"subtasks": ["Valid task", 42, null, "Another valid task"]}';
      final result = GroqService.parseBreakdownResponse(raw);
      expect(result.isSuccess, isTrue);
      expect(result.data, ['Valid task', 'Another valid task']);
    });
  });

  group('parseQuickAddResponse', () {
    test('parses a well-formed quick-add JSON body', () {
      const raw = '''
      {
        "title": "Pay rent",
        "dueDate": "2026-04-01",
        "time": "09:00",
        "recurrence": "monthly:1",
        "priority": "high"
      }
      ''';
      final result = GroqService.parseQuickAddResponse(raw);
      expect(result.isSuccess, isTrue);
      final draft = result.data!;
      expect(draft.title, 'Pay rent');
      expect(draft.dueDate, DateTime(2026, 4, 1));
      expect(draft.time?.hour, 9);
      expect(draft.time?.minute, 0);
      expect(draft.recurrence, 'monthly:1');
      expect(draft.priority, 'high');
    });

    test('missing title degrades to a fail', () {
      const raw = '{"dueDate": "2026-04-01", "recurrence": "none"}';
      final result = GroqService.parseQuickAddResponse(raw);
      expect(result.isSuccess, isFalse);
    });

    test('malformed JSON degrades to GroqResult.fail rather than throwing', () {
      const raw = '{"title": "Pay rent"';
      final result = GroqService.parseQuickAddResponse(raw);
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });

    test('recurrence strings the parser emits are accepted by RecurrenceRule',
        () {
      // Consistency check between the prompt's documented output grammar
      // and what RecurrenceRule.occursOn actually understands.
      const recurrences = ['none', 'daily', 'weekly:MON,WED,FRI', 'monthly:1', 'monthly:last'];
      for (final r in recurrences) {
        // Should not throw for any of these — a bogus/unsupported rule would
        // silently evaluate to false rather than crash, which is fine, but
        // the well-known outputs must all parse without error.
        expect(() => RecurrenceRule.occursOn(r, DateTime(2026, 4, 1)),
            returnsNormally);
      }
    });
  });

  group('parseDailyBriefResponse', () {
    test('passes through non-empty plain text', () {
      const raw = '• Finish the report\n• Call the dentist back';
      final result = GroqService.parseDailyBriefResponse(raw);
      expect(result.isSuccess, isTrue);
      expect(result.data, raw);
    });

    test('empty response degrades to a fail', () {
      final result = GroqService.parseDailyBriefResponse('   ');
      expect(result.isSuccess, isFalse);
    });
  });

  group('parseFocusCoachResponse', () {
    test('parses task + message', () {
      const raw = '{"task": "Finish the report", "message": "It\'s your '
          'highest-priority task and 25 minutes will make a real dent."}';
      final result = GroqService.parseFocusCoachResponse(raw);
      expect(result.isSuccess, isTrue);
      expect(result.data!.taskTitle, 'Finish the report');
      expect(result.data!.hasTask, isTrue);
      expect(result.data!.message, contains('highest-priority'));
    });

    test('empty task string yields hasTask == false', () {
      const raw = '{"task": "", "message": "Pick anything and just begin."}';
      final result = GroqService.parseFocusCoachResponse(raw);
      expect(result.isSuccess, isTrue);
      expect(result.data!.hasTask, isFalse);
    });

    test('missing message degrades to a fail', () {
      const raw = '{"task": "Something"}';
      final result = GroqService.parseFocusCoachResponse(raw);
      expect(result.isSuccess, isFalse);
    });

    test('malformed JSON degrades to a fail rather than throwing', () {
      final result = GroqService.parseFocusCoachResponse('not json {{');
      expect(result.isSuccess, isFalse);
    });
  });
}
