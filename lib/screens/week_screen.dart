import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/todo_task.dart';
import '../services/todo_service.dart';
import '../services/data_sync.dart';
import '../services/alarm_scheduler_service.dart';
import '../widgets/todo_editor_sheet.dart';
import '../widgets/ink_widgets.dart';
import '../widgets/alarm_feedback.dart';
import 'weekly_plan_preview_screen.dart';

/// InkList "Week" — a MON–SUN planner grid. Each day is a paper card with its
/// tasks, a per-day add button, and a highlighter header (today accented).
/// "Plan My Week" reuses the AI brain-dump → preview flow. You can page
/// backward/forward a week at a time.
class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});
  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> with WidgetsBindingObserver {
  bool _loading = true;
  List<TodoTask> _all = const [];
  late DateTime _weekStart; // Monday of the shown week

  // Highlighter colour per weekday, so the grid reads like a colourful planner.
  static const _dayHighlights = <Color>[
    AppColors.hlPink,
    AppColors.hlPeach,
    AppColors.hlYellow,
    AppColors.hlMint,
    AppColors.hlSky,
    AppColors.hlLavender,
    AppColors.hlPink,
  ];
  static const _dayNames = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _weekStart = TodoService.startOfWeek(DateTime.now());
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
    if (!mounted) return;
    setState(() {
      _all = all;
      _loading = false;
    });
  }

  Future<void> _persist(TodoTask t) async {
    await TodoService.upsert(t);
    final ok = await AlarmSchedulerService.syncTaskAlarm(t);
    DataSync.notifyChanged();
    if (mounted) await showAlarmSchedulingFeedback(context, t, ok);
  }

  Future<void> _addForDay(DateTime day) async {
    final t = await TodoEditorSheet.show(context, initialDate: day);
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

  Future<void> _openPlanMyWeek() async {
    HapticFeedback.lightImpact();
    await showWeeklyPlanFlow(context);
  }

  void _shiftWeek(int weeks) {
    HapticFeedback.selectionClick();
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));
  }

  void _goToThisWeek() {
    HapticFeedback.selectionClick();
    setState(() => _weekStart = TodoService.startOfWeek(DateTime.now()));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    final today = DateTime.now();
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final thisWeek = _isSameDay(_weekStart, TodoService.startOfWeek(today));

    // Weekly totals for the progress line.
    int total = 0, done = 0;
    for (var i = 0; i < 7; i++) {
      final day = _weekStart.add(Duration(days: i));
      final tasks = TodoService.tasksForDay(_all, day);
      total += tasks.length;
      done += tasks.where((t) => t.isCompletedOn(day)).length;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(_weekStart, weekEnd, thisWeek)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                sliver: SliverToBoxAdapter(child: _weekProgress(done, total)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final day = _weekStart.add(Duration(days: i));
                      return _daySheet(day, i, today)
                          .animate()
                          .fadeIn(duration: 240.ms, delay: (40 * i).ms)
                          .slideY(begin: 0.05, end: 0, curve: Curves.easeOut);
                    },
                    childCount: 7,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'week_plan_ai',
        onPressed: _openPlanMyWeek,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        label: Text('Plan My Week',
            style: T.body(c: Colors.white).copyWith(fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ── Header with week range + navigation ─────────────────────────────────────
  Widget _header(DateTime start, DateTime end, bool thisWeek) {
    final sameMonth = start.month == end.month;
    final range = sameMonth
        ? '${DateFormat('d').format(start)}–${DateFormat('d MMM').format(end)}'
        : '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(thisWeek ? 'This Week' : 'Week Plan', style: T.largeTitle()),
                const SizedBox(height: 2),
                Row(children: [
                  Text(range, style: T.body(c: AppColors.textSecondary)),
                  if (!thisWeek) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _goToThisWeek,
                      child: Text('Today',
                          style: T.footnote(c: AppColors.primary)
                              .copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ]),
              ],
            ),
          ),
          _navButton(Icons.chevron_left_rounded, () => _shiftWeek(-1),
              tooltip: 'Previous week'),
          const SizedBox(width: 8),
          _navButton(Icons.chevron_right_rounded, () => _shiftWeek(1),
              tooltip: 'Next week'),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap, {String? tooltip}) {
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
        icon: Icon(icon, color: AppColors.textSecondary, size: 22),
        onPressed: onTap,
        padding: EdgeInsets.zero,
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }

  // ── Weekly progress line ────────────────────────────────────────────────────
  Widget _weekProgress(int done, int total) {
    final pct = total > 0 ? done / total : 0.0;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const HighlighterLabel('This week', color: AppColors.hlMint),
            const Spacer(),
            Text(
              total == 0 ? 'Nothing planned' : '$done of $total done',
              style: T.body(c: AppColors.textSecondary)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(
                value: total == 0 ? 0 : v,
                minHeight: 10,
                backgroundColor: AppColors.fill,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── One day's sheet ─────────────────────────────────────────────────────────
  Widget _daySheet(DateTime day, int index, DateTime today) {
    final isToday = _isSameDay(day, today);
    final tasks = TodoService.tasksForDay(_all, day)
      ..sort((a, b) {
        final at = a.alarmTime, bt = b.alarmTime;
        if (at == null && bt == null) return 0;
        if (at == null) return 1; // untimed after timed
        if (bt == null) return -1;
        return (at.hour * 60 + at.minute).compareTo(bt.hour * 60 + bt.minute);
      });
    final doneCount = tasks.where((t) => t.isCompletedOn(day)).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PaperCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        color: isToday ? AppColors.primaryLight : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              HighlighterLabel(_dayNames[index], color: _dayHighlights[index]),
              const SizedBox(width: 8),
              Text(DateFormat('d MMM').format(day),
                  style: T.footnote(c: AppColors.textMuted)
                      .copyWith(fontWeight: FontWeight.w700)),
              if (isToday) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text('Today',
                      style: T.caption2(c: Colors.white)
                          .copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
              const Spacer(),
              if (tasks.isNotEmpty)
                Text('$doneCount/${tasks.length}',
                    style: T.footnote(c: AppColors.textMuted)
                        .copyWith(fontWeight: FontWeight.w700)),
              GestureDetector(
                onTap: () => _addForDay(day),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.add_circle_rounded,
                      size: 24, color: AppColors.primary),
                ),
              ),
            ]),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 2),
                child: Text('No plans yet',
                    style: T.footnote(c: AppColors.textHint)),
              )
            else ...[
              const SizedBox(height: 8),
              for (final t in tasks) _taskRow(t, day),
            ],
          ],
        ),
      ),
    );
  }

  Widget _taskRow(TodoTask t, DateTime day) {
    final done = t.isCompletedOn(day);
    final time = t.alarmTime != null
        ? TimeOfDay(hour: t.alarmTime!.hour, minute: t.alarmTime!.minute)
            .format(context)
        : null;
    final priorityColor = switch (t.priority) {
      'high' => AppColors.danger,
      'low' => AppColors.success,
      _ => AppColors.warning,
    };
    return InkWell(
      onTap: () => _edit(t),
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkCheckbox(
              value: done,
              size: 22,
              onChanged: (_) => _toggle(t, day),
            ),
            const SizedBox(width: 10),
            Container(
              width: 3,
              height: 18,
              margin: const EdgeInsets.only(top: 2, right: 8),
              decoration: BoxDecoration(
                color: priorityColor.withValues(alpha: done ? 0.25 : 0.9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      style: T.body().copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                          color:
                              done ? AppColors.textMuted : AppColors.textPrimary)),
                  if (time != null || t.isRecurring)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(children: [
                        if (time != null) ...[
                          Icon(
                            t.alarmEnabled
                                ? Icons.alarm_rounded
                                : Icons.schedule_rounded,
                            size: 12,
                            color: t.alarmEnabled
                                ? AppColors.primary
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(time,
                              style: T.caption2(c: AppColors.textSecondary)
                                  .copyWith(fontWeight: FontWeight.w700)),
                        ],
                        if (time != null && t.isRecurring)
                          const SizedBox(width: 8),
                        if (t.isRecurring) ...[
                          const Icon(Icons.repeat_rounded,
                              size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text('Repeats',
                              style: T.caption2(c: AppColors.textSecondary)
                                  .copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
