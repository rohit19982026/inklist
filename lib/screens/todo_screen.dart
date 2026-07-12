import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/todo_task.dart';
import '../services/todo_service.dart';
import '../services/data_sync.dart';
import '../services/groq_service.dart';
import '../services/alarm_scheduler_service.dart';
import '../widgets/section_header.dart';
import '../widgets/todo_editor_sheet.dart';
import '../widgets/nl_quick_add_sheet.dart';
import 'weekly_plan_preview_screen.dart';
import 'settings_screen.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});
  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> with WidgetsBindingObserver {
  bool _loading = true;
  List<TodoTask> _all = const [];
  int _tab = 0; // 0 = Today, 1 = This Week
  String? _brief;
  bool _briefLoading = false;
  bool _aiConfigured = false;
  DateTime? _selectedWeekDay;

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
    // Native alarm Dismiss/Snooze writes directly into SharedPreferences
    // while the app may be backgrounded or killed — that write doesn't fire
    // the pure-Dart DataSync signal, so re-read from disk on every resume.
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  void _onDataChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final all = await TodoService.getAll();
    final configured = await GroqService.isConfigured;
    final cachedBrief = configured ? await GroqService.getCachedDailyBrief() : null;
    if (!mounted) return;
    setState(() {
      _all = all;
      _aiConfigured = configured;
      _brief = cachedBrief;
      _loading = false;
    });
    // The Smart Reminders background pipeline now owns keeping this cache
    // fresh (3-4x/day, whether or not the app is open) — this screen just
    // mirrors whatever it last wrote. The refresh button below remains a
    // manual override.
  }

  Future<void> _refreshDailyBrief() async {
    if (_briefLoading) return;
    setState(() => _briefLoading = true);
    final now = DateTime.now();
    final tasks = [
      ...TodoService.tasksForDay(_all, now),
      ...TodoService.overdueTasks(_all, asOf: now),
    ];
    final result = await GroqService.dailyFocusBrief(tasks);
    if (!mounted) return;
    setState(() => _briefLoading = false);
    if (result.isSuccess) {
      setState(() => _brief = result.data);
      await GroqService.setCachedDailyBrief(result.data!);
    }
  }

  Future<void> _openQuickAdd() async {
    final t = await NlQuickAddSheet.show(context);
    if (t != null) {
      await TodoService.upsert(t);
      final ok = await AlarmSchedulerService.syncTaskAlarm(t);
      DataSync.notifyChanged();
      if (!ok && t.alarmEnabled) _showAlarmFailureWarning();
    }
  }

  Future<void> _openPlanMyWeek() async {
    await showWeeklyPlanFlow(context);
  }

  Future<void> _create() async {
    final t = await TodoEditorSheet.show(context);
    if (t != null) {
      await TodoService.upsert(t);
      final ok = await AlarmSchedulerService.syncTaskAlarm(t);
      DataSync.notifyChanged();
      if (!ok && t.alarmEnabled) _showAlarmFailureWarning();
    }
  }

  Future<void> _edit(TodoTask t) async {
    final updated = await TodoEditorSheet.show(context, existing: t);
    if (updated != null) {
      await TodoService.upsert(updated);
      final ok = await AlarmSchedulerService.syncTaskAlarm(updated);
      DataSync.notifyChanged();
      if (!ok && updated.alarmEnabled) _showAlarmFailureWarning();
    }
  }

  void _showAlarmFailureWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Alarm couldn\'t be scheduled — grant "Alarms & reminders" access',
          style: T.footnote(c: Colors.white)),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      action: SnackBarAction(
        label: 'FIX',
        textColor: Colors.white,
        onPressed: () => AlarmSchedulerService.requestExactAlarmPermission(),
      ),
    ));
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

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
    final weekStart = TodoService.startOfWeek(now);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _headerSection()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              sliver: SliverToBoxAdapter(child: _tabToggle()),
            ),
            if (_tab == 0) ..._todayTabSlivers(overdue, today, now)
            else ..._weekTabSlivers(weekStart),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'todo_quick_add',
            mini: true,
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
                style: T.footnote(c: Colors.white).copyWith(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _headerSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tasks', style: T.largeTitle()),
        const SizedBox(height: 2),
        Text('Plan your day, your week, without the noise', style: T.subhead()),
      ]),
    );
  }

  Widget _tabToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(children: [
        Expanded(child: _tabPill('Today', 0)),
        Expanded(child: _tabPill('This Week', 1)),
      ]),
    );
  }

  Widget _tabPill(String label, int idx) {
    final sel = _tab == idx;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _tab = idx);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: sel ? AppColors.tinyShadow : null,
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: T.footnote(c: sel ? AppColors.primary : AppColors.textSecondary)
                .copyWith(fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
      ),
    );
  }

  // ── Today tab ────────────────────────────────────────────────────────────

  List<Widget> _todayTabSlivers(
      List<TodoTask> overdue, List<TodoTask> today, DateTime now) {
    final done = today.where((t) => t.isCompletedOn(now)).length;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        sliver: SliverToBoxAdapter(child: _progressHeroCard(done, today.length)),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        sliver: SliverToBoxAdapter(child: _dailyFocusBriefCard()),
      ),
      if (overdue.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            title: 'Overdue',
            subtitle: '${overdue.length} task${overdue.length == 1 ? '' : 's'}',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _taskCard(overdue[i], now, accent: AppColors.danger),
              childCount: overdue.length,
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(
        child: SectionHeader(
          title: 'Today',
          subtitle: today.isEmpty ? null : '$done of ${today.length} done',
        ),
      ),
      if (today.isEmpty)
        SliverToBoxAdapter(
          child: _emptyState(Icons.self_improvement_rounded, 'Nothing due today',
              'Enjoy the calm, or add something new'),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _taskCard(today[i], now),
              childCount: today.length,
            ),
          ),
        ),
    ];
  }

  Widget _progressHeroCard(int done, int total) {
    final pct = total > 0 ? done / total : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: AppColors.mintCardGradient,
        borderRadius: BorderRadius.circular(Radii.x2),
        boxShadow: AppColors.coloredShadow(AppColors.mint),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TODAY\'S PROGRESS',
                  style: T.caption2(c: Colors.white.withValues(alpha: 0.8))
                      .copyWith(letterSpacing: 0.6)),
              const SizedBox(height: 6),
              Text(
                total == 0 ? 'Nothing scheduled' : '$done of $total done',
                style: T.title2(color: Colors.white),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 54,
          height: 54,
          child: Stack(alignment: Alignment.center, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CircularProgressIndicator(
                value: total == 0 ? 0 : v,
                strokeWidth: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            Text('${(pct * 100).round()}%',
                style: T.caption1(c: Colors.white).copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }

  // ── This Week tab ────────────────────────────────────────────────────────

  List<Widget> _weekTabSlivers(DateTime weekStart) {
    final selected = _selectedWeekDay ?? DateTime.now();
    final tasks = TodoService.tasksForDay(_all, selected);
    final isToday = _isSameDay(selected, DateTime.now());
    final label = isToday ? 'Today' : DateFormat('EEEE, d MMM').format(selected);

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        sliver: SliverToBoxAdapter(child: _planMyWeekCard()),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        sliver: SliverToBoxAdapter(child: _weekDayStrip(weekStart, selected)),
      ),
      SliverToBoxAdapter(
        child: SectionHeader(
          title: label,
          subtitle: tasks.isEmpty ? null : '${tasks.length} task${tasks.length == 1 ? '' : 's'}',
        ),
      ),
      if (tasks.isEmpty)
        SliverToBoxAdapter(
          child: _emptyState(Icons.event_available_rounded, 'No tasks this day',
              'Tap a task in Today to move it here, or add a new one'),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, j) => _taskCard(tasks[j], selected),
              childCount: tasks.length,
            ),
          ),
        ),
    ];
  }

  Widget _weekDayStrip(DateTime weekStart, DateTime selected) {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final day = weekStart.add(Duration(days: i));
          final isSelected = _isSameDay(day, selected);
          final isToday = _isSameDay(day, DateTime.now());
          final hasTasks = TodoService.tasksForDay(_all, day).isNotEmpty;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedWeekDay = day);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 50,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(Radii.lg),
                boxShadow: isSelected
                    ? AppColors.coloredShadow(AppColors.primary)
                    : AppColors.tinyShadow,
                border: (isToday && !isSelected)
                    ? Border.all(color: AppColors.primary, width: 1.4)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('E').format(day).substring(0, 3).toUpperCase(),
                    style: T.caption2(c: isSelected ? Colors.white70 : AppColors.textMuted)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text('${day.day}',
                      style: T.num(16, color: isSelected ? Colors.white : AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    width: 5, height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasTasks
                          ? (isSelected ? Colors.white : AppColors.primary)
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Task card ────────────────────────────────────────────────────────────

  Widget _taskCard(TodoTask t, DateTime forDay, {Color? accent}) {
    final done = t.isCompletedOn(forDay);
    final priorityColor = switch (t.priority) {
      'high' => AppColors.danger,
      'low' => AppColors.success,
      _ => AppColors.warning,
    };
    final priorityLabel = switch (t.priority) {
      'high' => 'High',
      'low' => 'Low',
      _ => 'Medium',
    };

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
        child: GestureDetector(
          onTap: () => _edit(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(Radii.xl),
              border: Border(
                left: BorderSide(color: accent ?? priorityColor, width: 4),
              ),
              boxShadow: done ? AppColors.tinyShadow : AppColors.softShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _toggle(t, forDay),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 28, height: 28,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? AppColors.success : Colors.transparent,
                      border: Border.all(
                        color: done ? AppColors.success : priorityColor.withValues(alpha: 0.55),
                        width: 2,
                      ),
                    ),
                    child: done
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          style: T.body().copyWith(
                              fontWeight: FontWeight.w700,
                              decoration: done ? TextDecoration.lineThrough : null,
                              color: done ? AppColors.textMuted : AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        _metaChip(priorityLabel, priorityColor, dot: true),
                        if (t.alarmTime != null)
                          _metaChip(
                            TimeOfDay(hour: t.alarmTime!.hour, minute: t.alarmTime!.minute)
                                .format(context),
                            AppColors.textSecondary,
                            icon: t.alarmEnabled ? Icons.alarm_rounded : Icons.schedule_rounded,
                            iconColor: t.alarmEnabled ? AppColors.danger : null,
                          ),
                        if (t.isRecurring)
                          _metaChip('Repeats', AppColors.textSecondary, icon: Icons.repeat_rounded),
                        if (t.subtasks.isNotEmpty)
                          _subtaskChip(t),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaChip(String label, Color color, {IconData? icon, Color? iconColor, bool dot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 5),
        ] else if (icon != null) ...[
          Icon(icon, size: 11, color: iconColor ?? color),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: T.caption2(c: color).copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _subtaskChip(TodoTask t) {
    final doneCount = t.subtasks.where((s) => s.done).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 28, height: 4,
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
            style: T.caption2(c: AppColors.textSecondary).copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ── AI cards ─────────────────────────────────────────────────────────────

  Widget _dailyFocusBriefCard() {
    if (!_aiConfigured) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Add your free Groq API key in Settings to get an AI daily brief',
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(Radii.x2),
        boxShadow: AppColors.coloredShadow(AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text('Daily Focus', style: T.headline(color: Colors.white)),
            const Spacer(),
            if (_briefLoading)
              const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
            else
              GestureDetector(
                onTap: _refreshDailyBrief,
                child: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white70),
              ),
          ]),
          const SizedBox(height: 8),
          Text(
            _brief ?? 'Tap refresh to get today\'s priorities',
            style: T.footnote(c: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }

  Widget _planMyWeekCard() {
    return GestureDetector(
      onTap: _openPlanMyWeek,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(Radii.x2),
          boxShadow: AppColors.coloredShadow(AppColors.primary),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan My Week', style: T.headline(color: Colors.white)),
                const SizedBox(height: 2),
                Text('Brain-dump your week, AI organizes it into days',
                    style: T.caption1(c: Colors.white.withValues(alpha: 0.7))),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white70),
        ]),
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        child: Column(children: [
          Icon(icon, size: 30, color: AppColors.textHint),
          const SizedBox(height: 10),
          Text(title, style: T.body().copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(subtitle, style: T.footnote(), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
