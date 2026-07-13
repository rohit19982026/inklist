package com.rohit.inklist

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Runs one "smart reminder" check-in: reads today's relevant tasks, asks
 * Groq (or falls back to a simple rule) whether the user needs a nudge
 * right now, and executes that decision — silently updating the cached
 * brief text, posting a notification, or ringing the existing full-screen
 * alarm — all without any Flutter engine/UI involvement. Runs as a
 * foreground service (started from a BroadcastReceiver, the same exemption
 * AlarmReceiver already relies on for AlarmRingingService) so the Groq
 * network call has a safe place to run off the main thread via a coroutine.
 */
class SmartReminderService : Service() {

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_AI_ENABLED = "flutter.ai_features_enabled"
        private const val KEY_API_KEY = "flutter.groq_api_key"
        private const val KEY_NAG_STATE = "flutter.smart_reminder_nag_state"
        private const val KEY_BRIEF_CACHE = "flutter.ai_daily_brief_cache"

        private const val TRANSIENT_CHANNEL_ID = "smart_reminder_check"
        private const val TRANSIENT_NOTIFICATION_ID = 20002
        private const val REMINDER_CHANNEL_ID = "smart_reminders"
        private const val REMINDER_NOTIFICATION_ID = 10004
        private const val REVIEW_NOTIFICATION_ID = 10005

        private const val MAX_NOTIFY_PER_DAY = 4
        private const val MAX_ALARM_PER_DAY = 2

        private const val GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
        private const val GROQ_MODEL = "llama-3.3-70b-versatile"
    }

    private data class RelevantTask(val title: String, val priority: String, val overdue: Boolean)
    private data class NagState(
        val notifyCount: Int,
        val alarmCount: Int,
        val reviewAm: Boolean = false,
        val reviewPm: Boolean = false,
    )
    private data class Decision(val urgency: String, val message: String)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(TRANSIENT_NOTIFICATION_ID, buildTransientNotification())
        CoroutineScope(Dispatchers.IO).launch {
            try {
                runCheckIn()
            } finally {
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun runCheckIn() {
        val todayCal = Calendar.getInstance()
        val todayKey = dateKey(todayCal)
        val hour = todayCal.get(Calendar.HOUR_OF_DAY)

        val tasks = TodoPrefsHelper.readTasks(applicationContext)
        val relevant = computeRelevantTasks(tasks, todayCal, todayKey)
        val nagState = readNagState(todayKey)

        // Compulsory daily review nudge — fires for everyone, once per period
        // per day, independent of tasks, AI, or an API key. This is the core
        // "review your plan today / review your day" promise. When it posts we
        // stop here so this check-in never stacks two notifications at once.
        if (maybePostDailyReview(hour, relevant, nagState, todayKey)) return

        if (relevant.isEmpty()) return // nothing else to report — leave cache as-is
        if (nagState.notifyCount >= MAX_NOTIFY_PER_DAY && nagState.alarmCount >= MAX_ALARM_PER_DAY) {
            return // hard cap reached for everything that could still fire
        }

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val aiEnabled = prefs.getBoolean(KEY_AI_ENABLED, false)
        val apiKey = prefs.getString(KEY_API_KEY, null)

        val decision = if (aiEnabled && !apiKey.isNullOrBlank()) {
            val behavior = BehaviorPrefsHelper.computeBehaviorSnapshot(
                tasks,
                BehaviorPrefsHelper.readHabits(applicationContext),
                BehaviorPrefsHelper.readPomodoroSessions(applicationContext),
                todayCal,
            )
            callGroqForDecision(apiKey, relevant, nagState, behavior)
                ?: ruleBasedDecision(relevant, nagState)
        } else {
            ruleBasedDecision(relevant, nagState)
        }

        executeDecision(decision, nagState, todayKey, todayCal)
    }

    // ── Relevant-task filtering (mirrors TodoService.tasksForDay/overdueTasks) ──

    private fun computeRelevantTasks(
        tasks: JSONArray, todayCal: Calendar, todayKey: String
    ): List<RelevantTask> {
        val out = mutableListOf<RelevantTask>()
        for (i in 0 until tasks.length()) {
            val obj = tasks.optJSONObject(i) ?: continue
            val recurrenceRule = obj.optString("recurrenceRule", "none")
            val isRecurring = recurrenceRule != "none"
            val dueDateMillis = obj.optLong("dueDate", -1L)
            if (dueDateMillis < 0) continue
            val priority = obj.optString("priority", "medium")
            val title = obj.optString("title", "Task")

            if (isRecurring) {
                if (!AlarmSchedulerHelper.occursOn(recurrenceRule, todayCal)) continue
                val completedDates = obj.optJSONArray("completedDates")
                val doneToday = completedDates != null && (0 until completedDates.length())
                    .any { completedDates.optString(it) == todayKey }
                if (doneToday) continue
                out.add(RelevantTask(title, priority, overdue = false))
            } else {
                if (obj.optBoolean("isCompleted", false)) continue
                val dueCal = Calendar.getInstance().apply { timeInMillis = dueDateMillis }
                val isToday = isSameDay(dueCal, todayCal)
                val isOverdue = !isToday && isBeforeDay(dueCal, todayCal)
                if (isToday || isOverdue) out.add(RelevantTask(title, priority, isOverdue))
            }
        }
        return out
    }

    private fun isSameDay(a: Calendar, b: Calendar): Boolean =
        a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)

    private fun isBeforeDay(a: Calendar, b: Calendar): Boolean {
        if (a.get(Calendar.YEAR) != b.get(Calendar.YEAR)) return a.get(Calendar.YEAR) < b.get(Calendar.YEAR)
        return a.get(Calendar.DAY_OF_YEAR) < b.get(Calendar.DAY_OF_YEAR)
    }

    private fun dateKey(cal: Calendar): String = String.format(
        Locale.US, "%04d-%02d-%02d",
        cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH)
    )

    // ── Nag-state (daily caps, independent of AI judgment) ──────────────────

    private fun readNagState(todayKey: String): NagState {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_NAG_STATE, null) ?: return NagState(0, 0)
        return try {
            val obj = JSONObject(raw)
            if (obj.optString("date") != todayKey) NagState(0, 0)
            else NagState(
                obj.optInt("notifyCount", 0),
                obj.optInt("alarmCount", 0),
                obj.optBoolean("reviewAm", false),
                obj.optBoolean("reviewPm", false),
            )
        } catch (e: Exception) {
            NagState(0, 0)
        }
    }

    private fun writeNagState(todayKey: String, state: NagState) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val obj = JSONObject().apply {
            put("date", todayKey)
            put("notifyCount", state.notifyCount)
            put("alarmCount", state.alarmCount)
            put("reviewAm", state.reviewAm)
            put("reviewPm", state.reviewPm)
        }
        prefs.edit().putString(KEY_NAG_STATE, obj.toString()).apply()
    }

    /**
     * The compulsory daily review nudge. Morning (before noon) posts "review
     * your plan"; evening (5pm+) posts "review your day". Each fires at most
     * once per day via the reviewAm/reviewPm flags, and works with zero tasks,
     * no AI, and no API key. Returns true if it posted something this run.
     */
    private fun maybePostDailyReview(
        hour: Int, relevant: List<RelevantTask>, nagState: NagState, todayKey: String
    ): Boolean {
        val open = relevant.size
        if (hour < 12 && !nagState.reviewAm) {
            val msg = if (open > 0)
                "You have $open thing${if (open == 1) "" else "s"} planned today. Review your plan ☀️"
            else
                "A fresh day — plan what matters most ☀️"
            postReview("Good morning", msg)
            writeNagState(todayKey, nagState.copy(reviewAm = true))
            return true
        }
        if (hour >= 17 && !nagState.reviewPm) {
            val msg = if (open > 0)
                "$open task${if (open == 1) "" else "s"} still open. Review your day 🌙"
            else
                "All caught up — set up tomorrow? 🌙"
            postReview("Evening check-in", msg)
            writeNagState(todayKey, nagState.copy(reviewPm = true))
            return true
        }
        return false
    }

    private fun writeBriefCache(todayKey: String, text: String) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val obj = JSONObject().apply { put("date", todayKey); put("text", text) }
        prefs.edit().putString(KEY_BRIEF_CACHE, obj.toString()).apply()
    }

    // ── Rule-based fallback (no API key, AI disabled, or a malformed Groq response) ──

    private fun ruleBasedDecision(relevant: List<RelevantTask>, nagState: NagState): Decision {
        val overdueHighPriority = relevant.filter { it.overdue && it.priority == "high" }
        // Static rules never ring a disruptive full-screen alarm — that's reserved for AI judgment.
        if (overdueHighPriority.isNotEmpty() && nagState.notifyCount < MAX_NOTIFY_PER_DAY) {
            val first = overdueHighPriority.first().title
            val extra = overdueHighPriority.size - 1
            val msg = if (extra > 0) {
                "You have ${overdueHighPriority.size} overdue tasks, including \"$first\"."
            } else {
                "\"$first\" is overdue."
            }
            return Decision("notify", msg)
        }
        return Decision("none", "")
    }

    // ── Groq call ────────────────────────────────────────────────────────────

    private fun callGroqForDecision(
        apiKey: String, relevant: List<RelevantTask>, nagState: NagState, behavior: JSONObject
    ): Decision? {
        val systemPrompt = "You are a task-reminder assistant for a personal to-do app. You " +
            "will be given the user's relevant tasks right now (title, priority, whether " +
            "overdue), how many times they've already been nagged today, and — when present " +
            "— a \"behavior\" object summarizing their actual completion patterns over the " +
            "last ~2 weeks (completion rates by weekday/priority, recurring tasks that keep " +
            "getting missed, habit streaks, focus-session activity). Use \"behavior\" to judge " +
            "urgency more accurately (e.g. a task on a weekday/category with a chronically low " +
            "completion rate deserves a more direct nudge than a one-off slip); reference a " +
            "specific pattern in \"message\" when it's relevant, otherwise ignore \"behavior\" " +
            "if it's absent or too thin. Decide ONE of: " +
            "\"none\" (nothing meaningfully new since the last check-in), \"notify\" (a normal " +
            "notification is warranted), or \"alarm\" (only for a HIGH-priority task that is " +
            "overdue and hasn't already triggered an alarm today — use sparingly, most " +
            "check-ins should be \"none\" or \"notify\"). Today they've had " +
            "${nagState.notifyCount} notification(s) and ${nagState.alarmCount} alarm(s) " +
            "already — never suggest \"alarm\" if alarmCount >= $MAX_ALARM_PER_DAY, never " +
            "suggest \"notify\" if notifyCount >= $MAX_NOTIFY_PER_DAY. Respond ONLY with JSON: " +
            "{\"urgency\": \"none\"|\"notify\"|\"alarm\", \"message\": \"<short specific " +
            "message, under 100 chars, empty string if none>\"}"

        val tasksJson = JSONArray()
        for (t in relevant) {
            tasksJson.put(JSONObject().apply {
                put("title", t.title)
                put("priority", t.priority)
                put("overdue", t.overdue)
            })
        }
        val userContent = JSONObject().apply {
            put("tasks", tasksJson)
            put("notifyCountToday", nagState.notifyCount)
            put("alarmCountToday", nagState.alarmCount)
            if (behavior.length() > 1) put("behavior", behavior) // >1: more than just windowDays
        }.toString()

        val content = postGroq(apiKey, systemPrompt, userContent) ?: return null
        return try {
            val obj = JSONObject(content)
            val urgency = obj.optString("urgency", "")
            if (urgency != "none" && urgency != "notify" && urgency != "alarm") return null
            Decision(urgency, obj.optString("message", ""))
        } catch (e: Exception) {
            null
        }
    }

    private fun postGroq(apiKey: String, systemPrompt: String, userContent: String): String? {
        return try {
            val conn = URL(GROQ_ENDPOINT).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Authorization", "Bearer $apiKey")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000

            val body = JSONObject().apply {
                put("model", GROQ_MODEL)
                put("temperature", 0.3)
                put("response_format", JSONObject().put("type", "json_object"))
                put("messages", JSONArray().apply {
                    put(JSONObject().apply { put("role", "system"); put("content", systemPrompt) })
                    put(JSONObject().apply { put("role", "user"); put("content", userContent) })
                })
            }
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }

            if (conn.responseCode != 200) {
                conn.disconnect()
                return null
            }
            val response = conn.inputStream.bufferedReader().use { it.readText() }
            conn.disconnect()

            val json = JSONObject(response)
            val choices = json.optJSONArray("choices") ?: return null
            if (choices.length() == 0) return null
            val message = choices.getJSONObject(0).optJSONObject("message") ?: return null
            val content = message.optString("content", "")
            content.ifEmpty { null }
        } catch (e: Exception) {
            null
        }
    }

    // ── Decision execution ──────────────────────────────────────────────────

    private fun executeDecision(decision: Decision, nagState: NagState, todayKey: String, todayCal: Calendar) {
        when (decision.urgency) {
            "notify" -> {
                writeNagState(todayKey, nagState.copy(notifyCount = nagState.notifyCount + 1))
                postNotify(decision.message)
                writeBriefCache(todayKey, decision.message)
            }
            "alarm" -> {
                writeNagState(todayKey, nagState.copy(alarmCount = nagState.alarmCount + 1))
                startAlarm(decision.message)
                writeBriefCache(todayKey, decision.message)
            }
            else -> {
                val timeStr = SimpleDateFormat("h:mm a", Locale.getDefault()).format(todayCal.time)
                writeBriefCache(todayKey, "All caught up as of $timeStr.")
            }
        }
    }

    private fun postNotify(message: String) =
        postNotification("Task check-in", message, REMINDER_NOTIFICATION_ID)

    private fun postReview(title: String, message: String) =
        postNotification(title, message, REVIEW_NOTIFICATION_ID)

    /**
     * The same tone the user picked for task alarms (Settings → Alarm &
     * Notification Tone — one setting covers both, per the feature request),
     * falling back to the system's default notification sound when nothing's
     * been picked yet.
     */
    private fun selectedToneUri(): Uri? {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val saved = prefs.getString("flutter.alarm_tone_uri", null)
        if (!saved.isNullOrEmpty()) {
            try { return Uri.parse(saved) } catch (_: Exception) {}
        }
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
    }

    /**
     * A NotificationChannel's sound is immutable once created — the only way
     * to change it after the fact is to delete and recreate the channel
     * under the same ID, which is exactly what this does whenever the
     * currently-registered sound no longer matches the user's selection.
     */
    private fun ensureChannelWithTone(
        nm: NotificationManager, channelId: String, name: String, description: String,
    ) {
        val desiredSound = selectedToneUri()
        val existing = nm.getNotificationChannel(channelId)
        if (existing != null && existing.sound == desiredSound) return
        if (existing != null) nm.deleteNotificationChannel(channelId)
        val channel = NotificationChannel(
            channelId, name, NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            this.description = description
            setSound(
                desiredSound,
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build(),
            )
            enableLights(true)
            lightColor = NotificationIcons.BRAND_COLOR
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 250, 150, 250)
        }
        nm.createNotificationChannel(channel)
    }

    private fun postNotification(title: String, message: String, id: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            ensureChannelWithTone(
                nm, REMINDER_CHANNEL_ID, "Smart Reminders",
                "Daily plan reviews and check-ins about tasks that need attention",
            )
        }
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingTap = PendingIntent.getActivity(
            this, id, tapIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(this, REMINDER_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setColor(NotificationIcons.BRAND_COLOR)
            .setLargeIcon(NotificationIcons.appLargeIcon(this))
            .setContentTitle(title)
            .setContentText(message)
            .setSubText("InkList")
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(pendingTap)
            .build()
        try {
            NotificationManagerCompat.from(this).notify(id, notification)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted on API 33+ — the decision still
            // gets written to the brief cache regardless.
        }
    }

    private fun startAlarm(message: String) {
        val intent = Intent(this, AlarmRingingService::class.java).apply {
            putExtra(AlarmRingingService.EXTRA_TASK_ID, "smart_nag")
            putExtra(AlarmRingingService.EXTRA_TITLE, message)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    // ── This service's own transient foreground notification ───────────────

    private fun buildTransientNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(TRANSIENT_CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    TRANSIENT_CHANNEL_ID, "Background Check-in", NotificationManager.IMPORTANCE_MIN
                )
                nm.createNotificationChannel(channel)
            }
        }
        return NotificationCompat.Builder(this, TRANSIENT_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setColor(NotificationIcons.BRAND_COLOR)
            .setContentTitle("Checking your tasks…")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .build()
    }
}
