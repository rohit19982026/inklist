package com.rohit.inklist

import android.content.Context
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri

/**
 * Lists Android's built-in notification-type system sounds (deliberately
 * TYPE_NOTIFICATION, not TYPE_ALARM — notification tones tend to be short,
 * gentle chimes rather than the loud, jarring tones alarm-type sounds are
 * designed to be, which is what "soothing, not a wake-up alarm" calls for)
 * and previews them on demand. The exact set is device/OEM-dependent — this
 * just surfaces whatever's already installed rather than bundling audio.
 */
object AlarmToneHelper {
    private var previewing: Ringtone? = null

    fun listTones(context: Context): List<Map<String, String>> {
        val manager = RingtoneManager(context).apply {
            setType(RingtoneManager.TYPE_NOTIFICATION)
        }
        val cursor = manager.cursor
        val out = mutableListOf<Map<String, String>>()
        while (cursor.moveToNext()) {
            val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
            val uri = manager.getRingtoneUri(cursor.position)
            out.add(mapOf("uri" to uri.toString(), "title" to title))
        }
        return out
    }

    fun preview(context: Context, uriString: String) {
        stopPreview()
        val ringtone = try {
            RingtoneManager.getRingtone(context, Uri.parse(uriString))
        } catch (_: Exception) {
            null
        }
        previewing = ringtone
        ringtone?.play()
    }

    fun stopPreview() {
        previewing?.let { if (it.isPlaying) it.stop() }
        previewing = null
    }
}
