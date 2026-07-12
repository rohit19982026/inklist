package com.rohit.inklist

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.core.content.ContextCompat

/**
 * Shared notification-icon helpers. Android draws the small status-bar icon
 * as a flat alpha mask (see ic_stat_notify.xml) but the large icon shown in
 * the expanded notification is a full bitmap, so the real app icon belongs
 * there instead. R.mipmap.ic_launcher resolves to an adaptive-icon XML on
 * API 26+, which BitmapFactory.decodeResource can't rasterize directly —
 * drawing the resolved Drawable onto a Canvas works for either the legacy
 * flat icon or the adaptive one.
 */
object NotificationIcons {
    const val BRAND_COLOR = 0xFFEF6B52.toInt() // InkList coral

    fun appLargeIcon(context: Context): Bitmap? {
        return try {
            val drawable = ContextCompat.getDrawable(context, R.mipmap.ic_launcher) ?: return null
            val size = 192
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            bitmap
        } catch (_: Exception) {
            null
        }
    }
}
