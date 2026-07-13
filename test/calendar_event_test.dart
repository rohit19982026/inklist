import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/models/calendar_event.dart';

void main() {
  group('CalendarEvent.fromJson', () {
    test('parses a timed event and normalizes it to local time', () {
      final json = {
        'summary': 'Team standup',
        'start': {'dateTime': '2026-07-13T09:00:00+05:30'},
        'end': {'dateTime': '2026-07-13T09:30:00+05:30'},
      };
      final event = CalendarEvent.fromJson(json);
      expect(event.title, 'Team standup');
      expect(event.allDay, isFalse);
      // Timezone-independent: check the represented instant is correct
      // (matches the source offset) rather than a hardcoded local hour,
      // which would depend on the test runner's own timezone.
      expect(event.start.isAtSameMomentAs(DateTime.parse('2026-07-13T09:00:00+05:30')),
          isTrue);
      expect(event.start.isUtc, isFalse);
      expect(event.end.difference(event.start), const Duration(minutes: 30));
    });

    test('parses an all-day event using the date field', () {
      final json = {
        'summary': 'Company holiday',
        'start': {'date': '2026-07-15'},
        'end': {'date': '2026-07-16'},
      };
      final event = CalendarEvent.fromJson(json);
      expect(event.title, 'Company holiday');
      expect(event.allDay, isTrue);
      expect(event.start, DateTime(2026, 7, 15));
      expect(event.end, DateTime(2026, 7, 16));
    });

    test('falls back to a placeholder title when summary is missing', () {
      final json = {
        'start': {'date': '2026-07-15'},
        'end': {'date': '2026-07-16'},
      };
      final event = CalendarEvent.fromJson(json);
      expect(event.title, '(No title)');
    });

    test('falls back to a placeholder title when summary is blank', () {
      final json = {
        'summary': '   ',
        'start': {'dateTime': '2026-07-13T09:00:00+05:30'},
        'end': {'dateTime': '2026-07-13T09:30:00+05:30'},
      };
      final event = CalendarEvent.fromJson(json);
      expect(event.title, '(No title)');
    });
  });
}
