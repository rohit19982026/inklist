package com.rohit.inklist

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager

/**
 * Fired by AlarmManager at the scheduled time. Wakes the device, starts the
 * looping ringing service + full-screen activity, and re-arms the next
 * occurrence for recurring tasks.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra(AlarmSchedulerHelper.EXTRA_TASK_ID) ?: return
        val title = intent.getStringExtra(AlarmSchedulerHelper.EXTRA_TITLE) ?: "Task"
        val recurrenceRule = intent.getStringExtra(AlarmSchedulerHelper.EXTRA_RECURRENCE) ?: "none"
        val hour = intent.getIntExtra(AlarmSchedulerHelper.EXTRA_HOUR, 9)
        val minute = intent.getIntExtra(AlarmSchedulerHelper.EXTRA_MINUTE, 0)

        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "inklist:alarm_wake"
        )
        wakeLock.acquire(10_000L)
        try {
            val serviceIntent = Intent(context, AlarmRingingService::class.java).apply {
                putExtra(AlarmSchedulerHelper.EXTRA_TASK_ID, taskId)
                putExtra(AlarmSchedulerHelper.EXTRA_TITLE, title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            // Re-arm the next occurrence unconditionally on firing — this is
            // independent of whether the user later snoozes or dismisses,
            // which use a distinct request code (see SNOOZE_OFFSET).
            if (recurrenceRule != "none") {
                val requestCode = taskId.hashCode()
                val next = AlarmSchedulerHelper.nextTriggerMillis(
                    recurrenceRule, hour, minute, System.currentTimeMillis()
                )
                AlarmSchedulerHelper.schedule(
                    context, requestCode, taskId, title, next, recurrenceRule
                )
            }
        } finally {
            wakeLock.release()
        }
    }
}
