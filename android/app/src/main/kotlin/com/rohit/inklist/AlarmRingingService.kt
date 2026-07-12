package com.rohit.inklist

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.CountDownTimer
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat

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

        startForeground(FOREGROUND_NOTIFICATION_ID, buildForegroundNotification(title))
        launchRingingActivity(taskId, title)
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

    private fun startRinging() {
        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            isLooping = true
            try {
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

    private fun buildForegroundNotification(title: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher_foreground)
            .setContentTitle("Alarm: $title")
            .setContentText("Tap to open")
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
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
