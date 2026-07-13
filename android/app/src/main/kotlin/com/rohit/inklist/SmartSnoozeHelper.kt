package com.rohit.inklist

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Adaptive snooze length instead of a fixed 10 minutes — computed entirely
 * offline from data already on the device:
 *  - Base length depends on the task's priority, so a high-priority item
 *    doesn't drift far from when it was meant to happen.
 *  - Each additional snooze on the same task *today* halves the remaining
 *    length (floor 2 min) — repeatedly punting the same reminder gets
 *    progressively less comfortable instead of silently repeating the same
 *    gap forever.
 * Snooze counts live under their own key (not the "flutter."-prefixed ones
 * Dart's shared_preferences plugin owns), keyed by taskId + today's date, so
 * a recurring task's count resets automatically once the date rolls over.
 */
object SmartSnoozeHelper {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_PREFIX = "native_snooze_count_"
    private const val MIN_SNOOZE_MINUTES = 2

    private fun baseMinutesForPriority(priority: String): Int = when (priority) {
        "high" -> 5
        "low" -> 15
        else -> 10
    }

    private fun todayKey(taskId: String): String {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        return "$KEY_PREFIX${taskId}_$today"
    }

    /** Records this snooze press and returns how many minutes to snooze for. */
    fun nextSnoozeMinutes(context: Context, taskId: String, priority: String): Int {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val key = todayKey(taskId)
        val countSoFar = prefs.getInt(key, 0)
        prefs.edit().putInt(key, countSoFar + 1).apply()

        var minutes = baseMinutesForPriority(priority)
        repeat(countSoFar) { minutes = (minutes / 2).coerceAtLeast(MIN_SNOOZE_MINUTES) }
        return minutes
    }
}
