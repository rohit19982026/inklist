import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo_task.dart';

/// Dart wrapper around the native "check in 3-4x/day, decide by itself
/// whether to notify or ring an alarm" pipeline. Mirrors
/// AlarmSchedulerService's style: a thin MethodChannel wrapper plus the
/// SharedPreferences state the native side also reads directly.
class SmartReminderService {
  static const _methods = MethodChannel('com.rohit.inklist/methods');
  static const _kEnabled = 'smart_reminders_enabled';
  static const _kTimes = 'smart_reminder_times';

  static const defaultTimes = <TimeOfDayMs>[
    TimeOfDayMs(hour: 9, minute: 0),
    TimeOfDayMs(hour: 13, minute: 0),
    TimeOfDayMs(hour: 18, minute: 0),
    TimeOfDayMs(hour: 21, minute: 0),
  ];

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, value);
  }

  static Future<List<TimeOfDayMs>> getCheckInTimes() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kTimes);
    if (raw == null) return defaultTimes;
    try {
      final list = jsonDecode(raw) as List;
      final times = list
          .map((e) => TimeOfDayMs(
                hour: (e as Map<String, dynamic>)['hour'] as int? ?? 9,
                minute: e['minute'] as int? ?? 0,
              ))
          .toList();
      return times.isEmpty ? defaultTimes : times;
    } catch (_) {
      return defaultTimes;
    }
  }

  static Future<void> setCheckInTimes(List<TimeOfDayMs> times) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kTimes,
      jsonEncode(times.map((t) => {'hour': t.hour, 'minute': t.minute}).toList()),
    );
  }

  /// Reads current enabled+times state and re-syncs the native alarm
  /// schedule accordingly — cancel-then-reschedule semantics, same pattern
  /// as AlarmSchedulerService.syncTaskAlarm. Safe to call at every app
  /// startup: covers reinstalls and "permission granted after being
  /// denied" recovery, not just Settings edits.
  static Future<void> syncSchedule() async {
    try {
      await _methods.invokeMethod('cancelSmartReminders');
      if (await isEnabled()) {
        final times = await getCheckInTimes();
        await _methods.invokeMethod('scheduleSmartReminders', {
          'times': times.map((t) => {'hour': t.hour, 'minute': t.minute}).toList(),
        });
      }
    } catch (_) {
      // Native methods may not exist yet on a stale build, or the platform
      // channel may be unavailable — this is a best-effort background sync,
      // never something that should crash app startup.
    }
  }
}
