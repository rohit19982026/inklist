import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/groq_result.dart';
import '../models/weekly_plan_draft.dart';
import '../models/quick_add_draft.dart';
import '../models/todo_task.dart';
import '../models/focus_suggestion.dart';

/// Groq (groq.com) AI integration — the app's only network dependency.
/// Every method degrades gracefully: AI is an enhancement, never a blocker.
/// HTTP-calling methods are thin wrappers around pure `parse*Response`
/// functions so the parsing logic is unit-testable without a live network
/// call or API key.
class GroqService {
  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'llama-3.3-70b-versatile';
  static const _apiKeyPrefKey = 'groq_api_key';
  static const _aiEnabledPrefKey = 'ai_features_enabled';
  static const _dailyBriefCacheKey = 'ai_daily_brief_cache';
  static const _timeout = Duration(seconds: 20);

  // ── Key management ──────────────────────────────────────────────────────
  static Future<String?> getApiKey() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_apiKeyPrefKey);
  }

  static Future<void> setApiKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_apiKeyPrefKey, key.trim());
  }

  static Future<void> clearApiKey() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_apiKeyPrefKey);
  }

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_aiEnabledPrefKey) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_aiEnabledPrefKey, v);
  }

  static Future<bool> get isConfigured async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty && await isEnabled();
  }

  // ── Daily brief cache (avoid burning free-tier quota on every rebuild) ──
  static Future<String?> getCachedDailyBrief() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_dailyBriefCacheKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final cachedDate = j['date'] as String?;
      if (cachedDate != _isoDate(DateTime.now())) return null;
      return j['text'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCachedDailyBrief(String text) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_dailyBriefCacheKey,
        jsonEncode({'date': _isoDate(DateTime.now()), 'text': text}));
  }

  // ── Connectivity check ──────────────────────────────────────────────────
  static Future<GroqResult<bool>> testConnection() async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail('No API key set — add one in Settings');
    }
    final result = await _post(key, [
      {'role': 'user', 'content': 'Reply with the single word: ok'}
    ], jsonMode: false, maxTokens: 5);
    return result.isSuccess
        ? const GroqResult.ok(true)
        : GroqResult.fail(result.error);
  }

  // ── The 4 AI capabilities ───────────────────────────────────────────────

  static Future<GroqResult<WeeklyPlanDraft>> planWeek(String brainDump) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    if (brainDump.trim().isEmpty) {
      return const GroqResult.fail('Describe your week first');
    }
    final now = DateTime.now();
    final weekday = _weekdayName(now.weekday);
    final system = 'You are a personal weekly planner. The user will paste '
        'unstructured notes about their week. Organize them into a JSON '
        'object matching this schema exactly: {"days": {"monday": '
        '[{"title": string, "time": "HH:MM"|null, "priority": '
        '"low"|"medium"|"high"}], "tuesday": [...], "wednesday": [...], '
        '"thursday": [...], "friday": [...], "saturday": [...], "sunday": '
        '[...]}}. Only include days that have tasks. Infer specific times '
        'only when the user implies them; otherwise use null. When '
        'suggesting multiple tasks on the same day, avoid assigning them '
        'the same time slot — spread them across morning, afternoon, and '
        'evening unless the user specified an exact time. Today is '
        '$weekday, ${_isoDate(now)}.';
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': brainDump},
    ], jsonMode: true);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseWeeklyPlanResponse(resp.data!);
  }

  static Future<GroqResult<List<String>>> breakdownTask(
    String title, {
    String? description,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    const system = 'Break this task into 3-7 concrete, actionable subtasks. '
        'Respond with JSON: {"subtasks": [string, string, ...]}.';
    final user = description == null || description.isEmpty
        ? title
        : '$title\n\n$description';
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ], jsonMode: true);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseBreakdownResponse(resp.data!);
  }

  static Future<GroqResult<String>> dailyFocusBrief(
      List<TodoTask> todayAndOverdue) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    if (todayAndOverdue.isEmpty) {
      return const GroqResult.fail('No tasks to summarize');
    }
    const system = 'You are a terse daily-focus assistant. Given today\'s '
        'and overdue tasks (as a JSON list with title/priority/overdue), '
        'write 1-3 short bullet points (each under 15 words) telling the '
        'user what to prioritize today. Be direct, no fluff, no greetings.';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final payload = jsonEncode(todayAndOverdue
        .map((t) => {
              'title': t.title,
              'priority': t.priority,
              'overdue': !t.isRecurring &&
                  DateTime(t.dueDate.year, t.dueDate.month, t.dueDate.day)
                      .isBefore(today),
            })
        .toList());
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': payload},
    ], jsonMode: false);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseDailyBriefResponse(resp.data!);
  }

  static Future<GroqResult<QuickAddDraft>> parseQuickAdd(String freeText) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    if (freeText.trim().isEmpty) {
      return const GroqResult.fail('Type something first');
    }
    final now = DateTime.now();
    final weekday = _weekdayName(now.weekday);
    final system = 'Parse this into a structured task. Respond with JSON: '
        '{"title": string, "dueDate": "yyyy-MM-dd", "time": "HH:MM"|null, '
        '"recurrence": "none"|"daily"|"weekly:MON,..."|"monthly:N"|'
        '"monthly:last", "priority": "low"|"medium"|"high"}. Today is '
        '$weekday, ${_isoDate(now)}. If no date is mentioned, use today. '
        'If a recurring pattern like \'every 1st of the month\' or \'every '
        'Monday\' is mentioned, set recurrence accordingly and set dueDate '
        'to the next occurrence.';
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': freeText},
    ], jsonMode: true);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseQuickAddResponse(resp.data!);
  }

  /// AI focus coach for the Pomodoro tab: given the user's pending tasks,
  /// picks the single best one to work on in the next focus session and
  /// returns a one-line reason. [taskTitle] echoes one of the given titles
  /// (or is empty) so the UI can auto-bind the session to that task.
  static Future<GroqResult<FocusSuggestion>> focusCoach(
      List<TodoTask> candidates) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    if (candidates.isEmpty) {
      return const GroqResult.fail('Add some tasks first, then ask for focus');
    }
    const system = 'You are a focus coach for a 25-minute Pomodoro session. '
        'Given the user\'s pending tasks (a JSON list with title/priority), '
        'pick the single best task to focus on right now. Respond with JSON: '
        '{"task": string, "message": string}. "task" MUST be exactly one of '
        'the given titles verbatim, or "" if none fit. "message" is one '
        'encouraging sentence under 18 words on why to start there. No fluff.';
    final payload = jsonEncode(candidates
        .map((t) => {'title': t.title, 'priority': t.priority})
        .toList());
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': payload},
    ], jsonMode: true);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseFocusCoachResponse(resp.data!);
  }

  // ── Pure parse functions (unit-testable, no network) ────────────────────

  static GroqResult<WeeklyPlanDraft> parseWeeklyPlanResponse(String rawContent) {
    try {
      final j = jsonDecode(rawContent) as Map<String, dynamic>;
      final draft = WeeklyPlanDraft.fromJson(j);
      return GroqResult.ok(draft);
    } catch (_) {
      return const GroqResult.fail(
          'Groq returned an unexpected response — try again or add manually');
    }
  }

  static GroqResult<List<String>> parseBreakdownResponse(String rawContent) {
    try {
      final j = jsonDecode(rawContent) as Map<String, dynamic>;
      final list = (j['subtasks'] as List?) ?? const [];
      final subtasks = list
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (subtasks.isEmpty) {
        return const GroqResult.fail('Groq returned no subtasks — try again');
      }
      return GroqResult.ok(subtasks);
    } catch (_) {
      return const GroqResult.fail(
          'Groq returned an unexpected response — try again or add manually');
    }
  }

  static GroqResult<QuickAddDraft> parseQuickAddResponse(String rawContent) {
    try {
      final j = jsonDecode(rawContent) as Map<String, dynamic>;
      final title = (j['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) {
        return const GroqResult.fail('Could not understand that — try rephrasing');
      }
      return GroqResult.ok(QuickAddDraft.fromJson(j));
    } catch (_) {
      return const GroqResult.fail(
          'Groq returned an unexpected response — try again or add manually');
    }
  }

  static GroqResult<FocusSuggestion> parseFocusCoachResponse(String rawContent) {
    try {
      final j = jsonDecode(rawContent) as Map<String, dynamic>;
      final message = (j['message'] as String?)?.trim() ?? '';
      if (message.isEmpty) {
        return const GroqResult.fail('Groq returned an empty suggestion');
      }
      return GroqResult.ok(FocusSuggestion(
        taskTitle: (j['task'] as String?)?.trim() ?? '',
        message: message,
      ));
    } catch (_) {
      return const GroqResult.fail(
          'Groq returned an unexpected response — pick a task manually');
    }
  }

  static GroqResult<String> parseDailyBriefResponse(String rawContent) {
    final text = rawContent.trim();
    if (text.isEmpty) {
      return const GroqResult.fail('Groq returned an empty brief');
    }
    return GroqResult.ok(text);
  }

  // ── HTTP core ────────────────────────────────────────────────────────────

  /// Returns the model's raw `message.content` string on success.
  static Future<GroqResult<String>> _post(
    String apiKey,
    List<Map<String, String>> messages, {
    required bool jsonMode,
    int maxTokens = 1024,
  }) async {
    try {
      final body = <String, dynamic>{
        'model': _model,
        'messages': messages,
        'temperature': 0.3,
        'max_tokens': maxTokens,
      };
      if (jsonMode) {
        body['response_format'] = {'type': 'json_object'};
      }
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (resp.statusCode == 401) {
        return const GroqResult.fail('Invalid API key — check Settings');
      }
      if (resp.statusCode == 429) {
        return const GroqResult.fail(
            'Rate limited — Groq\'s free tier has a request cap, try again in a minute');
      }
      if (resp.statusCode >= 500) {
        return const GroqResult.fail(
            'Groq is having issues right now — try again or add manually');
      }
      if (resp.statusCode != 200) {
        return const GroqResult.fail(
            'Groq is having issues right now — try again or add manually');
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List?;
      dynamic content;
      if (choices != null && choices.isNotEmpty) {
        final message = choices.first['message'] as Map<String, dynamic>?;
        content = message?['content'];
      }
      if (content is! String || content.isEmpty) {
        return const GroqResult.fail(
            'Groq returned an unexpected response — try again or add manually');
      }
      return GroqResult.ok(content);
    } on SocketException {
      return const GroqResult.fail(
          'No internet connection — you can still add this manually');
    } on TimeoutException {
      return const GroqResult.fail(
          'No internet connection — you can still add this manually');
    } catch (_) {
      return const GroqResult.fail(
          'Groq is having issues right now — try again or add manually');
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _weekdayName(int weekday) => const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
      ][weekday - 1];
}
