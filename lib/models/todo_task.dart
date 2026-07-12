/// A to-do task — one-off or recurring. Recurring tasks store a single
/// [recurrenceRule] plus a [completedDates] set (yyyy-MM-dd keys) rather
/// than materializing one row per future occurrence, since the whole list
/// round-trips through jsonEncode/jsonDecode on every write.
class TodoTask {
  final String id;
  final String title;
  final String? description;
  final DateTime dueDate;
  final TimeOfDayMs? alarmTime;
  final String priority; // 'low' | 'medium' | 'high'
  final bool isCompleted;
  final DateTime? completedAt;
  final bool alarmEnabled;
  final String recurrenceRule; // 'none' | 'daily' | 'weekly:MON,...' | 'monthly:N' | 'monthly:last'
  final Set<String> completedDates;
  final List<TodoSubtask> subtasks;
  final bool aiGenerated;
  final DateTime createdAt;

  const TodoTask({
    required this.id,
    required this.title,
    this.description,
    required this.dueDate,
    this.alarmTime,
    this.priority = 'medium',
    this.isCompleted = false,
    this.completedAt,
    this.alarmEnabled = false,
    this.recurrenceRule = 'none',
    this.completedDates = const {},
    this.subtasks = const [],
    this.aiGenerated = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'dueDate': dueDate.millisecondsSinceEpoch,
        'alarmTime': alarmTime?.toJson(),
        'priority': priority,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'alarmEnabled': alarmEnabled,
        'recurrenceRule': recurrenceRule,
        'completedDates': completedDates.toList(),
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'aiGenerated': aiGenerated,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory TodoTask.fromJson(Map<String, dynamic> j) => TodoTask(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        description: j['description'] as String?,
        dueDate: DateTime.fromMillisecondsSinceEpoch(
            j['dueDate'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        alarmTime: j['alarmTime'] != null
            ? TimeOfDayMs.fromJson(j['alarmTime'] as Map<String, dynamic>)
            : null,
        priority: j['priority'] as String? ?? 'medium',
        isCompleted: j['isCompleted'] as bool? ?? false,
        completedAt: j['completedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['completedAt'] as int)
            : null,
        alarmEnabled: j['alarmEnabled'] as bool? ?? false,
        recurrenceRule: j['recurrenceRule'] as String? ?? 'none',
        completedDates: ((j['completedDates'] as List?) ?? const [])
            .map((e) => e as String)
            .toSet(),
        subtasks: ((j['subtasks'] as List?) ?? const [])
            .map((e) => TodoSubtask.fromJson(e as Map<String, dynamic>))
            .toList(),
        aiGenerated: j['aiGenerated'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            j['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
      );

  TodoTask copyWith({
    String? title,
    String? description,
    DateTime? dueDate,
    TimeOfDayMs? alarmTime,
    String? priority,
    bool? isCompleted,
    DateTime? completedAt,
    bool? alarmEnabled,
    String? recurrenceRule,
    Set<String>? completedDates,
    List<TodoSubtask>? subtasks,
    bool? aiGenerated,
    bool clearAlarmTime = false,
    bool clearDescription = false,
    bool clearCompletedAt = false,
  }) =>
      TodoTask(
        id: id,
        title: title ?? this.title,
        description:
            clearDescription ? null : (description ?? this.description),
        dueDate: dueDate ?? this.dueDate,
        alarmTime: clearAlarmTime ? null : (alarmTime ?? this.alarmTime),
        priority: priority ?? this.priority,
        isCompleted: isCompleted ?? this.isCompleted,
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
        alarmEnabled: alarmEnabled ?? this.alarmEnabled,
        recurrenceRule: recurrenceRule ?? this.recurrenceRule,
        completedDates: completedDates ?? this.completedDates,
        subtasks: subtasks ?? this.subtasks,
        aiGenerated: aiGenerated ?? this.aiGenerated,
        createdAt: createdAt,
      );

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool get isRecurring => recurrenceRule != 'none';

  bool isCompletedOn(DateTime day) =>
      isRecurring ? completedDates.contains(dateKey(day)) : isCompleted;

  double get subtaskProgress => subtasks.isEmpty
      ? 0
      : subtasks.where((s) => s.done).length / subtasks.length;
}

class TodoSubtask {
  final String id;
  final String title;
  final bool done;

  const TodoSubtask({required this.id, required this.title, this.done = false});

  factory TodoSubtask.fromJson(Map<String, dynamic> j) => TodoSubtask(
        id: j['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title: j['title'] as String? ?? '',
        done: j['done'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};

  TodoSubtask copyWith({String? title, bool? done}) =>
      TodoSubtask(id: id, title: title ?? this.title, done: done ?? this.done);
}

/// Deliberately not Flutter's TimeOfDay, so this model file stays free of
/// package:flutter imports and trivially unit-testable.
class TimeOfDayMs {
  final int hour;
  final int minute;

  const TimeOfDayMs({required this.hour, required this.minute});

  factory TimeOfDayMs.fromJson(Map<String, dynamic> j) => TimeOfDayMs(
        hour: j['h'] as int? ?? 9,
        minute: j['m'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {'h': hour, 'm': minute};
}
