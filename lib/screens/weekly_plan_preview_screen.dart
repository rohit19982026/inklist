import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/todo_task.dart';
import '../models/weekly_plan_draft.dart';
import '../services/groq_service.dart';
import '../services/todo_service.dart';
import '../services/data_sync.dart';

/// Entry point: shows the brain-dump intake sheet, then (on a successful AI
/// response) pushes the preview/edit/confirm screen. Nothing is ever
/// auto-saved — the preview screen is the review step.
Future<void> showWeeklyPlanFlow(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _WeeklyPlanIntakeSheet(),
  );
}

class _WeeklyPlanIntakeSheet extends StatefulWidget {
  const _WeeklyPlanIntakeSheet();
  @override
  State<_WeeklyPlanIntakeSheet> createState() => _WeeklyPlanIntakeSheetState();
}

class _WeeklyPlanIntakeSheetState extends State<_WeeklyPlanIntakeSheet> {
  final _text = TextEditingController();
  bool _generating = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final text = _text.text.trim();
    if (text.isEmpty || _generating) return;
    HapticFeedback.lightImpact();
    setState(() => _generating = true);
    final result = await GroqService.planWeek(text);
    if (!mounted) return;
    setState(() => _generating = false);
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Could not generate a plan',
            style: T.footnote(c: Colors.white)),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ));
      return;
    }
    if (result.data!.totalTaskCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No tasks found in that — try adding more detail',
            style: T.footnote(c: Colors.white)),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => WeeklyPlanPreviewScreen(draft: result.data!)));
    if (!mounted) return;
    Navigator.pop(context);
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
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text('Plan My Week', style: T.title3()),
              const SizedBox(height: 6),
              Text(
                'Describe your week — meetings, errands, deadlines, anything. '
                'AI will organize it into a day-by-day plan you can edit before saving.',
                style: T.footnote(),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.fill,
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  style: T.body(),
                  decoration: InputDecoration(
                    hintText: 'e.g. dentist Tuesday morning, finish the report '
                        'by Friday, call mom sometime, gym Mon/Wed/Fri...',
                    hintStyle: T.footnote(c: AppColors.textHint),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.lg)),
                  ),
                  icon: _generating
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                  label: Text('Generate Plan', style: T.headline(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WeeklyPlanPreviewScreen extends StatefulWidget {
  final WeeklyPlanDraft draft;
  const WeeklyPlanPreviewScreen({super.key, required this.draft});

  @override
  State<WeeklyPlanPreviewScreen> createState() => _WeeklyPlanPreviewScreenState();
}

class _WeeklyPlanPreviewScreenState extends State<WeeklyPlanPreviewScreen> {
  late Map<String, List<WeeklyPlanTaskDraft>> _days;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _days = {
      for (final e in widget.draft.days.entries) e.key: List.of(e.value),
    };
  }

  int get _totalCount => _days.values.fold(0, (s, l) => s + l.length);

  void _removeTask(String day, int i) {
    setState(() {
      _days[day]!.removeAt(i);
      if (_days[day]!.isEmpty) _days.remove(day);
    });
  }

  void _addTask(String day) {
    setState(() {
      _days.putIfAbsent(day, () => []).add(WeeklyPlanTaskDraft(title: ''));
    });
  }

  Future<void> _confirm() async {
    if (_totalCount == 0 || _saving) return;
    setState(() => _saving = true);
    var saved = 0;
    final dayIndexOf = {
      for (var i = 0; i < WeeklyPlanDraft.dayOrder.length; i++)
        WeeklyPlanDraft.dayOrder[i]: i,
    };
    final weekStart = TodoService.startOfWeek(DateTime.now());
    for (final entry in _days.entries) {
      final dayOffset = dayIndexOf[entry.key] ?? 0;
      final dueDate = weekStart.add(Duration(days: dayOffset));
      for (var i = 0; i < entry.value.length; i++) {
        final draft = entry.value[i];
        if (draft.title.trim().isEmpty) continue;
        TimeOfDayMs? time;
        final t = draft.time;
        if (t != null && t.contains(':')) {
          final parts = t.split(':');
          final h = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          if (h != null && m != null) time = TimeOfDayMs(hour: h, minute: m);
        }
        final task = TodoTask(
          id: '${DateTime.now().millisecondsSinceEpoch}_${entry.key}_$i',
          title: draft.title.trim(),
          dueDate: dueDate,
          alarmTime: time,
          priority: draft.priority,
          recurrenceRule: 'none',
          aiGenerated: true,
          createdAt: DateTime.now(),
        );
        await TodoService.upsert(task);
        saved++;
      }
    }
    DataSync.notifyChanged();
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Saved $saved task${saved == 1 ? '' : 's'}',
          style: T.footnote(c: Colors.white)),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Review Your Week', style: T.title3()),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                for (final day in WeeklyPlanDraft.dayOrder)
                  if (_days.containsKey(day)) _daySection(day),
              ],
            ),
          ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_totalCount == 0 || _saving) ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.lg)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Confirm & Save $_totalCount Task${_totalCount == 1 ? '' : 's'}',
                      style: T.headline(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _daySection(String day) {
    final tasks = _days[day]!;
    final label = day[0].toUpperCase() + day.substring(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: T.headline()),
            const Spacer(),
            GestureDetector(
              onTap: () => _addTask(day),
              child: const Icon(Icons.add_circle_rounded,
                  size: 20, color: AppColors.primary),
            ),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < tasks.length; i++) _taskRow(day, i, tasks[i]),
        ],
      ),
    );
  }

  Widget _taskRow(String day, int i, WeeklyPlanTaskDraft t) {
    final priorityColor = switch (t.priority) {
      'high' => AppColors.danger,
      'low' => AppColors.success,
      _ => AppColors.warning,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border(left: BorderSide(color: priorityColor, width: 4)),
        boxShadow: AppColors.tinyShadow,
      ),
      child: Row(children: [
        Expanded(
          child: TextFormField(
            initialValue: t.title,
            style: T.body(),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
            ),
            onChanged: (v) => t.title = v,
          ),
        ),
        _priorityDot(day, i, t),
        GestureDetector(
          onTap: () => _removeTask(day, i),
          child: const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
          ),
        ),
      ]),
    );
  }

  Widget _priorityDot(String day, int i, WeeklyPlanTaskDraft t) {
    const order = ['low', 'medium', 'high'];
    return GestureDetector(
      onTap: () {
        setState(() {
          final idx = order.indexOf(t.priority);
          t.priority = order[(idx + 1) % order.length];
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(t.priority, style: T.caption2()),
      ),
    );
  }
}
