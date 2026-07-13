package com.rohit.inklist

import android.content.Context
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
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

/** One task occurring today, for the home-screen widget. */
data class WidgetTaskInfo(
    val title: String,
    val done: Boolean,
    val priority: String,
    val hasTime: Boolean,
    val hour: Int,
    val minute: Int,
)

/**
 * Reads/writes the same 'flutter.todo_tasks_v1' JSON blob that Flutter's
 * shared_preferences plugin owns (Flutter always prefixes keys with
 * "flutter." in the underlying native SharedPreferences file). This lets
 * native alarm/widget code, which runs without a warm Flutter engine, mark a
 * task done, reschedule alarms, or read today's tasks directly.
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

    /** The task's priority ("low"/"medium"/"high"), or "medium" if the task
     * can't be found — used by SmartSnoozeHelper to pick a base snooze
     * length without needing priority threaded through the alarm intent. */
    fun readPriority(context: Context, taskId: String): String {
        val tasks = readTasks(context)
        for (i in 0 until tasks.length()) {
            val obj = tasks.optJSONObject(i) ?: continue
            if (obj.optString("id") == taskId) return obj.optString("priority", "medium")
        }
        return "medium"
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

    /**
     * Every task occurring today (recurring rule matches today, or a one-off
     * task due today), with its completion state for today — mirrors
     * TodoService.tasksForDay()/isCompletedOn() on the Dart side. Used by the
     * home-screen widget, which has no Flutter engine to ask.
     */
    fun readTodayTasks(context: Context): List<WidgetTaskInfo> {
        val tasks = readTasks(context)
        val todayCal = Calendar.getInstance()
        val todayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(todayCal.time)
        val out = mutableListOf<WidgetTaskInfo>()
        for (i in 0 until tasks.length()) {
            val obj = tasks.optJSONObject(i) ?: continue
            val recurrenceRule = obj.optString("recurrenceRule", "none")
            val title = obj.optString("title", "Task")
            val priority = obj.optString("priority", "medium")
            val alarmTime = obj.optJSONObject("alarmTime")
            val hour = alarmTime?.optInt("h", -1) ?: -1
            val minute = alarmTime?.optInt("m", 0) ?: 0
            val hasTime = alarmTime != null

            if (recurrenceRule != "none") {
                if (!AlarmSchedulerHelper.occursOn(recurrenceRule, todayCal)) continue
                val completedDates = obj.optJSONArray("completedDates")
                val done = completedDates != null &&
                    (0 until completedDates.length()).any { completedDates.optString(it) == todayKey }
                out.add(WidgetTaskInfo(title, done, priority, hasTime, hour, minute))
            } else {
                val dueDateMillis = obj.optLong("dueDate", -1L)
                if (dueDateMillis < 0) continue
                val dueCal = Calendar.getInstance().apply { timeInMillis = dueDateMillis }
                val sameDay = dueCal.get(Calendar.YEAR) == todayCal.get(Calendar.YEAR) &&
                    dueCal.get(Calendar.DAY_OF_YEAR) == todayCal.get(Calendar.DAY_OF_YEAR)
                if (!sameDay) continue
                val done = obj.optBoolean("isCompleted", false)
                out.add(WidgetTaskInfo(title, done, priority, hasTime, hour, minute))
            }
        }
        return out
    }
}
