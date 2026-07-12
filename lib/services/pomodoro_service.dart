import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pomodoro.dart';

/// Persistence for the Pomodoro tab: the user's [PomodoroConfig], the rolling
/// session log (`pomodoro_sessions_v1`), and a snapshot of any in-flight timer
/// so it can be restored after the app process is killed and relaunched.
///
/// The running countdown itself lives in the screen's State (a 1-second
/// Timer); this service only owns durable state.
class PomodoroService {
  static const _configKey = 'pomodoro_config_v1';
  static const _sessionsKey = 'pomodoro_sessions_v1';
  static const _activeKey = 'pomodoro_active_v1';

  // Keep the log bounded — plenty for a "sessions today" count and a
  // reasonable history without unbounded SharedPreferences growth.
  static const _maxSessions = 500;

  // ── Config ──────────────────────────────────────────────────────────────
  static Future<PomodoroConfig> getConfig() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_configKey);
    if (raw == null) return PomodoroConfig.classic;
    try {
      return PomodoroConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return PomodoroConfig.classic;
    }
  }

  static Future<void> setConfig(PomodoroConfig config) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_configKey, jsonEncode(config.toJson()));
  }

  // ── Session log ─────────────────────────────────────────────────────────
  static Future<List<PomodoroSession>> getSessions() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_sessionsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => PomodoroSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> logSession(PomodoroSession session) async {
    final p = await SharedPreferences.getInstance();
    final list = await getSessions()..add(session);
    // Trim oldest first if we've exceeded the cap.
    final trimmed =
        list.length > _maxSessions ? list.sublist(list.length - _maxSessions) : list;
    await p.setString(
        _sessionsKey, jsonEncode(trimmed.map((s) => s.toJson()).toList()));
  }

  /// Count/minutes of focus (work) sessions completed on [day] (default today).
  static Future<({int count, int minutes})> summaryFor(
      {DateTime? day}) async {
    final d = day ?? DateTime.now();
    final sessions = await getSessions();
    var count = 0, minutes = 0;
    for (final s in sessions) {
      if (_sameDay(s.completedAt, d)) {
        count++;
        minutes += s.minutes;
      }
    }
    return (count: count, minutes: minutes);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── Active-timer snapshot (survives process death) ──────────────────────
  static Future<void> saveActive(ActiveTimer active) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_activeKey, jsonEncode(active.toJson()));
  }

  static Future<ActiveTimer?> getActive() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_activeKey);
    if (raw == null) return null;
    try {
      return ActiveTimer.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearActive() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_activeKey);
  }
}

/// Durable snapshot of a running/paused timer. When [running] is true the
/// truth is [endsAtMillis] (wall-clock end); when paused it's
/// [remainingSeconds]. This lets a resumed app recompute the countdown or
/// detect that the phase already elapsed while it was away.
class ActiveTimer {
  final PomodoroPhase phase;
  final bool running;
  final int endsAtMillis; // valid when running
  final int remainingSeconds; // valid when paused
  final int completedWorkRounds;
  final String? taskTitle;

  const ActiveTimer({
    required this.phase,
    required this.running,
    required this.endsAtMillis,
    required this.remainingSeconds,
    required this.completedWorkRounds,
    this.taskTitle,
  });

  Map<String, dynamic> toJson() => {
        'phase': phase.storageKey,
        'running': running,
        'endsAt': endsAtMillis,
        'remaining': remainingSeconds,
        'rounds': completedWorkRounds,
        'task': taskTitle,
      };

  factory ActiveTimer.fromJson(Map<String, dynamic> j) => ActiveTimer(
        phase: PomodoroPhaseX.fromStorage(j['phase'] as String?),
        running: j['running'] as bool? ?? false,
        endsAtMillis: (j['endsAt'] as num?)?.toInt() ?? 0,
        remainingSeconds: (j['remaining'] as num?)?.toInt() ?? 0,
        completedWorkRounds: (j['rounds'] as num?)?.toInt() ?? 0,
        taskTitle: j['task'] as String?,
      );
}
