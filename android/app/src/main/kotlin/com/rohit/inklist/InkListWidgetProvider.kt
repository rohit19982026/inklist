package com.rohit.inklist

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/**
 * Home-screen widget: today's task count + up to 3 open tasks, sorted by
 * priority then time. Refreshed both periodically by the OS (updatePeriodMillis
 * in inklist_widget_info.xml) and immediately whenever data changes — see
 * MainActivity's "updateWidget" MethodChannel case, called from Dart's
 * DataSync.notifyChanged().
 */
class InkListWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id)
    }

    companion object {
        private const val MAX_ROWS = 3

        fun updateAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, InkListWidgetProvider::class.java))
            for (id in ids) render(context, mgr, id)
        }

        private fun render(context: Context, mgr: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_today)

            val tasks = TodoPrefsHelper.readTodayTasks(context)
            val done = tasks.count { it.done }
            val total = tasks.size
            views.setTextViewText(
                R.id.widget_progress, if (total == 0) "" else "$done of $total done"
            )
            views.setViewVisibility(
                R.id.widget_empty, if (total == 0) View.VISIBLE else View.GONE
            )

            val open = tasks.filter { !it.done }.sortedWith(
                compareBy(
                    { priorityRank(it.priority) },
                    { if (it.hasTime) it.hour * 60 + it.minute else Int.MAX_VALUE },
                )
            )

            val rowIds = intArrayOf(R.id.widget_task_1, R.id.widget_task_2, R.id.widget_task_3)
            for (i in rowIds.indices) {
                if (i < open.size && i < MAX_ROWS) {
                    views.setViewVisibility(rowIds[i], View.VISIBLE)
                    views.setTextViewText(rowIds[i], "•  ${open[i].title}")
                } else {
                    views.setViewVisibility(rowIds[i], View.GONE)
                }
            }

            val extra = open.size - MAX_ROWS
            if (extra > 0) {
                views.setViewVisibility(R.id.widget_more, View.VISIBLE)
                views.setTextViewText(R.id.widget_more, "+$extra more")
            } else {
                views.setViewVisibility(R.id.widget_more, View.GONE)
            }

            val openAppIntent = Intent(context, MainActivity::class.java)
            val pending = PendingIntent.getActivity(
                context, 0, openAppIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)

            mgr.updateAppWidget(widgetId, views)
        }

        private fun priorityRank(p: String) = when (p) {
            "high" -> 0
            "medium" -> 1
            else -> 2
        }
    }
}
