package com.rohit.inklist

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * AlarmManager entries do not survive a device reboot. On BOOT_COMPLETED,
 * re-register alarms for every task with alarmEnabled == true and a future
 * trigger, reading task data directly from the same SharedPreferences file
 * Flutter's shared_preferences plugin owns (see TodoPrefsHelper).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val now = System.currentTimeMillis()
        val tasks = TodoPrefsHelper.readAlarmEnabledTasks(context)
        for (task in tasks) {
            val triggerAt = nextTriggerFor(task, now) ?: continue
            val requestCode = task.id.hashCode()
            AlarmSchedulerHelper.schedule(
                context, requestCode, task.id, task.title, triggerAt, task.recurrenceRule
            )
        }

        // Smart Reminders' check-in alarms don't survive reboot either.
        SmartReminderScheduler.rescheduleAll(context)
    }

    private fun nextTriggerFor(task: AlarmTaskInfo, now: Long): Long? {
        if (task.recurrenceRule == "none") {
            val cal = Calendar.getInstance().apply {
                timeInMillis = task.dueDateMillis
                set(Calendar.HOUR_OF_DAY, task.hour)
                set(Calendar.MINUTE, task.minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            return if (cal.timeInMillis > now) cal.timeInMillis else null
        }

        // Recurring: today at the alarm time, if it hasn't passed and today
        // matches the rule; otherwise the next matching day.
        val todayAtTime = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, task.hour)
            set(Calendar.MINUTE, task.minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (todayAtTime.timeInMillis > now &&
            AlarmSchedulerHelper.occursOn(task.recurrenceRule, todayAtTime)
        ) {
            return todayAtTime.timeInMillis
        }
        return AlarmSchedulerHelper.nextTriggerMillis(
            task.recurrenceRule, task.hour, task.minute, now
        )
    }
}
