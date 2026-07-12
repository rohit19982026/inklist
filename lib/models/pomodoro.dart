// Pomodoro domain models — deliberately free of package:flutter imports so
// the phase/config logic stays trivially unit-testable.

enum PomodoroPhase { work, shortBreak, longBreak }

extension PomodoroPhaseX on PomodoroPhase {
  String get label => switch (this) {
        PomodoroPhase.work => 'Focus',
        PomodoroPhase.shortBreak => 'Short break',
        PomodoroPhase.longBreak => 'Long break',
      };

  bool get isBreak => this != PomodoroPhase.work;

  String get storageKey => switch (this) {
        PomodoroPhase.work => 'work',
        PomodoroPhase.shortBreak => 'short',
        PomodoroPhase.longBreak => 'long',
      };

  static PomodoroPhase fromStorage(String? s) => switch (s) {
        'short' => PomodoroPhase.shortBreak,
        'long' => PomodoroPhase.longBreak,
        _ => PomodoroPhase.work,
      };
}

/// User-tunable durations. Free tier uses the classic 25/5/15; custom values
/// become a Pro feature once entitlement gating lands (Phase 8).
class PomodoroConfig {
  final int workMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int roundsBeforeLongBreak;

  const PomodoroConfig({
    this.workMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.roundsBeforeLongBreak = 4,
  });

  static const classic = PomodoroConfig();

  int minutesFor(PomodoroPhase phase) => switch (phase) {
        PomodoroPhase.work => workMinutes,
        PomodoroPhase.shortBreak => shortBreakMinutes,
        PomodoroPhase.longBreak => longBreakMinutes,
      };

  /// Given how many work rounds are already completed, what comes after the
  /// current work phase — a long break every [roundsBeforeLongBreak] rounds.
  PomodoroPhase breakAfter(int completedWorkRounds) =>
      (completedWorkRounds > 0 &&
              completedWorkRounds % roundsBeforeLongBreak == 0)
          ? PomodoroPhase.longBreak
          : PomodoroPhase.shortBreak;

  Map<String, dynamic> toJson() => {
        'work': workMinutes,
        'short': shortBreakMinutes,
        'long': longBreakMinutes,
        'rounds': roundsBeforeLongBreak,
      };

  factory PomodoroConfig.fromJson(Map<String, dynamic> j) => PomodoroConfig(
        workMinutes: (j['work'] as num?)?.toInt() ?? 25,
        shortBreakMinutes: (j['short'] as num?)?.toInt() ?? 5,
        longBreakMinutes: (j['long'] as num?)?.toInt() ?? 15,
        roundsBeforeLongBreak: (j['rounds'] as num?)?.toInt() ?? 4,
      );

  PomodoroConfig copyWith({
    int? workMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? roundsBeforeLongBreak,
  }) =>
      PomodoroConfig(
        workMinutes: workMinutes ?? this.workMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        roundsBeforeLongBreak:
            roundsBeforeLongBreak ?? this.roundsBeforeLongBreak,
      );
}

/// A completed focus session, logged for the "sessions today" count and
/// (Pro) focus stats/history.
class PomodoroSession {
  final DateTime completedAt;
  final int minutes;
  final String? taskTitle;

  const PomodoroSession({
    required this.completedAt,
    required this.minutes,
    this.taskTitle,
  });

  Map<String, dynamic> toJson() => {
        'at': completedAt.millisecondsSinceEpoch,
        'min': minutes,
        'task': taskTitle,
      };

  factory PomodoroSession.fromJson(Map<String, dynamic> j) => PomodoroSession(
        completedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['at'] as num?)?.toInt() ?? 0),
        minutes: (j['min'] as num?)?.toInt() ?? 0,
        taskTitle: j['task'] as String?,
      );
}
