import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/todo_task.dart';
import '../services/todo_service.dart';
import '../services/data_sync.dart';
import '../services/groq_service.dart';
import '../services/alarm_scheduler_service.dart';
import '../services/behavior_insights_service.dart';
import '../services/habit_service.dart';
import '../services/pomodoro_service.dart';
import '../services/google_calendar_service.dart';
import '../models/calendar_event.dart';
import '../widgets/todo_editor_sheet.dart';
import '../widgets/nl_quick_add_sheet.dart';
import '../widgets/ink_widgets.dart';
import '../widgets/alarm_feedback.dart';
import 'weekly_plan_preview_screen.dart';
import 'settings_screen.dart';

/// InkList "Today" — a handwritten daily planner. Tasks are grouped into
/// priority buckets (Overdue → Top Priorities → Must Do → If I Have Time),
/// with a schedule strip for anything that has a time, a progress sheet, and
/// the AI daily-focus note on top.
class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});
  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> with WidgetsBindingObserver {
  bool _loading = true;
  List<TodoTask> _all = const [];
  String? _brief;
  bool _briefLoading = false;
  bool _aiConfigured = false;
  List<CalendarEvent> _calendarEvents = const [];

  @override
  void initState() {
    super.initState();
    _load();
    DataSync.listenable.addListener(_onDataChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    DataSync.listenable.removeListener(_onDataChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final all = await TodoService.getAll();
    final configured = await GroqService.isConfigured;
    final cachedBrief = configured ? await GroqService.getCachedDailyBrief() : null;
    final events = await _loadTodayCalendarEvents();
    if (!mounted) return;
    setState(() {
      _all = all;
      _aiConfigured = configured;
      _brief = cachedBrief;
      _calendarEvents = events;
      _loading = false;
    });
  }

  /// Empty list unless the user has both enabled and signed in to Calendar
  /// sync — never blocks the rest of Today from loading (see
  /// GoogleCalendarService's graceful-degradation contract).
  Future<List<CalendarEvent>> _loadTodayCalendarEvents() async {
    if (!GoogleCalendarService.isConfigured) return const [];
    if (!await GoogleCalendarService.isSyncEnabled()) return const [];
    if (!await GoogleCalendarService.isSignedIn()) return const [];
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return GoogleCalendarService.fetchEventsForRange(start, end);
  }

  Future<void> _refreshDailyBrief() async {
    if (_briefLoading) return;
    setState(() => _briefLoading = true);
    final now = DateTime.now();
    final tasks = [
      ...TodoService.tasksForDay(_all, now),
      ...TodoService.overdueTasks(_all, asOf: now),
    ];
    final habits = await HabitService.getAll();
    final sessions = await PomodoroService.getSessions();
    final behaviorContext = BehaviorInsightsService.summarize(
      tasks: _all,
      habits: habits,
      sessions: sessions,
      now: now,
    );
    final result = await GroqService.dailyFocusBrief(
      tasks,
      behaviorContext: behaviorContext,
    );
    if (!mounted) return;
    setState(() => _briefLoading = false);
    if (result.isSuccess) {
      setState(() => _brief = result.data);
      await GroqService.setCachedDailyBrief(result.data!);
    }
  }

  Future<void> _persist(TodoTask t) async {
    await TodoService.upsert(t);
    final ok = await AlarmSchedulerService.syncTaskAlarm(t);
    DataSync.notifyChanged();
    if (mounted) await showAlarmSchedulingFeedback(context, t, ok);
  }

  Future<void> _openQuickAdd() async {
    final t = await NlQuickAddSheet.show(context);
    if (t != null) await _persist(t);
  }

  Future<void> _openPlanMyWeek() async => showWeeklyPlanFlow(context);

  Future<void> _create() async {
    final t = await TodoEditorSheet.show(context);
    if (t != null) await _persist(t);
  }

  Future<void> _edit(TodoTask t) async {
    final updated = await TodoEditorSheet.show(context, existing: t);
    if (updated != null) await _persist(updated);
  }

  Future<void> _toggle(TodoTask t, DateTime day) async {
    HapticFeedback.lightImpact();
    await TodoService.toggleOccurrence(t.id, day);
    DataSync.notifyChanged();
  }

  Future<void> _delete(TodoTask t) async {
    HapticFeedback.mediumImpact();
    await TodoService.delete(t.id);
    await AlarmSchedulerService.cancelTaskAlarm(t.id);
    DataSync.notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    final now = DateTime.now();
    final overdue = TodoService.overdueTasks(_all, asOf: now);
    final today = TodoService.tasksForDay(_all, now);
    final done = today.where((t) => t.isCompletedOn(now)).length;

    // Priority buckets among today's tasks.
    final high = today.where((t) => t.priority == 'high').toList();
    final medium = today.where((t) => t.priority == 'medium').toList();
    final low = today.where((t) => t.priority == 'low').toList();

    // Timed tasks (today) for the schedule strip.
    final timed = today.where((t) => t.alarmTime != null).toList()
      ..sort((a, b) {
        final am = a.alarmTime!.hour * 60 + a.alarmTime!.minute;
        final bm = b.alarmTime!.hour * 60 + b.alarmTime!.minute;
        return am.compareTo(bm);
      });

    final nothingAtAll = today.isEmpty && overdue.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(now)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                sliver: SliverToBoxAdapter(child: _progressSheet(done, today.length)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(child: _focusNote()),
              ),
              if (timed.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  sliver: SliverToBoxAdapter(child: _scheduleSheet(timed, now)),
                ),
              if (_calendarEvents.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  sliver: SliverToBoxAdapter(child: _calendarSheet()),
                ),
              if (nothingAtAll)
                SliverToBoxAdapter(child: _emptyState())
              else ...[
                ..._bucket('Overdue', overdue, now,
                    AppColors.hlPeach, AppColors.danger, Icons.error_outline_rounded),
                ..._bucket('Top Priorities', high, now,
                    AppColors.hlPink, AppColors.danger, Icons.star_rounded),
                ..._bucket('Must Do Today', medium, now,
                    AppColors.hlYellow, AppColors.warning, Icons.bolt_rounded),
                ..._bucket('If I Have Time', low, now,
                    AppColors.hlMint, AppColors.success, Icons.eco_rounded),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'todo_quick_add',
            mini: true,
            elevation: 2,
            onPressed: _openQuickAdd,
            backgroundColor: AppColors.accent,
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'todo_new_task',
            onPressed: _create,
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text('New Task',
                style: T.body(c: Colors.white).copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _header(DateTime now) {
    final h = now.hour;
    final greeting = h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: T.largeTitle()),
                const SizedBox(height: 2),
                Text(DateFormat('EEEE, d MMMM').format(now),
                    style: T.body(c: AppColors.textSecondary)),
              ],
            ),
          ),
          _roundIconButton(Icons.auto_awesome_rounded, _openPlanMyWeek,
              tint: AppColors.accent, tooltip: 'Plan my week'),
          const SizedBox(width: 8),
          _roundIconButton(Icons.settings_rounded, () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()));
          }, tint: AppColors.textSecondary, tooltip: 'Settings'),
        ],
      ),
    );
  }

  Widget _roundIconButton(IconData icon, VoidCallback onTap,
      {required Color tint, String? tooltip}) {
    final btn = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.card,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: IconButton(
        icon: Icon(icon, color: tint, size: 20),
        onPressed: onTap,
        padding: EdgeInsets.zero,
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  // ── Progress sheet ─────────────────────────────────────────────────────────
  Widget _progressSheet(int done, int total) {
    final pct = total > 0 ? done / total : 0.0;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HighlighterLabel('Today\'s progress', color: AppColors.hlYellow),
              const SizedBox(height: 10),
              Text(
                total == 0 ? 'Nothing scheduled yet' : '$done of $total done',
                style: T.title2(),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 58,
          height: 58,
          child: Stack(alignment: Alignment.center, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CircularProgressIndicator(
                value: total == 0 ? 0 : v,
                strokeWidth: 6,
                backgroundColor: AppColors.fill,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            Text('${(pct * 100).round()}%',
                style: T.title3().copyWith(fontSize: 18)),
          ]),
        ),
      ]),
    );
  }

  // ── AI daily focus ─────────────────────────────────────────────────────────
  Widget _focusNote() {
    if (!_aiConfigured) {
      return PaperCard(
        color: AppColors.overlay,
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Add your free Groq key in Settings for an AI daily brief',
                style: T.footnote()),
          ),
          TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
            child: Text('Settings',
                style: T.footnote(c: AppColors.primary).copyWith(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }
    return StickyNote(
      color: AppColors.hlLavender,
      tilt: -0.012,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('Daily focus', style: T.title3().copyWith(fontSize: 22)),
            const Spacer(),
            if (_briefLoading)
              const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
            else
              GestureDetector(
                onTap: _refreshDailyBrief,
                child: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.textSecondary),
              ),
          ]),
          const SizedBox(height: 6),
          Text(_brief ?? 'Tap refresh to get today\'s priorities',
              style: T.body(c: AppColors.textPrimary).copyWith(height: 1.35)),
        ],
      ),
    );
  }

  // ── Schedule strip (timed tasks) ────────────────────────────────────────────
  Widget _scheduleSheet(List<TodoTask> timed, DateTime now) {
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HighlighterLabel('Today\'s schedule',
              color: AppColors.hlSky, icon: Icons.schedule_rounded),
          const SizedBox(height: 12),
          ...timed.map((t) {
            final done = t.isCompletedOn(now);
            final time = TimeOfDay(hour: t.alarmTime!.hour, minute: t.alarmTime!.minute)
                .format(context);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 66,
                  child: Text(time,
                      style: T.footnote(c: AppColors.textSecondary)
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 10),
                  child: Icon(
                    t.alarmEnabled ? Icons.alarm_rounded : Icons.circle_outlined,
                    size: 14,
                    color: t.alarmEnabled ? AppColors.primary : AppColors.textHint,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _edit(t),
                    child: Text(t.title,
                        style: T.body().copyWith(
                            decoration: done ? TextDecoration.lineThrough : null,
                            color: done ? AppColors.textMuted : AppColors.textPrimary)),
                  ),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }

  // ── Google Calendar events (read-only import) ───────────────────────────────
  Widget _calendarSheet() {
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HighlighterLabel('From your calendar',
              color: AppColors.hlLavender, icon: Icons.event_rounded),
          const SizedBox(height: 12),
          ..._calendarEvents.map((e) {
            final timeLabel = e.allDay
                ? 'All day'
                : TimeOfDay.fromDateTime(e.start).format(context);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 66,
                  child: Text(timeLabel,
                      style: T.footnote(c: AppColors.textSecondary)
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 2, right: 10),
                  child: Icon(Icons.event_rounded,
                      size: 14, color: AppColors.accent),
                ),
                Expanded(child: Text(e.title, style: T.body())),
              ]),
            );
          }),
        ],
      ),
    );
  }

  // ── Priority bucket ─────────────────────────────────────────────────────────
  List<Widget> _bucket(String title, List<TodoTask> tasks, DateTime forDay,
      Color hl, Color accent, IconData icon) {
    if (tasks.isEmpty) return const [];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Row(children: [
            HighlighterLabel(title, color: hl, icon: icon),
            const SizedBox(width: 8),
            Text('${tasks.length}',
                style: T.body(c: AppColors.textMuted).copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _taskCard(tasks[i], forDay, accent: accent, index: i),
            childCount: tasks.length,
          ),
        ),
      ),
    ];
  }

  // ── Task card ───────────────────────────────────────────────────────────────
  Widget _taskCard(TodoTask t, DateTime forDay, {required Color accent, int index = 0}) {
    final done = t.isCompletedOn(forDay);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('${t.id}_${forDay.millisecondsSinceEpoch}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: AppColors.danger,
            borderRadius: BorderRadius.circular(Radii.xl),
          ),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        onDismissed: (_) => _delete(t),
        child: PaperCard(
          padding: const EdgeInsets.all(14),
          onTap: () => _edit(t),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 1, right: 12),
                child: InkCheckbox(
                  value: done,
                  onChanged: (_) => _toggle(t, forDay),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        style: T.body().copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            decoration: done ? TextDecoration.lineThrough : null,
                            color: done ? AppColors.textMuted : AppColors.textPrimary)),
                    if (_hasMeta(t)) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        if (t.alarmTime != null)
                          _metaChip(
                            TimeOfDay(hour: t.alarmTime!.hour, minute: t.alarmTime!.minute)
                                .format(context),
                            icon: t.alarmEnabled ? Icons.alarm_rounded : Icons.schedule_rounded,
                            iconColor: t.alarmEnabled ? AppColors.primary : null,
                          ),
                        if (t.isRecurring)
                          _metaChip('Repeats', icon: Icons.repeat_rounded),
                        if (t.subtasks.isNotEmpty) _subtaskChip(t),
                      ]),
                    ],
                  ],
                ),
              ),
              Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: done ? 0.25 : 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 260.ms, delay: (40 * index).ms)
        .slideY(begin: 0.06, end: 0, curve: Curves.easeOut);
  }

  bool _hasMeta(TodoTask t) =>
      t.alarmTime != null || t.isRecurring || t.subtasks.isNotEmpty;

  Widget _metaChip(String label, {IconData? icon, Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: iconColor ?? AppColors.textSecondary),
          const SizedBox(width: 5),
        ],
        Text(label,
            style: T.footnote(c: AppColors.textSecondary)
                .copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _subtaskChip(TodoTask t) {
    final doneCount = t.subtasks.where((s) => s.done).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 28,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: t.subtaskProgress,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('$doneCount/${t.subtasks.length}',
            style: T.footnote(c: AppColors.textSecondary)
                .copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: PaperCard(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
        child: Column(children: [
          const Text('🌿', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('A clear page today', style: T.title3()),
          const SizedBox(height: 4),
          Text('Tap + to jot down your first task',
              style: T.body(c: AppColors.textSecondary), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
