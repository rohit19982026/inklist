package com.rohit.inklist

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * Shared AlarmManager scheduling logic used by MainActivity (initial
 * schedule from Dart), AlarmReceiver (re-arming the next occurrence of a
 * recurring task) and BootReceiver (rescheduling everything after reboot).
 */
object AlarmSchedulerHelper {
    const val EXTRA_TASK_ID = "task_id"
    const val EXTRA_TITLE = "title"
    const val EXTRA_RECURRENCE = "recurrence_rule"
    const val EXTRA_HOUR = "alarm_hour"
    const val EXTRA_MINUTE = "alarm_minute"

    // Snooze alarms use a distinct request code so they never clobber the
    // already-armed next occurrence of a recurring task's regular alarm.
    const val SNOOZE_OFFSET = 1_000_000

    /**
     * Returns true only if the alarm was actually registered with the OS.
     * On API 31+, scheduling an exact alarm without the user having granted
     * "Alarms & reminders" throws a SecurityException — that permission is a
     * manual Settings trip, not a normal runtime dialog, so silently
     * swallowing the exception (the old behavior) meant the task looked
     * saved with its alarm "on" while nothing was ever scheduled.
     */
    fun schedule(
        context: Context,
        requestCode: Int,
        taskId: String,
        title: String,
        triggerAtMillis: Long,
        recurrenceRule: String
    ): Boolean {
        if (!canScheduleExact(context)) return false

        val cal = Calendar.getInstance().apply { timeInMillis = triggerAtMillis }
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val minute = cal.get(Calendar.MINUTE)

        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_RECURRENCE, recurrenceRule)
            putExtra(EXTRA_HOUR, hour)
            putExtra(EXTRA_MINUTE, minute)
        }
        val pending = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending)
            }
            true
        } catch (e: SecurityException) {
            false
        } catch (e: IllegalStateException) {
            // Some OEMs (notably Xiaomi/MIUI) throw here under aggressive
            // battery restrictions even with the permission granted.
            false
        }
    }

    fun cancel(context: Context, requestCode: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        am.cancel(pending)
        pending.cancel()
    }

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return am.canScheduleExactAlarms()
    }

    /**
     * Next occurrence strictly after [fromMillis] at [hour]:[minute], matching
     * [recurrenceRule]. Mirrors the Dart RecurrenceRule grammar: 'daily',
     * 'weekly:MON,WED,FRI', 'monthly:N', 'monthly:last'. This duplication is
     * unavoidable — AlarmReceiver/BootReceiver run natively without a warm
     * Flutter engine to call back into.
     */
    fun nextTriggerMillis(recurrenceRule: String, hour: Int, minute: Int, fromMillis: Long): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = fromMillis
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        cal.add(Calendar.DAY_OF_YEAR, 1) // always advance at least one day
        for (i in 0 until 370) {
            if (occursOn(recurrenceRule, cal)) return cal.timeInMillis
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        return fromMillis
    }

    fun occursOn(recurrenceRule: String, cal: Calendar): Boolean {
        return when {
            recurrenceRule == "daily" -> true
            recurrenceRule.startsWith("weekly:") -> {
                val codes = recurrenceRule.substring(7).split(",")
                codes.contains(weekdayCode(cal.get(Calendar.DAY_OF_WEEK)))
            }
            recurrenceRule.startsWith("monthly:") -> {
                val spec = recurrenceRule.substring(8)
                if (spec == "last") isLastDayOfMonth(cal)
                else spec.toIntOrNull() == cal.get(Calendar.DAY_OF_MONTH)
            }
            else -> false
        }
    }

    private fun isLastDayOfMonth(cal: Calendar): Boolean {
        val tmp = cal.clone() as Calendar
        tmp.add(Calendar.DAY_OF_MONTH, 1)
        return tmp.get(Calendar.MONTH) != cal.get(Calendar.MONTH)
    }

    private fun weekdayCode(calendarWeekday: Int): String =
        arrayOf("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT")[calendarWeekday - 1]
}
