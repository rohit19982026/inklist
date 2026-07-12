package com.rohit.inklist

import android.content.Context
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class AlarmTaskInfo(
    val id: String,
    val title: String,
    val dueDateMillis: Long,
    val hour: Int,
    val minute: Int,
    val recurrenceRule: String,
)

/**
 * Reads/writes the same 'flutter.todo_tasks_v1' JSON blob that Flutter's
 * shared_preferences plugin owns (Flutter always prefixes keys with
 * "flutter." in the underlying native SharedPreferences file — the same
 * technique MainActivity.updateWidget() already relies on for the home
 * screen widget). This lets native alarm code, which runs without a warm
 * Flutter engine, mark a task done or reschedule alarms directly.
 */
object TodoPrefsHelper {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val TASKS_KEY = "flutter.todo_tasks_v1"

    fun readTasks(context: Context): JSONArray {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(TASKS_KEY, null) ?: return JSONArray()
        return try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
    }

    private fun writeTasks(context: Context, tasks: JSONArray) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(TASKS_KEY, tasks.toString()).apply()
    }

    /** Marks today's occurrence done for a recurring task, or isCompleted for
     * a one-off task — mirrors TodoService.toggleOccurrence()'s "mark done"
     * half, but as a direct write since there's no Dart runtime here. */
    fun markCompletedToday(context: Context, taskId: String) {
        val tasks = readTasks(context)
        val todayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        for (i in 0 until tasks.length()) {
            val obj = tasks.optJSONObject(i) ?: continue
            if (obj.optString("id") != taskId) continue
            val recurrenceRule = obj.optString("recurrenceRule", "none")
            if (recurrenceRule != "none") {
                val dates = obj.optJSONArray("completedDates") ?: JSONArray()
                var alreadyThere = false
                for (j in 0 until dates.length()) {
                    if (dates.optString(j) == todayKey) { alreadyThere = true; break }
                }
                if (!alreadyThere) dates.put(todayKey)
                obj.put("completedDates", dates)
            } else {
                obj.put("isCompleted", true)
                obj.put("completedAt", System.currentTimeMillis())
            }
            break
        }
        writeTasks(context, tasks)
    }

    /** Every task with alarmEnabled == true and a specific alarm time set —
     * used by BootReceiver to re-register alarms after a reboot. */
    fun readAlarmEnabledTasks(context: Context): List<AlarmTaskInfo> {
        val tasks = readTasks(context)
        val out = mutableListOf<AlarmTaskInfo>()
        for (i in 0 until tasks.length()) {
            val obj = tasks.optJSONObject(i) ?: continue
            if (!obj.optBoolean("alarmEnabled", false)) continue
            val alarmTime = obj.optJSONObject("alarmTime") ?: continue
            val dueDateMillis = obj.optLong("dueDate", -1L)
            if (dueDateMillis < 0) continue
            out.add(
                AlarmTaskInfo(
                    id = obj.optString("id"),
                    title = obj.optString("title", "Task"),
                    dueDateMillis = dueDateMillis,
                    hour = alarmTime.optInt("h", 9),
                    minute = alarmTime.optInt("m", 0),
                    recurrenceRule = obj.optString("recurrenceRule", "none"),
                )
            )
        }
        return out
    }
}
