import 'package:flutter/services.dart';
import '../models/todo_task.dart';
import 'recurrence_rule.dart';

/// Thin MethodChannel wrapper around the native alarm-scheduling methods
/// added to MainActivity.kt. Every call is best-effort — a failure here
/// (e.g. platform channel unavailable) must never block task CRUD, since
/// alarms are an enhancement on top of a to-do list that already works
/// without them.
class AlarmSchedulerService {
  static const _methods = MethodChannel('com.rohit.inklist/methods');

  static Future<bool> canScheduleExactAlarms() async {
    try {
      return await _methods.invokeMethod<bool>('canScheduleExactAlarms') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestExactAlarmPermission() async {
    try {
      await _methods.invokeMethod('requestExactAlarmPermission');
    } catch (_) {}
  }

  static Future<void> requestDndAccess() async {
    try {
      await _methods.invokeMethod('requestDndAccess');
    } catch (_) {}
  }

  /// Standard Android battery optimization (Doze/App Standby) is separate
  /// from every other permission here — many OEMs (MIUI, ColorOS, One UI...)
  /// still throttle or kill background alarm work for apps under it, even
  /// with notifications, exact alarms, and full-screen intent all granted.
  /// Defaults to true (nothing to fix) if the platform call fails.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _methods.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _methods.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// Android 14+ only: a separate toggle from POST_NOTIFICATIONS that gates
  /// whether the alarm's full-screen ringing UI is allowed to auto-launch.
  /// Defaults to true (nothing to fix) on older Android or if the platform
  /// call fails, so this never blocks the rest of Settings from rendering.
  static Future<bool> canUseFullScreenIntent() async {
    try {
      return await _methods.invokeMethod<bool>('canUseFullScreenIntent') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestFullScreenIntentPermission() async {
    try {
      await _methods.invokeMethod('requestFullScreenIntentPermission');
    } catch (_) {}
  }

  /// Schedules (or re-schedules) the next occurrence of [task]'s alarm.
  /// No-ops if the task has no alarm enabled/time, or no future occurrence
  /// exists within the next year.
  static Future<bool> scheduleTaskAlarm(TodoTask task) async {
    if (!task.alarmEnabled || task.alarmTime == null) return false;
    final trigger = _nextTriggerMillis(task);
    if (trigger == null) return false;
    try {
      return await _methods.invokeMethod<bool>('scheduleTaskAlarm', {
            'id': _requestCode(task.id),
            'taskId': task.id,
            'title': task.title,
            'triggerAtMillis': trigger,
            'recurrenceRule': task.recurrenceRule,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cancelTaskAlarm(String taskId) async {
    try {
      await _methods
          .invokeMethod('cancelTaskAlarm', {'id': _requestCode(taskId)});
    } catch (_) {}
  }

  // ── Pomodoro completion chime ──────────────────────────────────────────
  // Reuses the proven task-alarm native path (no new Kotlin) so a focus/break
  // phase still notifies the user when it ends while the app is backgrounded.
  // Uses a fixed request code so a new phase overwrites the previous alarm.
  // The screen cancels this the moment a phase completes in the foreground,
  // where it plays a soft in-app chime instead.
  static const _pomodoroRequestCode = 990001;

  static Future<void> schedulePomodoroChime(
      DateTime endsAt, String label) async {
    if (!endsAt.isAfter(DateTime.now())) return;
    try {
      await _methods.invokeMethod('scheduleTaskAlarm', {
        'id': _pomodoroRequestCode,
        'taskId': 'pomodoro',
        'title': label,
        'triggerAtMillis': endsAt.millisecondsSinceEpoch,
        'recurrenceRule': 'none',
      });
    } catch (_) {}
  }

  static Future<void> cancelPomodoroChime() async {
    try {
      await _methods
          .invokeMethod('cancelTaskAlarm', {'id': _pomodoroRequestCode});
    } catch (_) {}
  }

  /// Cancels any existing alarm for [task], then reschedules it if enabled —
  /// covers create, edit (including toggling the alarm off), and delete via
  /// the same call site pattern. Returns false only when the task wants an
  /// alarm but scheduling it actually failed (e.g. missing exact-alarm
  /// permission) — callers should surface that to the user instead of
  /// letting it fail silently.
  static Future<bool> syncTaskAlarm(TodoTask task) async {
    await cancelTaskAlarm(task.id);
    if (!task.alarmEnabled) return true;
    return scheduleTaskAlarm(task);
  }

  /// Must match Kotlin/Java's `String.hashCode()` exactly — NOT Dart's
  /// built-in `String.hashCode`, which uses a different algorithm. The
  /// native side recomputes this same requestCode independently in two
  /// places Dart can't call into directly: AlarmReceiver re-arming a
  /// recurring task's next occurrence, and BootReceiver rescheduling
  /// everything after a reboot. If the two algorithms disagree, a later
  /// `cancelTaskAlarm`/`scheduleTaskAlarm` from Dart targets a different
  /// PendingIntent than the one actually armed — the real alarm survives
  /// being "turned off", or a duplicate gets scheduled alongside it.
  static int _requestCode(String taskId) => javaStringHashCode(taskId);

  static int? _nextTriggerMillis(TodoTask task) {
    final time = task.alarmTime;
    if (time == null) return null;
    final now = DateTime.now();

    if (!task.isRecurring) {
      final dt = DateTime(task.dueDate.year, task.dueDate.month,
          task.dueDate.day, time.hour, time.minute);
      return dt.isAfter(now) ? dt.millisecondsSinceEpoch : null;
    }

    var day = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < 370; i++) {
      final dt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      if (dt.isAfter(now) && RecurrenceRule.occursOn(task.recurrenceRule, day)) {
        return dt.millisecondsSinceEpoch;
      }
      day = day.add(const Duration(days: 1));
    }
    return null;
  }
}

/// A port of Java/Kotlin's `String.hashCode()` — `s[0]*31^(n-1) + ... +
/// s[n-1]`, over UTF-16 code units, wrapped to a 32-bit signed int. Dart's
/// own `String.hashCode` is a different, incompatible algorithm; this exists
/// so a taskId hashes to the same requestCode on both sides of the platform
/// channel. Masking after every step keeps the running value within 32 bits
/// throughout, matching Java's per-operation integer overflow exactly.
int javaStringHashCode(String s) {
  var hash = 0;
  for (final unit in s.codeUnits) {
    hash = (31 * hash + unit) & 0xFFFFFFFF;
  }
  return hash >= 0x80000000 ? hash - 0x100000000 : hash;
}
