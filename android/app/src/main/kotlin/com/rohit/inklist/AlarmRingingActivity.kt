package com.rohit.inklist

import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
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
 * Plain native views by design (no Flutter, no third-party animation libs —
 * everything here is stock Android so it always compiles and never depends
 * on a warm engine), but built to actually look like InkList: the same
 * coral/violet "paper planner" palette as the rest of the app, a breathing
 * pulse animation instead of a static block of color, and the task itself
 * front and center rather than a generic "Task" label.
 */
class AlarmRingingActivity : Activity() {

    private var taskId: String = ""
    private var title: String = "Task"
    // Guards against onKeyDown's auto-repeat (a held volume key fires this
    // repeatedly) or a double tap re-entering dismiss()/snooze() before the
    // activity has actually finished.
    private var handled = false
    private val pulseAnimators = mutableListOf<ValueAnimator>()

    companion object {
        private const val CORAL = 0xFFEF6B52.toInt() // AppColors.primary
        private const val VIOLET = 0xFF7C6BD6.toInt() // AppColors.accent
        private const val WHITE = 0xFFFFFFFF.toInt()
    }

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

    // ── Layout ───────────────────────────────────────────────────────────────

    private fun buildLayout(): View {
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val root = FrameLayout(this).apply {
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR, intArrayOf(CORAL, VIOLET))
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(32), dp(48), dp(32), dp(40))
            alpha = 0f
            translationY = dp(24).toFloat()
        }

        val appIcon = ImageView(this).apply {
            setImageBitmap(NotificationIcons.appLargeIcon(this@AlarmRingingActivity))
            alpha = 0.9f
        }
        content.addView(appIcon, LinearLayout.LayoutParams(dp(36), dp(36)))

        val eyebrow = TextView(this).apply {
            text = "TASK ALARM"
            textSize = 12f
            letterSpacing = 0.18f
            setTextColor(withAlpha(WHITE, 0.8f))
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, 0)
        }
        content.addView(eyebrow)

        val timeText = TextView(this).apply {
            text = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date())
            textSize = 16f
            setTextColor(withAlpha(WHITE, 0.75f))
            gravity = Gravity.CENTER
            setPadding(0, dp(4), 0, 0)
        }
        content.addView(timeText)

        content.addView(buildPulsingIcon(dp(176)), LinearLayout.LayoutParams(
            dp(176), dp(176)
        ).apply { topMargin = dp(28); bottomMargin = dp(28) })

        val titleText = TextView(this).apply {
            text = title
            textSize = 28f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setTextColor(WHITE)
            gravity = Gravity.CENTER
            maxLines = 3
        }
        content.addView(titleText)

        val priority = TodoPrefsHelper.readPriority(applicationContext, taskId)
        if (priority == "high" || priority == "low") {
            content.addView(buildPriorityChip(priority), LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(14) })
        }

        val buttonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val snoozeButton = pillButton(
            text = "Snooze",
            fillColor = withAlpha(WHITE, 0.16f),
            textColor = WHITE,
            strokeColor = withAlpha(WHITE, 0.6f),
        ).apply {
            setOnClickListener {
                isEnabled = false
                snooze()
            }
        }
        val dismissButton = pillButton(
            text = "Dismiss",
            fillColor = WHITE,
            textColor = CORAL,
            strokeColor = null,
        ).apply {
            setOnClickListener {
                isEnabled = false
                dismiss()
            }
        }
        buttonRow.addView(snoozeButton, LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
        ).apply { rightMargin = dp(10) })
        buttonRow.addView(dismissButton, LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
        ).apply { leftMargin = dp(10) })
        content.addView(buttonRow, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(40) })

        root.addView(content, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
        ))

        content.post {
            content.animate().alpha(1f).translationY(0f).setDuration(520)
                .setInterpolator(AccelerateDecelerateInterpolator()).start()
        }

        return root
    }

    /** Two staggered "breathing" ripple rings pulsing outward behind a
     * static icon circle — the calming, alive feel a soothing to-do
     * reminder should have, in place of the old static block of color. */
    private fun buildPulsingIcon(sizePx: Int): FrameLayout {
        val stack = FrameLayout(this)

        val ring1 = View(this).apply {
            background = ovalDrawable(withAlpha(WHITE, 0.28f))
        }
        val ring2 = View(this).apply {
            background = ovalDrawable(withAlpha(WHITE, 0.2f))
        }
        val core = FrameLayout(this).apply {
            background = ovalDrawable(withAlpha(WHITE, 0.22f))
        }
        val icon = ImageView(this).apply {
            setImageResource(R.drawable.ic_stat_notify)
            setColorFilter(WHITE)
        }

        val ringSize = sizePx
        val coreSize = (sizePx * 0.56f).toInt()
        val iconSize = (sizePx * 0.26f).toInt()

        stack.addView(ring1, FrameLayout.LayoutParams(ringSize, ringSize, Gravity.CENTER))
        stack.addView(ring2, FrameLayout.LayoutParams(ringSize, ringSize, Gravity.CENTER))
        stack.addView(core, FrameLayout.LayoutParams(coreSize, coreSize, Gravity.CENTER))
        core.addView(icon, FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER))

        startPulse(ring1, startDelay = 0L)
        startPulse(ring2, startDelay = 900L)

        return stack
    }

    private fun startPulse(target: View, startDelay: Long) {
        target.scaleX = 0.6f
        target.scaleY = 0.6f
        target.alpha = 0.55f
        val animator = ObjectAnimator.ofPropertyValuesHolder(
            target,
            PropertyValuesHolder.ofFloat(View.SCALE_X, 0.6f, 1f),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, 0.6f, 1f),
            PropertyValuesHolder.ofFloat(View.ALPHA, 0.55f, 0f),
        ).apply {
            duration = 1800L
            this.startDelay = startDelay
            repeatCount = ValueAnimator.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
        }
        animator.start()
        pulseAnimators.add(animator)
    }

    private fun buildPriorityChip(priority: String): TextView {
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()
        return TextView(this).apply {
            text = if (priority == "high") "HIGH PRIORITY" else "LOW PRIORITY"
            textSize = 11f
            letterSpacing = 0.1f
            setTextColor(WHITE)
            setPadding(dp(14), dp(6), dp(14), dp(6))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(20).toFloat()
                setColor(withAlpha(WHITE, 0.18f))
            }
        }
    }

    private fun pillButton(text: String, fillColor: Int, textColor: Int, strokeColor: Int?): Button {
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()
        return Button(this).apply {
            this.text = text
            isAllCaps = false
            textSize = 16f
            setTextColor(textColor)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(dp(16), dp(16), dp(16), dp(16))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(28).toFloat()
                setColor(fillColor)
                if (strokeColor != null) setStroke(dp(1), strokeColor)
            }
            elevation = if (strokeColor == null) dp(4).toFloat() else 0f
        }
    }

    private fun ovalDrawable(fillColor: Int): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(fillColor)
    }

    private fun withAlpha(color: Int, alpha: Float): Int {
        val a = (alpha.coerceIn(0f, 1f) * 255).toInt()
        return (a shl 24) or (color and 0x00FFFFFF)
    }

    // ── Snooze / Dismiss ─────────────────────────────────────────────────────

    /**
     * Volume buttons silence the alarm immediately, same as Dismiss — this
     * is meant to be a soothing to-do reminder, not something that fights
     * the user for control of their phone. Consumed (returns true) so the
     * system volume itself doesn't also change underneath the dismiss.
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            dismiss()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun snooze() {
        if (handled) return
        handled = true
        val priority = TodoPrefsHelper.readPriority(applicationContext, taskId)
        val minutes = SmartSnoozeHelper.nextSnoozeMinutes(applicationContext, taskId, priority)
        val requestCode = taskId.hashCode() + AlarmSchedulerHelper.SNOOZE_OFFSET
        val triggerAt = System.currentTimeMillis() + minutes * 60 * 1000L
        AlarmSchedulerHelper.schedule(this, requestCode, taskId, title, triggerAt, "none")
        stopRingingService()
        finishAndRemoveTask()
    }

    private fun dismiss() {
        if (handled) return
        handled = true
        markOccurrenceDone()
        stopRingingService()
        finishAndRemoveTask()
    }

    private fun markOccurrenceDone() {
        try {
            TodoPrefsHelper.markCompletedToday(applicationContext, taskId)
        } catch (_: Exception) {
            // Best-effort — the alarm still stops ringing even if this fails.
        }
    }

    /**
     * Stops AlarmRingingService two ways: a direct stopService() call (a
     * synchronous request through ActivityManager) and the ACTION_STOP
     * broadcast. The broadcast alone can race or simply never arrive if the
     * receiver hasn't finished registering yet, which is what made Dismiss
     * feel unreliable — stopService() doesn't depend on that at all, so this
     * is a guaranteed teardown with the broadcast as a redundant backstop.
     */
    private fun stopRingingService() {
        stopService(Intent(this, AlarmRingingService::class.java))
        sendBroadcast(Intent(AlarmRingingService.ACTION_STOP))
    }

    override fun onDestroy() {
        pulseAnimators.forEach { try { it.cancel() } catch (_: Exception) {} }
        pulseAnimators.clear()
        super.onDestroy()
    }
}
