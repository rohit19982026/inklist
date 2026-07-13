import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks how often the user actually keeps InkList's AI suggestions
/// (alarm time, priority, habit ideas) versus edits or dismisses them, and
/// by how much — a lightweight, local-only "learning loop" so
/// [GroqService]'s prompts can be told "your suggestions have been running
/// N minutes early" instead of generating in a vacuum every time. Pure
/// bookkeeping: no network, no ML, just a rolling log + aggregate stats.
class AiFeedbackService {
  AiFeedbackService._();

  static const _key = 'ai_feedback_v1';

  // Same bounded-log shape as PomodoroService._maxSessions — plenty of
  // history for a rolling average without unbounded SharedPreferences growth.
  static const _maxEntries = 50;

  // Below this many samples, a percentage/average is noise — omit the key
  // entirely rather than let the AI over-read a tiny sample (same rule
  // BehaviorInsightsService uses for completion rates).
  static const _minSamplesForSignal = 3;

  static Future<void> logAlarmTimeOutcome({
    required bool accepted,
    int? deltaMinutes,
  }) =>
      _append({
        'type': 'alarmTime',
        'accepted': accepted,
        if (deltaMinutes != null) 'deltaMinutes': deltaMinutes,
      });

  static Future<void> logPriorityOutcome({
    required bool accepted,
    String? changedDirection, // "higher" | "lower"
  }) =>
      _append({
        'type': 'priority',
        'accepted': accepted,
        if (changedDirection != null) 'changedDirection': changedDirection,
      });

  static Future<void> logHabitSuggestionOutcome({required bool accepted}) =>
      _append({'type': 'habit', 'accepted': accepted});

  static Future<void> _append(Map<String, dynamic> entry) async {
    final p = await SharedPreferences.getInstance();
    final list = await _readRaw(p)..add(entry);
    final trimmed = list.length > _maxEntries
        ? list.sublist(list.length - _maxEntries)
        : list;
    await p.setString(_key, jsonEncode(trimmed));
  }

  static Future<List<Map<String, dynamic>>> _readRaw(
      SharedPreferences p) async {
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Compact aggregate for feeding into AI prompts as `"feedback"` context.
  /// Each sub-object is omitted entirely if there aren't enough samples yet.
  static Future<Map<String, dynamic>> summarize() async {
    final p = await SharedPreferences.getInstance();
    final entries = await _readRaw(p);
    final out = <String, dynamic>{};

    final alarmEntries =
        entries.where((e) => e['type'] == 'alarmTime').toList();
    if (alarmEntries.length >= _minSamplesForSignal) {
      final accepted = alarmEntries.where((e) => e['accepted'] == true);
      final deltas = alarmEntries
          .map((e) => (e['deltaMinutes'] as num?)?.toInt())
          .whereType<int>()
          .toList();
      out['alarmTimeSuggestions'] = {
        'total': alarmEntries.length,
        'acceptedPercent':
            ((accepted.length / alarmEntries.length) * 100).round(),
        if (deltas.isNotEmpty)
          'avgEditMinutes':
              (deltas.reduce((a, b) => a + b) / deltas.length).round(),
      };
    }

    final priorityEntries =
        entries.where((e) => e['type'] == 'priority').toList();
    if (priorityEntries.length >= _minSamplesForSignal) {
      final accepted = priorityEntries.where((e) => e['accepted'] == true);
      out['prioritySuggestions'] = {
        'total': priorityEntries.length,
        'acceptedPercent':
            ((accepted.length / priorityEntries.length) * 100).round(),
      };
    }

    final habitEntries = entries.where((e) => e['type'] == 'habit').toList();
    if (habitEntries.length >= _minSamplesForSignal) {
      final accepted = habitEntries.where((e) => e['accepted'] == true);
      out['habitSuggestions'] = {
        'total': habitEntries.length,
        'acceptedPercent':
            ((accepted.length / habitEntries.length) * 100).round(),
      };
    }

    return out;
  }
}
