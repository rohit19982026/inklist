import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/habit.dart';
import '../services/habit_service.dart';
import '../services/entitlement_service.dart';
import '../services/groq_service.dart';
import '../services/data_sync.dart';
import '../services/todo_service.dart';
import '../widgets/ink_widgets.dart';
import 'settings_screen.dart';

/// InkList "Habits" — a weekly habit grid. Each habit is a paper card with a
/// streak flame and 7 tappable day cells for the current week. Free tier is
/// capped at 3 habits; an AI button suggests complementary habits.
class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});
  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> with WidgetsBindingObserver {
  bool _loading = true;
  List<Habit> _habits = const [];
  bool _isPro = false;
  bool _aiConfigured = false;
  bool _suggesting = false;
  late DateTime _weekStart;

  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    _weekStart = TodoService.startOfWeek(DateTime.now());
    _load();
    DataSync.listenable.addListener(_load);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    DataSync.listenable.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  Future<void> _load() async {
    final habits = await HabitService.getAll();
    final isPro = await EntitlementService.isPro();
    final configured = await GroqService.isConfigured;
    if (!mounted) return;
    setState(() {
      _habits = habits;
      _isPro = isPro;
      _aiConfigured = configured;
      _loading = false;
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _toggle(Habit h, DateTime day) async {
    // Don't allow ticking the future.
    if (day.isAfter(DateTime.now())) return;
    HapticFeedback.lightImpact();
    await HabitService.toggle(h.id, day);
    DataSync.notifyChanged();
  }

  Future<void> _addHabit() async {
    if (!_isPro && _habits.length >= EntitlementService.maxFreeHabits) {
      _showProGate();
      return;
    }
    final habit = await _HabitEditorSheet.show(context);
    if (habit != null) {
      await HabitService.upsert(habit);
      DataSync.notifyChanged();
    }
  }

  Future<void> _editHabit(Habit h) async {
    final updated = await _HabitEditorSheet.show(context, existing: h);
    if (updated != null) {
      await HabitService.upsert(updated);
      DataSync.notifyChanged();
    }
  }

  Future<void> _deleteHabit(Habit h) async {
    HapticFeedback.mediumImpact();
    await HabitService.delete(h.id);
    DataSync.notifyChanged();
  }

  void _shiftWeek(int weeks) {
    HapticFeedback.selectionClick();
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));
  }

  void _showProGate() {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Free plan tracks up to 3 habits — InkList Pro unlocks unlimited',
          style: T.footnote(c: Colors.white)),
      backgroundColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ));
  }

  Future<void> _suggestHabits() async {
    if (_suggesting) return;
    if (!_aiConfigured) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return;
    }
    setState(() => _suggesting = true);
    final result =
        await GroqService.suggestHabits(_habits.map((h) => h.title).toList());
    if (!mounted) return;
    setState(() => _suggesting = false);
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Could not get suggestions',
            style: T.footnote(c: Colors.white)),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ));
      return;
    }
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuggestionSheet(suggestions: result.data!),
    );
    if (chosen == null || !mounted) return;
    if (!_isPro && _habits.length >= EntitlementService.maxFreeHabits) {
      _showProGate();
      return;
    }
    final habit = await _HabitEditorSheet.show(context, presetTitle: chosen);
    if (habit != null) {
      await HabitService.upsert(habit);
      DataSync.notifyChanged();
    }
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
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final thisWeek = _isSameDay(_weekStart, TodoService.startOfWeek(now));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(thisWeek)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                sliver: SliverToBoxAdapter(child: _weekBar(_weekStart, weekEnd, thisWeek)),
              ),
              if (_habits.isEmpty)
                SliverToBoxAdapter(child: _emptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _habitCard(_habits[i], now, i)
                          .animate()
                          .fadeIn(duration: 240.ms, delay: (40 * i).ms)
                          .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                      childCount: _habits.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'habits_ai',
            mini: true,
            elevation: 2,
            onPressed: _suggestHabits,
            backgroundColor: AppColors.accent,
            child: _suggesting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'habits_add',
            onPressed: _addHabit,
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text('New Habit',
                style: T.body(c: Colors.white).copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _header(bool thisWeek) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Habits', style: T.largeTitle()),
                const SizedBox(height: 2),
                Text(
                  _habits.isEmpty
                      ? 'Small things, every day.'
                      : '${_habits.length} habit${_habits.length == 1 ? '' : 's'} · keep the streak alive',
                  style: T.body(c: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekBar(DateTime start, DateTime end, bool thisWeek) {
    final sameMonth = start.month == end.month;
    final range = sameMonth
        ? '${DateFormat('d').format(start)}–${DateFormat('d MMM').format(end)}'
        : '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(children: [
        GestureDetector(
          onTap: () => _shiftWeek(-1),
          behavior: HitTestBehavior.opaque,
          child: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
        ),
        Expanded(
          child: Column(children: [
            Text(thisWeek ? 'This week' : range,
                style: T.title3().copyWith(fontSize: 18)),
            if (thisWeek)
              Text(range, style: T.caption1()),
          ]),
        ),
        GestureDetector(
          onTap: () => _shiftWeek(1),
          behavior: HitTestBehavior.opaque,
          child: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        ),
      ]),
    );
  }

  Widget _habitCard(Habit h, DateTime now, int index) {
    final color = Color(h.colorValue);
    final streak = h.currentStreak(now);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey('habit_${h.id}'),
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
        confirmDismiss: (_) async {
          await _deleteHabit(h);
          return true;
        },
        child: PaperCard(
          onTap: () => _editHabit(h),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Text(h.emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(h.title,
                      style: T.body().copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (streak > 0) ...[
                  const Icon(Icons.local_fire_department_rounded,
                      color: AppColors.sunset, size: 18),
                  const SizedBox(width: 3),
                  Text('$streak',
                      style: T.body(c: AppColors.sunset).copyWith(fontWeight: FontWeight.w800)),
                ],
              ]),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) {
                  final day = _weekStart.add(Duration(days: i));
                  final done = h.isDoneOn(day);
                  final isToday = _isSameDay(day, now);
                  final future = day.isAfter(now);
                  return _dayCell(h, day, i, done, isToday, future, color);
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayCell(Habit h, DateTime day, int i, bool done, bool isToday,
      bool future, Color color) {
    return GestureDetector(
      onTap: future ? null : () => _toggle(h, day),
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        Text(_weekdayLetters[i],
            style: T.caption2(
                c: isToday ? AppColors.primary : AppColors.textMuted)
                .copyWith(fontWeight: isToday ? FontWeight.w800 : FontWeight.w600)),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: done ? color : AppColors.fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: isToday && !done ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            scale: done ? 1 : 0,
            child: Icon(Icons.check_rounded,
                size: 18,
                color: future ? AppColors.textHint : AppColors.textPrimary),
          ),
        ),
      ]),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: PaperCard(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
        child: Column(children: [
          const Text('🔥', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Build your first habit', style: T.title3()),
          const SizedBox(height: 4),
          Text('Tap + to add a daily habit, or ✨ for AI ideas',
              style: T.body(c: AppColors.textSecondary), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

/// Bottom sheet listing AI habit suggestions; returns the chosen title.
class _SuggestionSheet extends StatelessWidget {
  final List<String> suggestions;
  const _SuggestionSheet({required this.suggestions});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.x2)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('Habit ideas', style: T.title3()),
              ]),
              const SizedBox(height: 4),
              Text('Tap one to add it', style: T.footnote()),
              const SizedBox(height: 12),
              for (final s in suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PaperCard(
                    onTap: () => Navigator.pop(context, s),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Expanded(child: Text(s, style: T.body())),
                      const Icon(Icons.add_circle_rounded,
                          color: AppColors.primary, size: 20),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Create / edit a habit — title, emoji, colour.
class _HabitEditorSheet extends StatefulWidget {
  final Habit? existing;
  final String? presetTitle;
  const _HabitEditorSheet({this.existing, this.presetTitle});

  static Future<Habit?> show(BuildContext context,
      {Habit? existing, String? presetTitle}) {
    return showModalBottomSheet<Habit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HabitEditorSheet(existing: existing, presetTitle: presetTitle),
    );
  }

  @override
  State<_HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends State<_HabitEditorSheet> {
  static const _emojis = [
    '🌱', '💧', '📚', '🏃', '🧘', '💪', '🥗', '😴', '✍️', '🎯',
    '🧹', '🎸', '☀️', '🚭', '💊', '🙏',
  ];

  late final TextEditingController _title;
  late String _emoji;
  late int _color;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _title = TextEditingController(text: h?.title ?? widget.presetTitle ?? '');
    _emoji = h?.emoji ?? _emojis.first;
    _color = h?.colorValue ?? AppColors.highlighters.first.toARGB32();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Give your habit a name', style: T.footnote(c: Colors.white)),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ));
      return;
    }
    final base = widget.existing;
    final habit = base != null
        ? base.copyWith(title: title, emoji: _emoji, colorValue: _color)
        : Habit(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: title,
            emoji: _emoji,
            colorValue: _color,
            createdAt: DateTime.now(),
          );
    Navigator.pop(context, habit);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.x2)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(widget.existing == null ? 'New Habit' : 'Edit Habit',
                  style: T.title3()),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.fill,
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _title,
                  autofocus: widget.existing == null,
                  textCapitalization: TextCapitalization.sentences,
                  style: T.body(),
                  decoration: InputDecoration(
                    hintText: 'e.g. Drink 2L water',
                    hintStyle: T.footnote(c: AppColors.textHint),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Icon', style: T.footnote(c: AppColors.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _emojis.map((e) {
                  final sel = e == _emoji;
                  return GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: Container(
                      width: 44, height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primaryLight : AppColors.fill,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(
                          color: sel ? AppColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text('Colour', style: T.footnote(c: AppColors.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10, runSpacing: 10,
                children: AppColors.highlighters.map((c) {
                  final v = c.toARGB32();
                  final sel = v == _color;
                  return GestureDetector(
                    onTap: () => setState(() => _color = v),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? AppColors.textPrimary : AppColors.border,
                          width: sel ? 2.5 : 1,
                        ),
                      ),
                      child: sel
                          ? const Icon(Icons.check_rounded,
                              size: 18, color: AppColors.textPrimary)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.lg)),
                  ),
                  child: Text(widget.existing == null ? 'Add Habit' : 'Save',
                      style: T.headline(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
