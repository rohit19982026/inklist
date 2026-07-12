package com.rohit.inklist

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * Arms/cancels the 3-4 daily "smart reminder" check-in alarms. These are a
 * separate concern from task alarms (AlarmReceiver) and use their own
 * dedicated receiver (SmartReminderReceiver) and their own reserved request
 * codes, so the two never collide or get confused with each other.
 */
object SmartReminderScheduler {
    // Reserved request codes for up to 4 check-in slots. Real task alarms
    // use taskId.hashCode() (which CAN be negative — String.hashCode() is a
    // signed 32-bit value with no sign masking) and snoozes use
    // hashCode() + SNOOZE_OFFSET, so these tiny fixed negative sentinels are
    // not theoretically collision-proof. Task IDs here are timestamp-derived
    // numeric strings, not adversarial input, so this is an accepted
    // tradeoff rather than a real design risk.
    private val REQUEST_CODES = intArrayOf(-100, -101, -102, -103)
    const val MAX_SLOTS = 4

    private val DEFAULT_TIMES = listOf(9 to 0, 13 to 0, 18 to 0, 21 to 0)

    /** Cancels all 4 slots, then arms one per (hour, minute) in [times]
     * (up to MAX_SLOTS). Returns true only if every slot armed successfully. */
    fun scheduleAll(context: Context, times: List<Pair<Int, Int>>): Boolean {
        cancelAll(context)
        var allOk = true
        for (i in times.indices) {
            if (i >= MAX_SLOTS) break
            val (hour, minute) = times[i]
            val trigger = nextOccurrenceAt(hour, minute)
            if (!armSlot(context, i, trigger, hour, minute)) allOk = false
        }
        return allOk
    }

    fun cancelAll(context: Context) {
        for (code in REQUEST_CODES) cancelSlot(context, code)
    }

    private fun cancelSlot(context: Context, requestCode: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, SmartReminderReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        am.cancel(pending)
        pending.cancel()
    }

    /** Arms (or re-arms) a single check-in slot. Returns false, never
     * throws, if exact alarms aren't permitted or the OS rejects it. */
    fun armSlot(
        context: Context,
        slotIndex: Int,
        triggerAtMillis: Long,
        hour: Int,
        minute: Int
    ): Boolean {
        if (slotIndex !in REQUEST_CODES.indices) return false
        if (!AlarmSchedulerHelper.canScheduleExact(context)) return false

        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, SmartReminderReceiver::class.java).apply {
            putExtra(SmartReminderReceiver.EXTRA_SLOT_INDEX, slotIndex)
            putExtra(SmartReminderReceiver.EXTRA_HOUR, hour)
            putExtra(SmartReminderReceiver.EXTRA_MINUTE, minute)
        }
        val pending = PendingIntent.getBroadcast(
            context, REQUEST_CODES[slotIndex], intent,
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
            false
        }
    }

    private fun nextOccurrenceAt(hour: Int, minute: Int): Long {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis <= System.currentTimeMillis()) {
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        return cal.timeInMillis
    }

    /**
     * Reads enabled + times directly from the same FlutterSharedPreferences
     * file Dart writes to (same "flutter." prefix technique TodoPrefsHelper
     * already uses) and re-arms all slots, or cancels all if disabled.
     * Called by BootReceiver since AlarmManager entries don't survive
     * reboot, and by MainActivity's MethodChannel handlers for Settings
     * edits.
     */
    fun rescheduleAll(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("flutter.smart_reminders_enabled", false)
        if (!enabled) {
            cancelAll(context)
            return
        }
        val raw = prefs.getString("flutter.smart_reminder_times", null)
        scheduleAll(context, parseTimes(raw))
    }

    private fun parseTimes(raw: String?): List<Pair<Int, Int>> {
        if (raw == null) return DEFAULT_TIMES
        return try {
            val arr = org.json.JSONArray(raw)
            val out = mutableListOf<Pair<Int, Int>>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                out.add(obj.optInt("hour", 9) to obj.optInt("minute", 0))
            }
            if (out.isEmpty()) DEFAULT_TIMES else out
        } catch (e: Exception) {
            DEFAULT_TIMES
        }
    }
}
