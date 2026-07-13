import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One selectable alarm/notification tone — [uri] is the Android content://
/// URI RingtoneManager gave us, [title] is its display name on-device.
class AlarmTone {
  final String uri;
  final String title;
  const AlarmTone({required this.uri, required this.title});
}

/// Thin MethodChannel wrapper around AlarmToneHelper.kt, plus the persisted
/// selection. One tone setting covers both the task alarm (played directly
/// via MediaPlayer) and the Smart Reminders notification channel (which
/// recreates itself when the selection changes — see
/// SmartReminderService.ensureChannelWithTone) — see AlarmRingingService.kt
/// and SmartReminderService.kt for how each side actually consumes this.
class AlarmToneService {
  static const _methods = MethodChannel('com.rohit.inklist/methods');
  static const _uriKey = 'alarm_tone_uri';
  static const _titleKey = 'alarm_tone_title';

  static Future<String?> getSelectedUri() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_uriKey);
  }

  static Future<String> getSelectedTitle() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_titleKey) ?? 'Default';
  }

  static Future<void> setSelectedTone(AlarmTone tone) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_uriKey, tone.uri);
    await p.setString(_titleKey, tone.title);
  }

  /// Returns an empty list if the platform call fails — the picker screen
  /// just shows nothing to choose rather than crashing.
  static Future<List<AlarmTone>> listAvailableTones() async {
    try {
      final raw = await _methods.invokeMethod<List<dynamic>>('listAlarmTones');
      if (raw == null) return [];
      return raw
          .whereType<Map>()
          .map((m) => AlarmTone(
                uri: m['uri'] as String? ?? '',
                title: m['title'] as String? ?? 'Tone',
              ))
          .where((t) => t.uri.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> previewTone(String uri) async {
    try {
      await _methods.invokeMethod('previewTone', {'uri': uri});
    } catch (_) {}
  }

  static Future<void> stopPreview() async {
    try {
      await _methods.invokeMethod('stopTonePreview');
    } catch (_) {}
  }
}
