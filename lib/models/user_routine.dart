import 'todo_task.dart'; // TimeOfDayMs

/// The user's own daily rhythm — when they wake, sleep, and typically work
/// — entered once in Settings so alarm-time suggestions (AI and the local
/// fallback) stop guessing generic defaults and actually respect it. Every
/// field is optional and defaults to null (unset): suggestion logic falls
/// back to its existing generic behavior until the user fills these in.
class UserRoutine {
  final TimeOfDayMs? wakeTime;
  final TimeOfDayMs? sleepTime;
  final TimeOfDayMs? workStart;
  final TimeOfDayMs? workEnd;

  const UserRoutine({
    this.wakeTime,
    this.sleepTime,
    this.workStart,
    this.workEnd,
  });

  bool get isEmpty =>
      wakeTime == null && sleepTime == null && workStart == null && workEnd == null;

  static String _hhmm(TimeOfDayMs t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Formatted for GroqService prompts — only includes fields the user has
  /// actually set, as "HH:MM" strings.
  Map<String, dynamic> toPromptContext() => {
        if (wakeTime != null) 'wakeTime': _hhmm(wakeTime!),
        if (sleepTime != null) 'sleepTime': _hhmm(sleepTime!),
        if (workStart != null) 'workStart': _hhmm(workStart!),
        if (workEnd != null) 'workEnd': _hhmm(workEnd!),
      };

  UserRoutine copyWith({
    TimeOfDayMs? wakeTime,
    TimeOfDayMs? sleepTime,
    TimeOfDayMs? workStart,
    TimeOfDayMs? workEnd,
    bool clearWakeTime = false,
    bool clearSleepTime = false,
    bool clearWorkStart = false,
    bool clearWorkEnd = false,
  }) =>
      UserRoutine(
        wakeTime: clearWakeTime ? null : (wakeTime ?? this.wakeTime),
        sleepTime: clearSleepTime ? null : (sleepTime ?? this.sleepTime),
        workStart: clearWorkStart ? null : (workStart ?? this.workStart),
        workEnd: clearWorkEnd ? null : (workEnd ?? this.workEnd),
      );

  Map<String, dynamic> toJson() => {
        if (wakeTime != null) 'wake': wakeTime!.toJson(),
        if (sleepTime != null) 'sleep': sleepTime!.toJson(),
        if (workStart != null) 'workStart': workStart!.toJson(),
        if (workEnd != null) 'workEnd': workEnd!.toJson(),
      };

  factory UserRoutine.fromJson(Map<String, dynamic> j) => UserRoutine(
        wakeTime: j['wake'] != null
            ? TimeOfDayMs.fromJson(j['wake'] as Map<String, dynamic>)
            : null,
        sleepTime: j['sleep'] != null
            ? TimeOfDayMs.fromJson(j['sleep'] as Map<String, dynamic>)
            : null,
        workStart: j['workStart'] != null
            ? TimeOfDayMs.fromJson(j['workStart'] as Map<String, dynamic>)
            : null,
        workEnd: j['workEnd'] != null
            ? TimeOfDayMs.fromJson(j['workEnd'] as Map<String, dynamic>)
            : null,
      );
}
