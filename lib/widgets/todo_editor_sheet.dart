import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/todo_task.dart';
import '../services/recurrence_rule.dart';
import '../services/groq_service.dart';
import '../services/alarm_scheduler_service.dart';

/// Create / edit a to-do task. Forked from GoalEditorSheet's structure —
/// same drag-handle/sheet-decoration/pill-row idioms. The alarm toggle is
/// intentionally not shown yet (native scheduling lands in a later
/// milestone); the time picker below is purely informational until then.
class TodoEditorSheet extends StatefulWidget {
  final TodoTask? existing;
  const TodoEditorSheet({super.key, this.existing});

  /// Returns the saved task, or null if dismissed.
  static Future<TodoTask?> show(BuildContext context, {TodoTask? existing}) {
    return showModalBottomSheet<TodoTask>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TodoEditorSheet(existing: existing),
    );
  }

  @override
  State<TodoEditorSheet> createState() => _TodoEditorSheetState();
}

class _TodoEditorSheetState extends State<TodoEditorSheet> {
  static const _priorities = <(String, String, Color)>[
    ('low', 'Low', AppColors.success),
    ('medium', 'Medium', AppColors.warning),
    ('high', 'High', AppColors.danger),
  ];
  static const _recurrenceOptions = <(String, String)>[
    ('none', 'None'),
    ('daily', 'Daily'),
    ('weekly', 'Weekly'),
    ('monthly', 'Monthly'),
  ];

  late final TextEditingController _title;
  late final TextEditingController _description;
  late final List<TextEditingController> _subtaskControllers;
  late DateTime _dueDate;
  TimeOfDayMs? _time;
  String _priority = 'medium';
  String _recurrenceKind = 'none'; // none | daily | weekly | monthly
  Set<int> _weekdays = {}; // 1=Mon..7=Sun
  bool _monthlyLast = false;
  late List<TodoSubtask> _subtasks;
  bool _breakingDown = false;
  bool _alarmEnabled = false;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _title = TextEditingController(text: t?.title ?? '');
    _description = TextEditingController(text: t?.description ?? '');
    _dueDate = t?.dueDate ?? DateTime.now();
    _time = t?.alarmTime;
    // Alarm on by default for every new task (InkList's "don't forget" promise).
    _alarmEnabled = t?.alarmEnabled ?? true;
    _priority = t?.priority ?? 'medium';
    _subtasks = List.of(t?.subtasks ?? const []);
    _subtaskControllers =
        _subtasks.map((s) => TextEditingController(text: s.title)).toList();

    final rule = t?.recurrenceRule ?? 'none';
    if (rule == 'daily') {
      _recurrenceKind = 'daily';
    } else if (rule.startsWith('weekly:')) {
      _recurrenceKind = 'weekly';
      final codes = rule.substring(7).split(',').toSet();
      _weekdays = {
        for (var w = 1; w <= 7; w++)
          if (codes.contains(RecurrenceRule.weekdayCode(w))) w,
      };
    } else if (rule.startsWith('monthly:')) {
      _recurrenceKind = 'monthly';
      _monthlyLast = rule.substring(8) == 'last';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    for (final c in _subtaskControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate.isAfter(now) ? _dueDate : now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'When is this due?',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickTime() async {
    HapticFeedback.lightImpact();
    final picked = await showTimePicker(
      context: context,
      initialTime: _time != null
          ? TimeOfDay(hour: _time!.hour, minute: _time!.minute)
          : TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _time = TimeOfDayMs(hour: picked.hour, minute: picked.minute));
    }
  }

  Future<void> _onAlarmToggle(bool v) async {
    if (!v) {
      setState(() => _alarmEnabled = false);
      return;
    }
    setState(() => _alarmEnabled = true);
    final canSchedule = await AlarmSchedulerService.canScheduleExactAlarms();
    if (canSchedule || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        title: const Text('Allow Alarms & Reminders'),
        content: Text(
          'This task\'s alarm won\'t ring on time without "Alarms & reminders" '
          'access. It\'s a one-time system setting, not an app permission dialog.',
          style: T.footnote(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              AlarmSchedulerService.requestExactAlarmPermission();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _setQuickDate(int daysFromToday) {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    setState(() =>
        _dueDate = DateTime(now.year, now.month, now.day + daysFromToday));
  }

  void _addSubtaskRow() {
    setState(() {
      _subtasks.add(TodoSubtask(
          id: DateTime.now().microsecondsSinceEpoch.toString(), title: ''));
      _subtaskControllers.add(TextEditingController());
    });
  }

  void _removeSubtaskRow(int i) {
    setState(() {
      _subtasks.removeAt(i);
      _subtaskControllers.removeAt(i).dispose();
    });
  }

  Future<void> _breakDownTask() async {
    final title = _title.text.trim();
    if (title.isEmpty || _breakingDown) return;
    setState(() => _breakingDown = true);
    final desc = _description.text.trim();
    final result = await GroqService.breakdownTask(title,
        description: desc.isEmpty ? null : desc);
    if (!mounted) return;
    setState(() => _breakingDown = false);
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Could not generate subtasks',
            style: T.footnote(c: Colors.white)),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ));
      return;
    }
    setState(() {
      final base = DateTime.now().microsecondsSinceEpoch;
      for (var i = 0; i < result.data!.length; i++) {
        final s = result.data![i];
        _subtasks.add(TodoSubtask(id: '${base + i}', title: s));
        _subtaskControllers.add(TextEditingController(text: s));
      }
    });
  }

  String get _recurrenceRule {
    switch (_recurrenceKind) {
      case 'daily':
        return 'daily';
      case 'weekly':
        if (_weekdays.isEmpty) return 'none';
        final codes = _weekdays.toList()..sort();
        return 'weekly:${codes.map(RecurrenceRule.weekdayCode).join(',')}';
      case 'monthly':
        return _monthlyLast ? 'monthly:last' : 'monthly:${_dueDate.day}';
      default:
        return 'none';
    }
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Add a title', style: T.footnote(c: Colors.white)),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ));
      return;
    }
    final subtasks = <TodoSubtask>[];
    for (var i = 0; i < _subtasks.length; i++) {
      final text = _subtaskControllers[i].text.trim();
      if (text.isNotEmpty) subtasks.add(_subtasks[i].copyWith(title: text));
    }
    final desc = _description.text.trim();
    // Alarm-on-by-default: if the user left the alarm on but didn't pick a
    // time, default to 9:00 AM so every task still gets a reminder.
    final effectiveTime =
        _time ?? (_alarmEnabled ? const TimeOfDayMs(hour: 9, minute: 0) : null);
    final task = TodoTask(
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: desc.isEmpty ? null : desc,
      dueDate: _dueDate,
      alarmTime: effectiveTime,
      priority: _priority,
      isCompleted: widget.existing?.isCompleted ?? false,
      completedAt: widget.existing?.completedAt,
      alarmEnabled: _alarmEnabled && effectiveTime != null,
      recurrenceRule: _recurrenceRule,
      completedDates: widget.existing?.completedDates ?? const {},
      subtasks: subtasks,
      aiGenerated: widget.existing?.aiGenerated ?? false,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    HapticFeedback.mediumImpact();
    Navigator.pop(context, task);
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
        child: SingleChildScrollView(
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
              Text(widget.existing == null ? 'New Task' : 'Edit Task',
                  style: T.title3()),
              const SizedBox(height: 14),

              _label('TITLE'),
              _box(TextField(
                controller: _title,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                style: T.body().copyWith(fontWeight: FontWeight.w600),
                decoration: _dec('e.g. Pay electricity bill'),
                onChanged: (_) => setState(() {}),
              )),
              const SizedBox(height: 14),

              _label('DESCRIPTION (OPTIONAL)'),
              _box(TextField(
                controller: _description,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: T.body(),
                decoration: _dec('Add notes...'),
              )),
              const SizedBox(height: 14),

              _label('DUE DATE'),
              Row(children: [
                _pillButton('Today', _isSameDay(_dueDate, DateTime.now()),
                    () => _setQuickDate(0)),
                const SizedBox(width: 6),
                _pillButton(
                    'Tomorrow',
                    _isSameDay(_dueDate, DateTime.now().add(const Duration(days: 1))),
                    () => _setQuickDate(1)),
                const Spacer(),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.event_rounded, size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(DateFormat('d MMM').format(_dueDate),
                          style: T.caption1(c: AppColors.primary)
                              .copyWith(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 14),

              _label('TIME (OPTIONAL)'),
              GestureDetector(
                onTap: _pickTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.fill,
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Row(children: [
                    Icon(Icons.schedule_rounded,
                        size: 16,
                        color: _time != null ? AppColors.primary : AppColors.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      _time != null
                          ? TimeOfDay(hour: _time!.hour, minute: _time!.minute)
                              .format(context)
                          : 'No specific time',
                      style: T.body(
                          c: _time != null ? AppColors.textPrimary : AppColors.textMuted),
                    ),
                    if (_time != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() {
                          _time = null;
                          _alarmEnabled = false;
                        }),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: AppColors.textMuted),
                      ),
                    ],
                  ]),
                ),
              ),
              if (_time != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.alarm_rounded, size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Ring a real alarm at this time', style: T.footnote()),
                  ),
                  Switch.adaptive(
                    value: _alarmEnabled,
                    activeThumbColor: AppColors.danger,
                    onChanged: _onAlarmToggle,
                  ),
                ]),
              ],
              const SizedBox(height: 14),

              _label('PRIORITY'),
              Row(
                children: _priorities.map((p) {
                  final sel = _priority == p.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _priority = p.$1);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? p.$3 : AppColors.fill,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(p.$2,
                            style: T.caption1(c: sel ? Colors.white : AppColors.textSecondary)
                                .copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              _label('REPEAT'),
              Row(
                children: _recurrenceOptions.map((r) {
                  final sel = _recurrenceKind == r.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _recurrenceKind = r.$1;
                          if (r.$1 == 'weekly' && _weekdays.isEmpty) {
                            _weekdays = {_dueDate.weekday};
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.accent : AppColors.fill,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(r.$2,
                            style: T.caption1(c: sel ? Colors.white : AppColors.textSecondary)
                                .copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  );
                }).toList(),
              ),

              if (_recurrenceKind == 'weekly') ...[
                const SizedBox(height: 10),
                Row(
                  children: List.generate(7, (i) {
                    final w = i + 1;
                    final sel = _weekdays.contains(w);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            if (sel) {
                              _weekdays.remove(w);
                            } else {
                              _weekdays.add(w);
                            }
                          });
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: sel ? AppColors.accentLight : AppColors.fill,
                            shape: BoxShape.circle,
                            border: sel
                                ? Border.all(color: AppColors.accent, width: 1.2)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            RecurrenceRule.weekdayCode(w).substring(0, 1),
                            style: T.caption1(
                                    c: sel ? AppColors.accent : AppColors.textSecondary)
                                .copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],

              if (_recurrenceKind == 'monthly') ...[
                const SizedBox(height: 10),
                Row(children: [
                  _pillButton('Day ${_dueDate.day} of every month', !_monthlyLast,
                      () => setState(() => _monthlyLast = false)),
                  const SizedBox(width: 6),
                  _pillButton('Last day of month', _monthlyLast,
                      () => setState(() => _monthlyLast = true)),
                ]),
              ],
              const SizedBox(height: 14),

              Row(children: [
                _label('SUBTASKS'),
                const Spacer(),
                GestureDetector(
                  onTap: _addSubtaskRow,
                  child: const Icon(Icons.add_circle_rounded,
                      size: 20, color: AppColors.primary),
                ),
              ]),
              if (_title.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _breakingDown ? null : _breakDownTask,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.pill)),
                    ),
                    icon: _breakingDown
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: Text('AI: Break this down',
                        style: T.caption1(c: AppColors.accent)
                            .copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              ...List.generate(_subtasks.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(
                      child: _box(TextField(
                        controller: _subtaskControllers[i],
                        style: T.body(),
                        decoration: _dec('Subtask'),
                      )),
                    ),
                    GestureDetector(
                      onTap: () => _removeSubtaskRow(i),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.close_rounded,
                            size: 18, color: AppColors.textMuted),
                      ),
                    ),
                  ]),
                );
              }),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
                  ),
                  child: Text(widget.existing == null ? 'Create Task' : 'Save Changes',
                      style: T.headline(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _pillButton(String text, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : AppColors.fill,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(text,
            style: T.caption1(c: sel ? Colors.white : AppColors.textSecondary)
                .copyWith(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s, style: T.sectionHeader()),
      );

  Widget _box(Widget child) => Container(
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: child,
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: T.body(c: AppColors.textHint),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
      );
}
