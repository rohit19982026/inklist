package com.rohit.inklist

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Fired by AlarmManager at one of the 3-4 daily "smart reminder" check-in
 * times. Re-arms tomorrow's occurrence for this slot immediately — before
 * any downstream work — so a slow or failed check-in job can never prevent
 * the next day's check-in from being scheduled — then starts
 * SmartReminderService to run the actual Groq-backed decision.
 */
class SmartReminderReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_SLOT_INDEX = "slot_index"
        const val EXTRA_HOUR = "hour"
        const val EXTRA_MINUTE = "minute"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val slotIndex = intent.getIntExtra(EXTRA_SLOT_INDEX, -1)
        val hour = intent.getIntExtra(EXTRA_HOUR, 9)
        val minute = intent.getIntExtra(EXTRA_MINUTE, 0)
        if (slotIndex < 0) return

        val next = AlarmSchedulerHelper.nextTriggerMillis(
            "daily", hour, minute, System.currentTimeMillis()
        )
        SmartReminderScheduler.armSlot(context, slotIndex, next, hour, minute)

        val serviceIntent = Intent(context, SmartReminderService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
