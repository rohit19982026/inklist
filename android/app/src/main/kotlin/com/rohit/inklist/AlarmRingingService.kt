package com.rohit.inklist

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.CountDownTimer
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Foreground service that loops the system alarm ringtone + vibration until
 * the user hits Snooze/Dismiss on [AlarmRingingActivity], or a 5-minute
 * safety timeout elapses (so an unattended phone doesn't ring forever).
 */
class AlarmRingingService : Service() {

    companion object {
        const val CHANNEL_ID = "task_alarms"
        const val CHANNEL_NAME = "Task Alarms"
        const val FOREGROUND_NOTIFICATION_ID = 20001
        const val ACTION_STOP = "com.rohit.inklist.action.STOP_ALARM_RING"
        // Tapped directly from the notification's action buttons — lets the
        // user snooze/dismiss without the full-screen UI having launched.
        const val ACTION_NOTIF_SNOOZE = "com.rohit.inklist.action.NOTIF_SNOOZE"
        const val ACTION_NOTIF_DISMISS = "com.rohit.inklist.action.NOTIF_DISMISS"
        val EXTRA_TASK_ID = AlarmSchedulerHelper.EXTRA_TASK_ID
        val EXTRA_TITLE = AlarmSchedulerHelper.EXTRA_TITLE
        private const val SAFETY_TIMEOUT_MS = 5 * 60 * 1000L
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var safetyTimer: CountDownTimer? = null
    private var receiverRegistered = false

    private val stopReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            stopRinging()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val filter = IntentFilter(ACTION_STOP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(stopReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val taskId = intent?.getStringExtra(EXTRA_TASK_ID) ?: ""
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Task"

        when (intent?.action) {
            ACTION_NOTIF_SNOOZE -> {
                snoozeFromNotification(taskId, title)
                return START_NOT_STICKY
            }
            ACTION_NOTIF_DISMISS -> {
                dismissFromNotification(taskId)
                return START_NOT_STICKY
            }
        }

        startForeground(FOREGROUND_NOTIFICATION_ID, buildForegroundNotification(taskId, title))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Pre-Android 10 has no background-activity-start restriction, and
            // some older OEM skins are slow to honor a full-screen-intent
            // notification — launch directly too, for belt-and-suspenders.
            launchRingingActivity(taskId, title)
        }
        startRinging()

        safetyTimer?.cancel()
        safetyTimer = object : CountDownTimer(SAFETY_TIMEOUT_MS, SAFETY_TIMEOUT_MS) {
            override fun onTick(millisUntilFinished: Long) {}
            override fun onFinish() { stopRinging() }
        }.start()

        return START_NOT_STICKY
    }

    private fun launchRingingActivity(taskId: String, title: String) {
        val intent = Intent(this, AlarmRingingActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra(EXTRA_TITLE, title)
        }
        startActivity(intent)
    }

    private fun ringingActivityPendingIntent(taskId: String, title: String): PendingIntent {
        val intent = Intent(this, AlarmRingingActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra(EXTRA_TITLE, title)
        }
        return PendingIntent.getActivity(
            this, taskId.hashCode(), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    // ── Notification action buttons — mirror AlarmRingingActivity's own
    // Snooze/Dismiss so the user can act straight from the notification,
    // e.g. if the full-screen UI didn't auto-launch on this device/OS.

    private fun notificationActionPendingIntent(
        action: String, requestCodeOffset: Int, taskId: String, title: String
    ): PendingIntent {
        val intent = Intent(this, AlarmRingingService::class.java).apply {
            this.action = action
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra(EXTRA_TITLE, title)
        }
        return PendingIntent.getService(
            this, taskId.hashCode() + requestCodeOffset, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun snoozeFromNotification(taskId: String, title: String) {
        val requestCode = taskId.hashCode() + AlarmSchedulerHelper.SNOOZE_OFFSET
        val triggerAt = System.currentTimeMillis() + 10 * 60 * 1000L
        AlarmSchedulerHelper.schedule(this, requestCode, taskId, title, triggerAt, "none")
        stopRinging()
    }

    private fun dismissFromNotification(taskId: String) {
        try {
            TodoPrefsHelper.markCompletedToday(applicationContext, taskId)
        } catch (_: Exception) {
            // Best-effort — the alarm still stops ringing even if this fails.
        }
        stopRinging()
    }

    /**
     * The user's chosen tone (Settings → Alarm & Notification Tone), or —
     * when nothing's been picked yet — the system's default *notification*
     * sound rather than the default *alarm* sound. The stock alarm sound is
     * deliberately loud/jarring by design; this is meant to be a soothing
     * to-do reminder, not a wake-up alarm.
     */
    private fun selectedToneUri(): Uri? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val saved = prefs.getString("flutter.alarm_tone_uri", null)
        if (!saved.isNullOrEmpty()) {
            try { return Uri.parse(saved) } catch (_: Exception) {}
        }
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
    }

    private fun startRinging() {
        val alarmUri = selectedToneUri()
        mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            isLooping = true
            try {
                if (alarmUri == null) throw IllegalStateException("No tone URI available")
                setDataSource(this@AlarmRingingService, alarmUri)
                prepare()
                start()
            } catch (_: Exception) {
                // No alarm sound available on this device — vibration still runs.
            }
        }

        vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        val pattern = longArrayOf(0, 500, 250, 500, 250, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun stopRinging() {
        safetyTimer?.cancel()
        mediaPlayer?.let {
            try { if (it.isPlaying) it.stop() } catch (_: Exception) {}
            it.release()
        }
        mediaPlayer = null
        vibrator?.cancel()
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }

    /**
     * This notification IS how the ringing screen actually launches on
     * Android 10+: a Service started from a BroadcastReceiver can't call
     * startActivity() directly (background-activity-start restriction), but
     * a full-screen-intent notification is the OS-sanctioned exception,
     * which is exactly what USE_FULL_SCREEN_INTENT (declared in the
     * manifest) exists for. If the system declines to auto-launch it (e.g.
     * the device is unlocked and in active use, or — Android 14+ — the user
     * hasn't granted the separate full-screen-intent toggle) this still
     * surfaces as a heads-up notification the user can tap to open.
     */
    private fun buildForegroundNotification(taskId: String, title: String): Notification {
        val contentPending = ringingActivityPendingIntent(taskId, title)
        val snoozePending =
            notificationActionPendingIntent(ACTION_NOTIF_SNOOZE, 1, taskId, title)
        val dismissPending =
            notificationActionPendingIntent(ACTION_NOTIF_DISMISS, 2, taskId, title)
        val timeLabel = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date())
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setColor(NotificationIcons.BRAND_COLOR)
            .setLargeIcon(NotificationIcons.appLargeIcon(this))
            .setContentTitle(title)
            .setContentText("Alarm · $timeLabel")
            .setSubText("InkList")
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setFullScreenIntent(contentPending, true)
            .setContentIntent(contentPending)
            .addAction(R.drawable.ic_stat_snooze, "Snooze 10 min", snoozePending)
            .addAction(R.drawable.ic_stat_dismiss, "Dismiss", dismissPending)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Task alarms that ring like a real alarm clock"
            setSound(null, null) // this service plays the sound itself via MediaPlayer
            enableVibration(false) // this service handles vibration itself
        }
        nm.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        stopRinging()
        if (receiverRegistered) {
            try { unregisterReceiver(stopReceiver) } catch (_: Exception) {}
            receiverRegistered = false
        }
        super.onDestroy()
    }
}
