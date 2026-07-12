import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/models/pomodoro.dart';
import 'package:inklist/services/pomodoro_service.dart';

void main() {
  group('PomodoroConfig', () {
    const c = PomodoroConfig.classic;

    test('classic defaults are 25/5/15 with a long break every 4 rounds', () {
      expect(c.workMinutes, 25);
      expect(c.shortBreakMinutes, 5);
      expect(c.longBreakMinutes, 15);
      expect(c.roundsBeforeLongBreak, 4);
    });

    test('minutesFor returns the right duration per phase', () {
      expect(c.minutesFor(PomodoroPhase.work), 25);
      expect(c.minutesFor(PomodoroPhase.shortBreak), 5);
      expect(c.minutesFor(PomodoroPhase.longBreak), 15);
    });

    test('breakAfter gives a long break only on the Nth completed round', () {
      // Rounds 1-3 → short break, round 4 → long break, round 5-7 → short...
      expect(c.breakAfter(1), PomodoroPhase.shortBreak);
      expect(c.breakAfter(3), PomodoroPhase.shortBreak);
      expect(c.breakAfter(4), PomodoroPhase.longBreak);
      expect(c.breakAfter(8), PomodoroPhase.longBreak);
      expect(c.breakAfter(5), PomodoroPhase.shortBreak);
    });

    test('breakAfter with zero completed rounds is a short break', () {
      expect(c.breakAfter(0), PomodoroPhase.shortBreak);
    });

    test('custom config round-trips through JSON', () {
      const custom = PomodoroConfig(
        workMinutes: 50,
        shortBreakMinutes: 10,
        longBreakMinutes: 30,
        roundsBeforeLongBreak: 3,
      );
      final restored = PomodoroConfig.fromJson(custom.toJson());
      expect(restored.workMinutes, 50);
      expect(restored.shortBreakMinutes, 10);
      expect(restored.longBreakMinutes, 30);
      expect(restored.roundsBeforeLongBreak, 3);
    });

    test('fromJson tolerates a malformed/empty map', () {
      final restored = PomodoroConfig.fromJson(const {});
      expect(restored.workMinutes, 25);
      expect(restored.roundsBeforeLongBreak, 4);
    });
  });

  group('PomodoroPhase storage', () {
    test('storageKey and fromStorage round-trip', () {
      for (final phase in PomodoroPhase.values) {
        expect(PomodoroPhaseX.fromStorage(phase.storageKey), phase);
      }
    });

    test('fromStorage defaults unknown values to work', () {
      expect(PomodoroPhaseX.fromStorage(null), PomodoroPhase.work);
      expect(PomodoroPhaseX.fromStorage('garbage'), PomodoroPhase.work);
    });

    test('isBreak is false only for work', () {
      expect(PomodoroPhase.work.isBreak, isFalse);
      expect(PomodoroPhase.shortBreak.isBreak, isTrue);
      expect(PomodoroPhase.longBreak.isBreak, isTrue);
    });
  });

  group('PomodoroSession', () {
    test('round-trips through JSON', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final s = PomodoroSession(
          completedAt: now, minutes: 25, taskTitle: 'Write report');
      final r = PomodoroSession.fromJson(s.toJson());
      expect(r.completedAt, now);
      expect(r.minutes, 25);
      expect(r.taskTitle, 'Write report');
    });

    test('tolerates a null task title', () {
      final s = PomodoroSession(
          completedAt: DateTime.now(), minutes: 25, taskTitle: null);
      final r = PomodoroSession.fromJson(s.toJson());
      expect(r.taskTitle, isNull);
    });
  });

  group('ActiveTimer', () {
    test('running snapshot round-trips', () {
      const a = ActiveTimer(
        phase: PomodoroPhase.work,
        running: true,
        endsAtMillis: 1700000000000,
        remainingSeconds: 0,
        completedWorkRounds: 2,
        taskTitle: 'Focus task',
      );
      final r = ActiveTimer.fromJson(a.toJson());
      expect(r.phase, PomodoroPhase.work);
      expect(r.running, isTrue);
      expect(r.endsAtMillis, 1700000000000);
      expect(r.completedWorkRounds, 2);
      expect(r.taskTitle, 'Focus task');
    });

    test('paused snapshot preserves remaining seconds', () {
      const a = ActiveTimer(
        phase: PomodoroPhase.shortBreak,
        running: false,
        endsAtMillis: 0,
        remainingSeconds: 184,
        completedWorkRounds: 1,
      );
      final r = ActiveTimer.fromJson(a.toJson());
      expect(r.running, isFalse);
      expect(r.remainingSeconds, 184);
      expect(r.phase, PomodoroPhase.shortBreak);
    });
  });
}
