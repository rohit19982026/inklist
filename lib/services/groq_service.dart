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
  static const _weeklyReviewCacheKey = 'ai_weekly_review_cache';
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

  // ── Weekly review cache (keyed by ISO week, not date, so it persists all
  // week once generated rather than regenerating every day) ───────────────
  static Future<String?> getCachedWeeklyReview() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_weeklyReviewCacheKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final cachedWeek = j['week'] as String?;
      if (cachedWeek != _isoWeekKey(DateTime.now())) return null;
      return j['text'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCachedWeeklyReview(String text) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_weeklyReviewCacheKey,
        jsonEncode({'week': _isoWeekKey(DateTime.now()), 'text': text}));
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
    List<TodoTask> todayAndOverdue, {
    Map<String, dynamic>? behaviorContext,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    if (todayAndOverdue.isEmpty) {
      return const GroqResult.fail('No tasks to summarize');
    }
    const system = 'You are a terse daily-focus assistant. Given today\'s '
        'and overdue tasks (a JSON list with title/priority/overdue) and, '
        'when present, a "behavior" object summarizing the user\'s actual '
        'completion patterns over the last ~2 weeks (completion rates by '
        'weekday/priority, recurring tasks that keep getting missed, habit '
        'streaks, focus-session activity), write 1-3 short bullet points '
        '(each under 15 words) telling the user what to prioritize today. '
        'If "behavior" reveals something specific and relevant — a weak '
        'weekday, a task that keeps getting missed, a strong habit streak '
        '— call it out by name instead of generic advice. If "behavior" is '
        'absent or too thin to say anything specific, just give a direct '
        'read of today\'s tasks. Be direct, no fluff, no greetings.';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final payload = jsonEncode({
      'tasks': todayAndOverdue
          .map((t) => {
                'title': t.title,
                'priority': t.priority,
                'overdue': !t.isRecurring &&
                    DateTime(t.dueDate.year, t.dueDate.month, t.dueDate.day)
                        .isBefore(today),
              })
          .toList(),
      if (behaviorContext != null && behaviorContext.isNotEmpty)
        'behavior': behaviorContext,
    });
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': payload},
    ], jsonMode: false);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseDailyBriefResponse(resp.data!);
  }

  /// A short weekly-review narrative built entirely from [behaviorContext]
  /// (the same 14-day snapshot every other behavior-aware feature uses) —
  /// no task list needed, since the point is reflecting on the week's
  /// patterns rather than today's to-dos.
  static Future<GroqResult<String>> weeklyRetrospective(
    Map<String, dynamic> behaviorContext,
  ) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    if (behaviorContext.length <= 1) {
      // Only windowDays present — nothing to reflect on yet.
      return const GroqResult.fail('Not enough history yet for a weekly review');
    }
    const system = 'You are writing a short weekly review for a personal '
        'to-do app, based on a "behavior" object summarizing the user\'s '
        'actual patterns over the last ~2 weeks (completion rates '
        'overall/by weekday/by priority, recurring tasks that keep getting '
        'missed, habit streaks, focus-session activity). Write 3-5 '
        'sentences that read like a real reflection, not generic '
        'encouragement — cite specific numbers or named patterns from the '
        'data (e.g. a completion-rate change, a specific chronically-'
        'missed task, a habit streak). If the data is thin, keep it '
        'short and honest rather than padding with fluff. No greetings, '
        'no sign-off.';
    final payload = jsonEncode({'behavior': behaviorContext});
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': payload},
    ], jsonMode: false);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseDailyBriefResponse(resp.data!);
  }

  /// Parses free text into one or more structured tasks — e.g. "buy milk,
  /// call mom tomorrow, and finish the report by Friday" becomes 3 separate
  /// drafts rather than being mangled into one.
  static Future<GroqResult<List<QuickAddDraft>>> parseQuickAddMulti(
      String freeText) async {
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
    final system = 'Parse this into one or more structured tasks. Split on '
        'commas, "and", or line breaks when the text clearly describes '
        'more than one task — e.g. "buy milk, call mom tomorrow, and '
        'finish the report by Friday" is 3 tasks, not 1. Respond with '
        'JSON: {"tasks": [{"title": string, "dueDate": "yyyy-MM-dd", '
        '"time": "HH:MM"|null, "recurrence": "none"|"daily"|'
        '"weekly:MON,..."|"monthly:N"|"monthly:last", "priority": '
        '"low"|"medium"|"high"}, ...]}. Today is $weekday, '
        '${_isoDate(now)}. If no date is mentioned for a task, use today. '
        'If a recurring pattern like \'every 1st of the month\' or \'every '
        'Monday\' is mentioned, set recurrence accordingly and set dueDate '
        'to the next occurrence.';
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': freeText},
    ], jsonMode: true);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseQuickAddMultiResponse(resp.data!);
  }

  /// AI focus coach for the Pomodoro tab: given the user's pending tasks,
  /// picks the single best one to work on in the next focus session and
  /// returns a one-line reason. [taskTitle] echoes one of the given titles
  /// (or is empty) so the UI can auto-bind the session to that task.
  static Future<GroqResult<FocusSuggestion>> focusCoach(
    List<TodoTask> candidates, {
    Map<String, dynamic>? behaviorContext,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    if (candidates.isEmpty) {
      return const GroqResult.fail('Add some tasks first, then ask for focus');
    }
    const system = 'You are a focus coach for a 25-minute Pomodoro session. '
        'Given the user\'s pending tasks (a JSON list with title/priority) '
        'and, when present, a "behavior" object with their actual recent '
        'focus-session activity (pomodoroTopFocusedTasks — titles they\'ve '
        'already been putting session time into) and completion patterns, '
        'pick the single best task to focus on right now. Prefer a task '
        'they\'ve already started focusing on recently (in '
        'pomodoroTopFocusedTasks) to help them finish it, unless a higher-'
        'priority task clearly needs attention first. Respond with JSON: '
        '{"task": string, "message": string}. "task" MUST be exactly one of '
        'the given titles verbatim, or "" if none fit. "message" is one '
        'encouraging sentence under 18 words on why to start there — '
        'reference the specific pattern (e.g. "you\'ve already put time '
        'into this") when it applies. No fluff.';
    final payload = jsonEncode({
      'tasks': candidates
          .map((t) => {'title': t.title, 'priority': t.priority})
          .toList(),
      if (behaviorContext != null && behaviorContext.isNotEmpty)
        'behavior': behaviorContext,
    });
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': payload},
    ], jsonMode: true);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseFocusCoachResponse(resp.data!);
  }

  /// A short, punchy congratulatory line shown in the celebration overlay
  /// when a Pomodoro work session completes. Cheap and fast by design (this
  /// is a nice-to-have swap-in, not something the celebration should ever
  /// wait on) — the caller always has an instant local fallback message
  /// ready before this resolves.
  static Future<GroqResult<String>> pomodoroCelebrationMessage({
    required String taskTitle,
    required int completedRoundsToday,
    Map<String, dynamic>? behaviorContext,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    const system = 'The user just finished a 25-minute focus session in a '
        'Pomodoro app. Write ONE short, punchy, celebratory sentence (under '
        '14 words) congratulating them — energetic, like a small win, not '
        'corporate or flowery. Reference the task title or session count '
        'naturally if it fits (e.g. a 3rd session on the same task today is '
        'genuine momentum worth calling out); otherwise just celebrate the '
        'session itself. No emoji, no quotes, no sign-off. Respond ONLY '
        'with JSON: {"message": string}.';
    final payload = jsonEncode({
      if (taskTitle.isNotEmpty) 'taskTitle': taskTitle,
      'completedRoundsToday': completedRoundsToday,
      if (behaviorContext != null && behaviorContext.isNotEmpty)
        'behavior': behaviorContext,
    });
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': payload},
    ], jsonMode: true, maxTokens: 40);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parsePomodoroCelebrationResponse(resp.data!);
  }

  /// AI habit ideas for the Habits tab. Given the habits the user already
  /// tracks, suggests a handful of complementary, concrete daily habits.
  static Future<GroqResult<List<String>>> suggestHabits(
    List<String> existingTitles, {
    Map<String, dynamic>? behaviorContext,
    Map<String, dynamic>? feedbackContext,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    final existing = existingTitles.isEmpty
        ? 'none yet'
        : existingTitles.join(', ');
    final system = 'You suggest daily habits for a habit tracker. The user '
        'already tracks: $existing. The user message may include a '
        '"behavior" object with "habitStreaks" (title/streak/completion '
        'rate for their existing habits) and task-completion patterns, and '
        'a "feedback" object showing how often past habit suggestions were '
        'actually adopted ("habitSuggestions": {total, acceptedPercent}) — '
        'if acceptedPercent is low, suggestions have been missing the mark, '
        'so lean toward smaller/easier/more concrete ideas. If a tracked '
        'habit has a low completion rate, suggest something easier or '
        'differently-timed as a complement rather than piling on more of '
        'the same difficulty; if their streaks are strong, feel free to '
        'suggest something a bit more ambitious. Suggest 5 concrete, '
        'specific, doable daily habits that complement what they already '
        'track without duplicating them. Keep each under 4 words, '
        'action-oriented (e.g. "Drink 2L water", "Read 10 pages"). Respond '
        'ONLY with JSON: {"habits": [string, ...]}.';
    final hasContext = (behaviorContext != null && behaviorContext.isNotEmpty) ||
        (feedbackContext != null && feedbackContext.isNotEmpty);
    final userContent = hasContext
        ? jsonEncode({
            if (behaviorContext != null && behaviorContext.isNotEmpty)
              'behavior': behaviorContext,
            if (feedbackContext != null && feedbackContext.isNotEmpty)
              'feedback': feedbackContext,
          })
        : 'Suggest habits.';
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': userContent},
    ], jsonMode: true);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseHabitSuggestions(resp.data!);
  }

  /// AI-suggested alarm time for a task the user hasn't picked a time for.
  /// Purely an enhancement in front of the app's own fallback (see
  /// TodoEditorSheet._defaultAlarmTime) — never blocks task creation, and a
  /// manual time pick always overrides whatever this suggests.
  static Future<GroqResult<TimeOfDayMs>> suggestAlarmTime({
    required String title,
    String? description,
    required String priority,
    required DateTime dueDate,
    required String recurrenceRule,
    Map<String, dynamic>? behaviorContext,
    Map<String, dynamic>? feedbackContext,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    const system = 'Suggest a single good time of day for a reminder alarm '
        'for this task, based on what it likely involves — e.g. "Morning '
        'run" implies early morning, "Read before bed" implies evening, '
        '"Team meeting" implies typical business hours. If nothing about '
        'the task implies a time, default to a reasonable mid-morning time '
        '(e.g. 9:00-10:00). The user message may include a "behavior" '
        'object with the user\'s actual completion patterns (completion '
        'rates by weekday, habit streaks) — use it as a secondary signal '
        'only when relevant, never override an obvious semantic cue from '
        'the title. It may also include a "feedback" object '
        '("alarmTimeSuggestions": {total, acceptedPercent, avgEditMinutes}) '
        'showing how past suggestions of this kind were received — if '
        'avgEditMinutes shows a consistent bias (e.g. users move suggested '
        'times ~30 minutes later), shift your default accordingly. Respond '
        'ONLY with JSON: {"hour": 0-23, "minute": 0-59}.';
    final payload = jsonEncode({
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'priority': priority,
      'dueWeekday': _weekdayName(dueDate.weekday),
      'recurrence': recurrenceRule,
      if (behaviorContext != null && behaviorContext.isNotEmpty)
        'behavior': behaviorContext,
      if (feedbackContext != null && feedbackContext.isNotEmpty)
        'feedback': feedbackContext,
    });
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': payload},
    ], jsonMode: true, maxTokens: 60);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parseAlarmTimeResponse(resp.data!);
  }

  /// AI-suggested priority for a brand-new task, mirroring
  /// [suggestAlarmTime]'s "enhancement in front of a sensible default"
  /// design — a manual pick always overrides this, and it's never offered
  /// when editing an existing task (an established priority shouldn't be
  /// second-guessed).
  static Future<GroqResult<String>> suggestPriority({
    required String title,
    String? description,
    required DateTime dueDate,
    Map<String, dynamic>? behaviorContext,
    Map<String, dynamic>? feedbackContext,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return const GroqResult.fail(
          'Add your Groq API key in Settings to use AI features');
    }
    const system = 'Suggest a priority ("low", "medium", or "high") for '
        'this task based on what it likely involves — bills, deadlines, '
        'health/safety, and time-sensitive commitments lean high; routine '
        'chores and open-ended items lean low; default to medium when '
        'unclear. The user message may include a "behavior" object with '
        'completion patterns by priority, and a "feedback" object '
        '("prioritySuggestions": {total, acceptedPercent}) showing how '
        'often past suggestions were kept as-is — if acceptedPercent is '
        'low, be more conservative and default to medium more often. '
        'Respond ONLY with JSON: {"priority": "low"|"medium"|"high"}.';
    final payload = jsonEncode({
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'dueWeekday': _weekdayName(dueDate.weekday),
      if (behaviorContext != null && behaviorContext.isNotEmpty)
        'behavior': behaviorContext,
      if (feedbackContext != null && feedbackContext.isNotEmpty)
        'feedback': feedbackContext,
    });
    final resp = await _post(key, [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': payload},
    ], jsonMode: true, maxTokens: 20);
    if (!resp.isSuccess) return GroqResult.fail(resp.error);
    return parsePriorityResponse(resp.data!);
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

  static GroqResult<List<QuickAddDraft>> parseQuickAddMultiResponse(
      String rawContent) {
    try {
      final j = jsonDecode(rawContent) as Map<String, dynamic>;
      final list = (j['tasks'] as List?) ?? const [];
      final drafts = list
          .whereType<Map<String, dynamic>>()
          .map(QuickAddDraft.fromJson)
          .where((d) => d.title.isNotEmpty)
          .toList();
      if (drafts.isEmpty) {
        return const GroqResult.fail('Could not understand that — try rephrasing');
      }
      return GroqResult.ok(drafts);
    } catch (_) {
      return const GroqResult.fail(
          'Groq returned an unexpected response — try again or add manually');
    }
  }

  static GroqResult<String> parsePriorityResponse(String rawContent) {
    try {
      final j = jsonDecode(rawContent) as Map<String, dynamic>;
      final priority = (j['priority'] as String?)?.trim().toLowerCase();
      if (priority != 'low' && priority != 'medium' && priority != 'high') {
        return const GroqResult.fail('Groq returned an invalid priority');
      }
      return GroqResult.ok(priority);
    } catch (_) {
      return const GroqResult.fail(
          'Groq returned an unexpected response — try again or pick manually');
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

  static GroqResult<String> parsePomodoroCelebrationResponse(String rawContent) {
    try {
      final j = jsonDecode(rawContent) as Map<String, dynamic>;
      final message = (j['message'] as String?)?.trim() ?? '';
      if (message.isEmpty) {
        return const GroqResult.fail('Groq returned an empty message');
      }
      return GroqResult.ok(message);
    } catch (_) {
      return const GroqResult.fail(
          'Groq returned an unexpected response');
    }
  }

  static GroqResult<List<String>> parseHabitSuggestions(String rawContent) {
    try {
      final j = jsonDecode(rawContent) as Map<String, dynamic>;
      final list = (j['habits'] as List?) ?? const [];
      final habits = list
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (habits.isEmpty) {
        return const GroqResult.fail('Groq returned no habits — try again');
      }
      return GroqResult.ok(habits);
    } catch (_) {
      return const GroqResult.fail(
          'Groq returned an unexpected response — try again or add manually');
    }
  }

  static GroqResult<TimeOfDayMs> parseAlarmTimeResponse(String rawContent) {
    try {
      final j = jsonDecode(rawContent) as Map<String, dynamic>;
      final hour = (j['hour'] as num?)?.toInt();
      if (hour == null || hour < 0 || hour > 23) {
        return const GroqResult.fail('Groq returned an invalid time');
      }
      final minute = ((j['minute'] as num?)?.toInt() ?? 0).clamp(0, 59);
      return GroqResult.ok(TimeOfDayMs(hour: hour, minute: minute));
    } catch (_) {
      return const GroqResult.fail(
          'Groq returned an unexpected response — try again or pick a time');
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

  /// A stable "year-Www" key identifying [date]'s ISO-8601 week — only
  /// needs to be internally consistent (same week in → same key out) for
  /// cache purposes, not a certified ISO week-numbering implementation.
  static String _isoWeekKey(DateTime date) {
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final ordinalDay =
        thursday.difference(DateTime(thursday.year, 1, 1)).inDays + 1;
    final week = ((ordinalDay - 1) / 7).floor() + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }
}
