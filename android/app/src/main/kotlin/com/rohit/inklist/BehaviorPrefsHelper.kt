package com.rohit.inklist

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

data class NativeHabitInfo(
    val title: String,
    val completedDates: Set<String>,
)

data class NativePomodoroSession(
    val completedAtMillis: Long,
    val minutes: Int,
    val taskTitle: String?,
)

private data class Occurrence(val weekday: Int, val priority: String, val done: Boolean)

/**
 * Reads the same 'flutter.habits_v1' and 'flutter.pomodoro_sessions_v1' JSON
 * blobs Flutter's HabitService/PomodoroService own (see TodoPrefsHelper for
 * why the "flutter." prefix), and computes the same behavior-pattern summary
 * as lib/services/behavior_insights_service.dart — same field names, same
 * rules, same 14-day window — so the native Smart Reminders check-in can
 * feed real behavioral context into its Groq call too, not just the Dart
 * side. Kept as a hand-ported duplicate rather than shared code because
 * there's no warm Flutter engine to call into from a background service
 * (same tradeoff already accepted for recurrence-rule logic — see
 * AlarmSchedulerHelper.occursOn/nextTriggerMillis).
 */
object BehaviorPrefsHelper {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val HABITS_KEY = "flutter.habits_v1"
    private const val SESSIONS_KEY = "flutter.pomodoro_sessions_v1"

    private const val WINDOW_DAYS = 14
    private const val MIN_OCCURRENCES_FOR_RATE = 3
    private const val CHRONIC_THRESHOLD_PERCENT = 50

    private val WEEKDAY_NAMES = arrayOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

    fun readHabits(context: Context): List<NativeHabitInfo> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(HABITS_KEY, null) ?: return emptyList()
        val arr = try { JSONArray(raw) } catch (_: Exception) { return emptyList() }
        val out = mutableListOf<NativeHabitInfo>()
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            val datesArr = obj.optJSONArray("completedDates")
            val dates = mutableSetOf<String>()
            if (datesArr != null) {
                for (j in 0 until datesArr.length()) dates.add(datesArr.optString(j))
            }
            out.add(NativeHabitInfo(obj.optString("title", "Habit"), dates))
        }
        return out
    }

    fun readPomodoroSessions(context: Context): List<NativePomodoroSession> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(SESSIONS_KEY, null) ?: return emptyList()
        val arr = try { JSONArray(raw) } catch (_: Exception) { return emptyList() }
        val out = mutableListOf<NativePomodoroSession>()
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            val taskTitle = obj.optString("task", "").ifEmpty { null }
            out.add(
                NativePomodoroSession(
                    completedAtMillis = obj.optLong("at", 0L),
                    minutes = obj.optInt("min", 0),
                    taskTitle = taskTitle,
                )
            )
        }
        return out
    }

    /**
     * Kotlin port of BehaviorInsightsService.summarize(). [tasks] is the raw
     * JSONArray from TodoPrefsHelper.readTasks(). [now] should be midnight-
     * agnostic (only the date fields are used).
     */
    fun computeBehaviorSnapshot(
        tasks: JSONArray,
        habits: List<NativeHabitInfo>,
        sessions: List<NativePomodoroSession>,
        now: Calendar,
    ): JSONObject {
        val windowDates = buildWindowDates(now)
        val windowDateKeys = windowDates.map { dateKey(it) }

        val occurrences = buildOccurrenceStream(tasks, windowDates, windowDateKeys)

        val out = JSONObject()
        out.put("windowDays", WINDOW_DAYS)

        if (occurrences.size >= MIN_OCCURRENCES_FOR_RATE) {
            rate(occurrences.map { it.done })?.let { out.put("completionRatePercent", it) }
        }

        val byWeekday = groupRatePercent(occurrences) { WEEKDAY_NAMES[weekdayIndex(it.weekday)] }
        if (byWeekday.length() > 0) out.put("completionRateByWeekday", byWeekday)

        val byPriority = groupRatePercent(occurrences) { it.priority }
        if (byPriority.length() > 0) out.put("completionRateByPriority", byPriority)

        val chronic = chronicallyMissedTasks(tasks, windowDates)
        if (chronic.length() > 0) out.put("chronicallyMissedTasks", chronic)

        val streaks = habitStreaks(habits, windowDates, windowDateKeys)
        if (streaks.length() > 0) out.put("habitStreaks", streaks)

        val windowKeySet = windowDateKeys.toSet()
        val windowSessions = sessions.filter { dateKeyFromMillis(it.completedAtMillis) in windowKeySet }
        if (windowSessions.isNotEmpty()) {
            val avg = Math.round((windowSessions.size.toDouble() / WINDOW_DAYS) * 10.0) / 10.0
            out.put("pomodoroSessionsPerDayAvg", avg)
            val top = topFocusedTasks(windowSessions)
            if (top.length() > 0) out.put("pomodoroTopFocusedTasks", top)
        }

        return out
    }

    // ── Window setup: exactly WINDOW_DAYS consecutive midnights ending today ──

    private fun buildWindowDates(now: Calendar): List<Calendar> {
        val start = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, -(WINDOW_DAYS - 1))
        }
        val out = mutableListOf<Calendar>()
        var day = start
        for (i in 0 until WINDOW_DAYS) {
            out.add(day)
            day = (day.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
        }
        return out
    }

    private fun dateKey(cal: Calendar): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cal.time)

    private fun dateKeyFromMillis(millis: Long): String {
        val cal = Calendar.getInstance().apply { timeInMillis = millis }
        return dateKey(cal)
    }

    // DateTime.weekday in Dart is 1=Mon..7=Sun; Calendar.DAY_OF_WEEK is 1=Sun..7=Sat.
    private fun weekdayIndex(calendarDayOfWeek: Int): Int = (calendarDayOfWeek + 5) % 7

    // ── Occurrence stream ─────────────────────────────────────────────────────

    private fun buildOccurrenceStream(
        tasks: JSONArray, windowDates: List<Calendar>, windowDateKeys: List<String>,
    ): List<Occurrence> {
        val out = mutableListOf<Occurrence>()
        for (i in 0 until tasks.length()) {
            val obj = tasks.optJSONObject(i) ?: continue
            val recurrenceRule = obj.optString("recurrenceRule", "none")
            val priority = obj.optString("priority", "medium")

            if (recurrenceRule != "none") {
                val completedDates = jsonStringSet(obj.optJSONArray("completedDates"))
                for (day in windowDates) {
                    if (!AlarmSchedulerHelper.occursOn(recurrenceRule, day)) continue
                    out.add(Occurrence(day.get(Calendar.DAY_OF_WEEK), priority, dateKey(day) in completedDates))
                }
            } else {
                val dueDateMillis = obj.optLong("dueDate", -1L)
                if (dueDateMillis < 0) continue
                val dueKey = dateKeyFromMillis(dueDateMillis)
                val idx = windowDateKeys.indexOf(dueKey)
                if (idx < 0) continue
                out.add(Occurrence(
                    windowDates[idx].get(Calendar.DAY_OF_WEEK), priority,
                    obj.optBoolean("isCompleted", false),
                ))
            }
        }
        return out
    }

    private fun groupRatePercent(
        occurrences: List<Occurrence>, keyOf: (Occurrence) -> String,
    ): JSONObject {
        val buckets = mutableMapOf<String, MutableList<Boolean>>()
        for (o in occurrences) buckets.getOrPut(keyOf(o)) { mutableListOf() }.add(o.done)
        val out = JSONObject()
        for ((key, doneList) in buckets) {
            if (doneList.size < MIN_OCCURRENCES_FOR_RATE) continue
            rate(doneList)?.let { out.put(key, it) }
        }
        return out
    }

    private fun rate(doneList: List<Boolean>): Int? {
        if (doneList.isEmpty()) return null
        return Math.round((doneList.count { it }.toDouble() / doneList.size) * 100.0).toInt()
    }

    // ── Chronically-missed recurring tasks ───────────────────────────────────

    private fun chronicallyMissedTasks(tasks: JSONArray, windowDates: List<Calendar>): JSONArray {
        val scored = mutableListOf<Triple<String, Int, Int>>()
        for (i in 0 until tasks.length()) {
            val obj = tasks.optJSONObject(i) ?: continue
            val recurrenceRule = obj.optString("recurrenceRule", "none")
            if (recurrenceRule == "none") continue
            val completedDates = jsonStringSet(obj.optJSONArray("completedDates"))
            var occurrences = 0
            var done = 0
            for (day in windowDates) {
                if (!AlarmSchedulerHelper.occursOn(recurrenceRule, day)) continue
                occurrences++
                if (dateKey(day) in completedDates) done++
            }
            if (occurrences < MIN_OCCURRENCES_FOR_RATE) continue
            val r = Math.round((done.toDouble() / occurrences) * 100.0).toInt()
            if (r < CHRONIC_THRESHOLD_PERCENT) {
                scored.add(Triple(obj.optString("title", "Task"), r, occurrences))
            }
        }
        scored.sortBy { it.second }
        val out = JSONArray()
        scored.take(5).forEach { out.put(it.first) }
        return out
    }

    // ── Habit streaks ────────────────────────────────────────────────────────

    private fun habitStreaks(
        habits: List<NativeHabitInfo>, windowDates: List<Calendar>, windowDateKeys: List<String>,
    ): JSONArray {
        data class Scored(val title: String, val streak: Int, val rate: Int)
        val scored = habits.map { h ->
            val streak = currentStreak(h, windowDates)
            val done = windowDateKeys.count { it in h.completedDates }
            val r = Math.round((done.toDouble() / WINDOW_DAYS) * 100.0).toInt()
            Scored(h.title, streak, r)
        }.sortedByDescending { it.streak }
        val out = JSONArray()
        scored.take(5).forEach {
            out.put(JSONObject().apply {
                put("title", it.title)
                put("streak", it.streak)
                put("completionRatePercent", it.rate)
            })
        }
        return out
    }

    /** Mirrors Habit.currentStreak() in lib/models/habit.dart: consecutive
     * completed days ending today, or yesterday if today isn't done yet.
     * [windowDates] is used only as a source of "today" (its last entry). */
    private fun currentStreak(habit: NativeHabitInfo, windowDates: List<Calendar>): Int {
        var day = (windowDates.last().clone() as Calendar)
        if (dateKey(day) !in habit.completedDates) {
            day = (day.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -1) }
        }
        var n = 0
        while (dateKey(day) in habit.completedDates) {
            n++
            day = (day.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -1) }
        }
        return n
    }

    // ── Pomodoro ──────────────────────────────────────────────────────────────

    private fun topFocusedTasks(windowSessions: List<NativePomodoroSession>): JSONArray {
        val minutesByTask = mutableMapOf<String, Int>()
        for (s in windowSessions) {
            val title = s.taskTitle?.trim()
            if (title.isNullOrEmpty()) continue
            minutesByTask[title] = (minutesByTask[title] ?: 0) + s.minutes
        }
        val out = JSONArray()
        minutesByTask.entries.sortedByDescending { it.value }.take(3).forEach { out.put(it.key) }
        return out
    }

    private fun jsonStringSet(arr: JSONArray?): Set<String> {
        if (arr == null) return emptySet()
        val out = mutableSetOf<String>()
        for (i in 0 until arr.length()) out.add(arr.optString(i))
        return out
    }
}
