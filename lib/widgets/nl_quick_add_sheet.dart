import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/todo_task.dart';
import '../models/quick_add_draft.dart';
import '../services/groq_service.dart';
import '../services/todo_service.dart';
import '../services/duplicate_task_service.dart';
import 'todo_editor_sheet.dart';

/// Natural-language quick-add. "Parse with AI" can return one task or
/// several (e.g. "buy milk, call mom tomorrow, and finish the report by
/// Friday") — a single task skips straight to TodoEditorSheet as the
/// review/confirm step (unchanged from before); multiple tasks show an
/// inline preview list first. "Enter manually instead" is the guaranteed
/// fallback when AI is unavailable or the user prefers not to use it.
class NlQuickAddSheet extends StatefulWidget {
  const NlQuickAddSheet({super.key});

  /// Returns the tasks to save, or null if the whole flow was dismissed.
  static Future<List<TodoTask>?> show(BuildContext context) {
    return showModalBottomSheet<List<TodoTask>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NlQuickAddSheet(),
    );
  }

  @override
  State<NlQuickAddSheet> createState() => _NlQuickAddSheetState();
}

class _NlQuickAddSheetState extends State<NlQuickAddSheet> {
  final _text = TextEditingController();
  bool _parsing = false;

  // Non-null once AI parses 2+ tasks — switches the sheet into preview mode.
  List<QuickAddDraft>? _multiDrafts;
  Set<int> _checked = {};
  Map<int, TodoTask?> _duplicates = {};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _parseWithAi() async {
    final text = _text.text.trim();
    if (text.isEmpty || _parsing) return;
    HapticFeedback.lightImpact();
    setState(() => _parsing = true);
    final result = await GroqService.parseQuickAddMulti(text);
    if (!mounted) return;
    setState(() => _parsing = false);
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Could not understand that',
            style: T.footnote(c: Colors.white)),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ));
      return;
    }
    final drafts = result.data!;
    if (drafts.length == 1) {
      final task = await TodoEditorSheet.show(context,
          existing: drafts.first.toTodoTask());
      if (!mounted) return;
      Navigator.pop(context, task == null ? null : [task]);
      return;
    }
    await _enterPreviewMode(drafts);
  }

  Future<void> _enterPreviewMode(List<QuickAddDraft> drafts) async {
    final existingTasks = await TodoService.getAll();
    final openTasks =
        existingTasks.where((t) => t.isRecurring || !t.isCompleted).toList();
    final duplicates = <int, TodoTask?>{};
    for (var i = 0; i < drafts.length; i++) {
      duplicates[i] =
          DuplicateTaskService.findLikelyDuplicate(drafts[i].title, openTasks);
    }
    if (!mounted) return;
    setState(() {
      _multiDrafts = drafts;
      _checked = Set.of(List.generate(drafts.length, (i) => i));
      _duplicates = duplicates;
    });
  }

  Future<void> _editRow(int i) async {
    final drafts = _multiDrafts;
    if (drafts == null) return;
    final edited = await TodoEditorSheet.show(context,
        existing: drafts[i].toTodoTask());
    if (edited == null || !mounted) return;
    setState(() {
      final updated = List<QuickAddDraft>.from(drafts);
      updated[i] = QuickAddDraft(
        title: edited.title,
        dueDate: edited.dueDate,
        time: edited.alarmTime,
        recurrence: edited.recurrenceRule,
        priority: edited.priority,
      );
      _multiDrafts = updated;
    });
  }

  void _confirmChecked() {
    final drafts = _multiDrafts;
    if (drafts == null) return;
    final tasks = [
      for (var i = 0; i < drafts.length; i++)
        if (_checked.contains(i)) drafts[i].toTodoTask(),
    ];
    Navigator.pop(context, tasks.isEmpty ? null : tasks);
  }

  Future<void> _enterManually() async {
    final task = await TodoEditorSheet.show(context);
    if (!mounted) return;
    Navigator.pop(context, task == null ? null : [task]);
  }

  @override
  Widget build(BuildContext context) {
    final drafts = _multiDrafts;
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
              if (drafts == null) ..._buildInput() else ..._buildPreview(drafts),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildInput() {
    return [
      Row(children: [
        const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Text('Quick Add', style: T.title3()),
      ]),
      const SizedBox(height: 6),
      Text(
        'Describe it your way — AI will figure out the date, time and repeat. '
        'You can list more than one thing at once.',
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
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: T.body(),
          decoration: InputDecoration(
            hintText: 'e.g. buy milk, call mom tomorrow, and pay rent on the 1st',
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
          onPressed: _parsing ? null : _parseWithAi,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.lg)),
          ),
          icon: _parsing
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          label: Text('Parse with AI', style: T.headline(color: Colors.white)),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: _parsing ? null : _enterManually,
          child: Text('Enter manually instead',
              style: T.footnote(c: AppColors.textSecondary)),
        ),
      ),
    ];
  }

  List<Widget> _buildPreview(List<QuickAddDraft> drafts) {
    return [
      Row(children: [
        const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Text('${drafts.length} tasks found', style: T.title3()),
      ]),
      const SizedBox(height: 6),
      Text('Uncheck anything you don\'t want, or tap to edit first.',
          style: T.footnote()),
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: drafts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _draftRow(i, drafts[i]),
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _checked.isEmpty ? null : _confirmChecked,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.lg)),
          ),
          child: Text('Add ${_checked.length} task${_checked.length == 1 ? '' : 's'}',
              style: T.headline(color: Colors.white)),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: () => setState(() {
            _multiDrafts = null;
            _checked = {};
            _duplicates = {};
          }),
          child: Text('Start over', style: T.footnote(c: AppColors.textSecondary)),
        ),
      ),
    ];
  }

  Widget _draftRow(int i, QuickAddDraft draft) {
    final checked = _checked.contains(i);
    final duplicate = _duplicates[i];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(children: [
        Checkbox(
          value: checked,
          activeColor: AppColors.primary,
          onChanged: (v) => setState(() {
            if (v == true) {
              _checked.add(i);
            } else {
              _checked.remove(i);
            }
          }),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(draft.title,
                  style: T.body().copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '${DateFormat('d MMM').format(draft.dueDate)}'
                '${draft.time != null ? ' · ${TimeOfDay(hour: draft.time!.hour, minute: draft.time!.minute).format(context)}' : ''}'
                ' · ${draft.priority}',
                style: T.caption2(c: AppColors.textMuted),
              ),
              if (duplicate != null) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.content_copy_rounded,
                      size: 12, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Similar to "${duplicate.title}"',
                        style: T.caption2(c: AppColors.warning),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ],
            ],
          ),
        ),
        GestureDetector(
          onTap: () => _editRow(i),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.edit_rounded, size: 18, color: AppColors.textSecondary),
          ),
        ),
      ]),
    );
  }
}
