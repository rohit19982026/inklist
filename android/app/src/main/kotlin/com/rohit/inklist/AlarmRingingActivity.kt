package com.rohit.inklist

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Native full-screen "alarm ringing" UI — shows over the lock screen even
 * when launched cold with the app fully killed. Deliberately not a Flutter
 * route: the Flutter engine may not be warm when an alarm fires, and a real
 * alarm-clock experience needs to render reliably regardless of app state.
 * Plain native views by design — not attempting to reproduce the Flutter
 * design system for a two-button emergency screen.
 */
class AlarmRingingActivity : Activity() {

    private var taskId: String = ""
    private var title: String = "Task"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        taskId = intent.getStringExtra(AlarmSchedulerHelper.EXTRA_TASK_ID) ?: ""
        title = intent.getStringExtra(AlarmSchedulerHelper.EXTRA_TITLE) ?: "Task"

        showOverLockScreen()
        setContentView(buildLayout())
    }

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            km.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun buildLayout(): LinearLayout {
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF4F46E5.toInt())
            setPadding(dp(32), dp(32), dp(32), dp(32))
        }

        val timeText = TextView(this).apply {
            text = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date())
            textSize = 18f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
        }
        val titleText = TextView(this).apply {
            text = title
            textSize = 26f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, dp(48))
        }

        val snoozeButton = Button(this).apply {
            text = "Snooze 10 min"
            setOnClickListener { snooze() }
        }
        val dismissButton = Button(this).apply {
            text = "Dismiss"
            setOnClickListener { dismiss() }
        }

        root.addView(timeText)
        root.addView(titleText)
        root.addView(snoozeButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ))
        root.addView(dismissButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(16) })
        return root
    }

    private fun snooze() {
        stopRingingService()
        val requestCode = taskId.hashCode() + AlarmSchedulerHelper.SNOOZE_OFFSET
        val triggerAt = System.currentTimeMillis() + 10 * 60 * 1000L
        AlarmSchedulerHelper.schedule(this, requestCode, taskId, title, triggerAt, "none")
        finish()
    }

    private fun dismiss() {
        markOccurrenceDone()
        stopRingingService()
        finish()
    }

    private fun markOccurrenceDone() {
        try {
            TodoPrefsHelper.markCompletedToday(applicationContext, taskId)
        } catch (_: Exception) {
            // Best-effort — the alarm still stops ringing even if this fails.
        }
    }

    private fun stopRingingService() {
        sendBroadcast(Intent(AlarmRingingService.ACTION_STOP))
    }
}
