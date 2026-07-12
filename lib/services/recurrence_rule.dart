/// Pure recurrence-rule parsing/evaluation — no I/O, fully unit-testable.
///
/// Grammar: 'none' | 'daily' | 'weekly:MON,WED,FRI' | 'monthly:1'..'monthly:28'
/// | 'monthly:last'. Deliberately narrow (4 patterns) rather than a full
/// RFC 5545 RRULE parser, since that's all a personal to-do list needs.
class RecurrenceRule {
  RecurrenceRule._();

  static const _weekdayCodes = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  static bool occursOn(String rule, DateTime day) {
    if (rule == 'none') return false;
    if (rule == 'daily') return true;
    if (rule.startsWith('weekly:')) {
      final codes = rule.substring(7).split(',').map((c) => c.trim()).toSet();
      return codes.contains(_weekdayCodes[day.weekday - 1]);
    }
    if (rule.startsWith('monthly:')) {
      final spec = rule.substring(8);
      if (spec == 'last') return day.day == lastDayOfMonth(day).day;
      final dayOfMonth = int.tryParse(spec);
      return dayOfMonth != null && day.day == dayOfMonth;
    }
    return false;
  }

  static DateTime lastDayOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

  static String weekdayCode(int weekday) => _weekdayCodes[weekday - 1];
}
