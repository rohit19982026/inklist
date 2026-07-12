import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/todo_task.dart';
import '../services/groq_service.dart';
import 'todo_editor_sheet.dart';

/// Single-field natural-language quick-add. "Parse with AI" pre-fills
/// TodoEditorSheet (which itself is the review/confirm step — no separate
/// preview UI needed here); "Enter manually instead" is the guaranteed
/// fallback when AI is unavailable or the user prefers not to use it.
class NlQuickAddSheet extends StatefulWidget {
  const NlQuickAddSheet({super.key});

  /// Returns the saved task, or null if the whole flow was dismissed.
  static Future<TodoTask?> show(BuildContext context) {
    return showModalBottomSheet<TodoTask>(
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
    final result = await GroqService.parseQuickAdd(text);
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
    final task = await TodoEditorSheet.show(context,
        existing: result.data!.toTodoTask());
    if (!mounted) return;
    Navigator.pop(context, task);
  }

  Future<void> _enterManually() async {
    final task = await TodoEditorSheet.show(context);
    if (!mounted) return;
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
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('Quick Add', style: T.title3()),
              ]),
              const SizedBox(height: 6),
              Text(
                'Describe it your way — AI will figure out the date, time and repeat.',
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
                    hintText: 'e.g. remind me to pay rent every 1st of the month',
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
            ],
          ),
        ),
      ),
    );
  }
}
