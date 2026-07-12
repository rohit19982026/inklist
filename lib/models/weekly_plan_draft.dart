/// Editable draft of one AI-suggested task within the weekly plan preview.
/// Mutable by design — the preview screen binds these fields directly to
/// TextEditingControllers/pills before the user confirms and they become
/// real TodoTasks.
class WeeklyPlanTaskDraft {
  String title;
  String? time; // "HH:MM" or null
  String priority; // 'low' | 'medium' | 'high'

  WeeklyPlanTaskDraft({required this.title, this.time, this.priority = 'medium'});
}

/// Parsed, editable representation of a Groq weekly-plan response.
/// Never auto-saved — always reviewed/edited by the user before becoming
/// real TodoTasks.
class WeeklyPlanDraft {
  static const dayOrder = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];

  /// Keyed by lowercase weekday name; only days with tasks are present.
  final Map<String, List<WeeklyPlanTaskDraft>> days;

  const WeeklyPlanDraft({required this.days});

  int get totalTaskCount => days.values.fold(0, (s, list) => s + list.length);

  factory WeeklyPlanDraft.fromJson(Map<String, dynamic> j) {
    final rawDays = (j['days'] as Map<String, dynamic>?) ?? const {};
    final out = <String, List<WeeklyPlanTaskDraft>>{};
    for (final day in dayOrder) {
      final list = rawDays[day] as List?;
      if (list == null || list.isEmpty) continue;
      out[day] = list
          .whereType<Map>()
          .map((e) => WeeklyPlanTaskDraft(
                title: (e['title'] as String?)?.trim() ?? '',
                time: e['time'] as String?,
                priority: e['priority'] as String? ?? 'medium',
              ))
          .where((t) => t.title.isNotEmpty)
          .toList();
      if (out[day]!.isEmpty) out.remove(day);
    }
    return WeeklyPlanDraft(days: out);
  }
}
