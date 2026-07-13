package com.rohit.inklist

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.rohit.inklist/methods"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "openAppSettings" -> {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        intent.data = android.net.Uri.parse("package:$packageName")
                        startActivity(intent)
                        result.success(null)
                    }

                    "openPostNotificationsPermission" -> {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        startActivity(intent)
                        result.success(null)
                    }

                    "canPostNotifications" -> {
                        val nm = NotificationManagerCompat.from(applicationContext)
                        result.success(nm.areNotificationsEnabled())
                    }

                    // ── Task alarms (exact, ring-like-a-real-alarm-clock) ────
                    "canScheduleExactAlarms" -> {
                        result.success(AlarmSchedulerHelper.canScheduleExact(this))
                    }

                    "requestExactAlarmPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            intent.data = android.net.Uri.parse("package:$packageName")
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    "requestDndAccess" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                        result.success(null)
                    }

                    // Android 14+ gates the alarm's full-screen ringing UI behind a
                    // separate toggle from POST_NOTIFICATIONS — apps not pre-approved
                    // as a default alarm/calling app may need the user to flip it on
                    // manually even though USE_FULL_SCREEN_INTENT is in the manifest.
                    "canUseFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            val nm = getSystemService(NotificationManager::class.java)
                            result.success(nm?.canUseFullScreenIntent() ?: true)
                        } else {
                            result.success(true)
                        }
                    }

                    "requestFullScreenIntentPermission" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    "scheduleTaskAlarm" -> {
                        val id        = call.argument<Int>("id") ?: 0
                        val taskId    = call.argument<String>("taskId") ?: ""
                        val title     = call.argument<String>("title") ?: "Task"
                        val triggerAt = (call.argument<Number>("triggerAtMillis")?.toLong()) ?: 0L
                        val recurrence = call.argument<String>("recurrenceRule") ?: "none"
                        if (taskId.isEmpty() || triggerAt <= 0L) {
                            result.success(false)
                        } else {
                            val scheduled = AlarmSchedulerHelper.schedule(
                                this, id, taskId, title, triggerAt, recurrence)
                            result.success(scheduled)
                        }
                    }

                    "cancelTaskAlarm" -> {
                        val id = call.argument<Int>("id") ?: 0
                        AlarmSchedulerHelper.cancel(this, id)
                        AlarmSchedulerHelper.cancel(this, id + AlarmSchedulerHelper.SNOOZE_OFFSET)
                        result.success(null)
                    }

                    // ── Smart Reminders (autonomous check-ins) ───────────────
                    "scheduleSmartReminders" -> {
                        @Suppress("UNCHECKED_CAST")
                        val rawTimes = (call.argument<List<*>>("times")) ?: emptyList<Any>()
                        val times = rawTimes.mapNotNull { entry ->
                            val map = entry as? Map<*, *> ?: return@mapNotNull null
                            val hour = (map["hour"] as? Number)?.toInt() ?: return@mapNotNull null
                            val minute = (map["minute"] as? Number)?.toInt() ?: 0
                            hour to minute
                        }
                        result.success(SmartReminderScheduler.scheduleAll(this, times))
                    }

                    "cancelSmartReminders" -> {
                        SmartReminderScheduler.cancelAll(this)
                        result.success(true)
                    }

                    // ── Home-screen widget ────────────────────────────────────
                    "updateWidget" -> {
                        InkListWidgetProvider.updateAll(this)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
