import 'todo_task.dart';

/// Parsed representation of a Groq natural-language quick-add response.
/// Used to prefill TodoEditorSheet for the user to review/edit/confirm —
/// never saved directly.
class QuickAddDraft {
  final String title;
  final DateTime dueDate;
  final TimeOfDayMs? time;
  final String recurrence; // matches TodoTask.recurrenceRule grammar
  final String priority;

  const QuickAddDraft({
    required this.title,
    required this.dueDate,
    this.time,
    this.recurrence = 'none',
    this.priority = 'medium',
  });

  factory QuickAddDraft.fromJson(Map<String, dynamic> j) {
    DateTime due;
    try {
      due = DateTime.parse(j['dueDate'] as String);
    } catch (_) {
      final now = DateTime.now();
      due = DateTime(now.year, now.month, now.day);
    }
    TimeOfDayMs? time;
    final t = j['time'] as String?;
    if (t != null && t.contains(':')) {
      final parts = t.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) time = TimeOfDayMs(hour: h, minute: m);
    }
    return QuickAddDraft(
      title: (j['title'] as String?)?.trim() ?? '',
      dueDate: due,
      time: time,
      recurrence: j['recurrence'] as String? ?? 'none',
      priority: j['priority'] as String? ?? 'medium',
    );
  }

  TodoTask toTodoTask() => TodoTask(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        dueDate: dueDate,
        alarmTime: time,
        priority: priority,
        recurrenceRule: recurrence,
        aiGenerated: true,
        createdAt: DateTime.now(),
      );
}
