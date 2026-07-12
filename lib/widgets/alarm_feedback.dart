import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/todo_task.dart';
import '../services/alarm_scheduler_service.dart';

/// Shared feedback when a task wanted an alarm but scheduling returned false.
/// Distinguishes the two real causes so the message is actionable and not
/// misleading:
///   - exact-alarm permission missing  → offer a one-tap fix
///   - the alarm time is already in the past (e.g. a same-day task whose
///     time has already gone by) → tell the user to pick a future time,
///     instead of blaming a permission that's actually granted.
///
/// [scheduled] is the bool returned by [AlarmSchedulerService.syncTaskAlarm].
Future<void> showAlarmSchedulingFeedback(
    BuildContext context, TodoTask task, bool scheduled) async {
  if (scheduled || !task.alarmEnabled) return;
  final canSchedule = await AlarmSchedulerService.canScheduleExactAlarms();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (!canSchedule) {
    messenger.showSnackBar(SnackBar(
      content: Text(
          'Alarm couldn\'t be scheduled — grant "Alarms & reminders" access',
          style: T.footnote(c: Colors.white)),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      action: SnackBarAction(
        label: 'FIX',
        textColor: Colors.white,
        onPressed: () => AlarmSchedulerService.requestExactAlarmPermission(),
      ),
    ));
  } else {
    messenger.showSnackBar(SnackBar(
      content: Text(
          'That time has already passed — pick a future time or date to set the alarm',
          style: T.footnote(c: Colors.white)),
      backgroundColor: AppColors.textPrimary,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ));
  }
}
