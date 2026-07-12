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

  static int _requestCode(String taskId) => taskId.hashCode;

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
