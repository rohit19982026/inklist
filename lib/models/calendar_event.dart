/// One Google Calendar event, as shown (read-only) alongside InkList tasks.
/// Deliberately minimal — this app never writes back to the user's calendar.
class CalendarEvent {
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  const CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
  });

  /// Parses one entry from the Calendar API v3 `events.list` response.
  /// Timed events use `start.dateTime`/`end.dateTime` (RFC3339); all-day
  /// events use `start.date`/`end.date` (yyyy-MM-dd, no time component).
  /// Timed values carry their own UTC offset, which `DateTime.parse` keeps
  /// as UTC rather than converting — `.toLocal()` puts them in the same
  /// local wall-clock terms as every other DateTime in this app (task due
  /// dates, alarm times), so `.hour`/`.minute` and `TimeOfDay.fromDateTime`
  /// display correctly instead of showing UTC time.
  factory CalendarEvent.fromJson(Map<String, dynamic> j) {
    final startObj = j['start'] as Map<String, dynamic>? ?? const {};
    final endObj = j['end'] as Map<String, dynamic>? ?? const {};
    final startDateTime = startObj['dateTime'] as String?;
    final endDateTime = endObj['dateTime'] as String?;
    final allDay = startDateTime == null;
    final start = (startDateTime != null
            ? DateTime.parse(startDateTime)
            : DateTime.parse(startObj['date'] as String? ?? '1970-01-01'))
        .toLocal();
    final end = (endDateTime != null
            ? DateTime.parse(endDateTime)
            : DateTime.parse(endObj['date'] as String? ?? '1970-01-01'))
        .toLocal();
    return CalendarEvent(
      title: (j['summary'] as String?)?.trim().isNotEmpty == true
          ? (j['summary'] as String).trim()
          : '(No title)',
      start: start,
      end: end,
      allDay: allDay,
    );
  }
}
