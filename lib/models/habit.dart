// Habit domain model — free of package:flutter imports so the streak/date
// logic stays trivially unit-testable.

class Habit {
  final String id;
  final String title;
  final String emoji;
  final int colorValue; // an AppColors highlighter, stored as ARGB int
  final Set<String> completedDates; // yyyy-MM-dd keys
  final DateTime createdAt;

  const Habit({
    required this.id,
    required this.title,
    this.emoji = '🌱',
    required this.colorValue,
    this.completedDates = const {},
    required this.createdAt,
  });

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool isDoneOn(DateTime day) => completedDates.contains(dateKey(day));

  /// Current run of consecutive completed days ending today — or yesterday,
  /// so a streak stays "alive" until the day is actually missed.
  int currentStreak(DateTime asOf) {
    var day = DateTime(asOf.year, asOf.month, asOf.day);
    if (!isDoneOn(day)) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (isDoneOn(day)) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// How many days in the 7-day window starting [weekStart] are completed.
  int completionsInWeek(DateTime weekStart) {
    var n = 0;
    for (var i = 0; i < 7; i++) {
      if (isDoneOn(weekStart.add(Duration(days: i)))) n++;
    }
    return n;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'color': colorValue,
        'completedDates': completedDates.toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '🌱',
        colorValue: (j['color'] as num?)?.toInt() ?? 0xFFCDEFD8,
        completedDates: ((j['completedDates'] as List?) ?? const [])
            .map((e) => e as String)
            .toSet(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (j['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
      );

  Habit copyWith({
    String? title,
    String? emoji,
    int? colorValue,
    Set<String>? completedDates,
  }) =>
      Habit(
        id: id,
        title: title ?? this.title,
        emoji: emoji ?? this.emoji,
        colorValue: colorValue ?? this.colorValue,
        completedDates: completedDates ?? this.completedDates,
        createdAt: createdAt,
      );
}
