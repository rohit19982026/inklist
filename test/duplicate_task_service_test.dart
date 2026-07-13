import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/models/todo_task.dart';
import 'package:inklist/services/duplicate_task_service.dart';

void main() {
  TodoTask task(String title, {bool completed = false}) => TodoTask(
        id: title,
        title: title,
        dueDate: DateTime(2026, 7, 13),
        isCompleted: completed,
        createdAt: DateTime(2026, 7, 13),
      );

  group('DuplicateTaskService.findLikelyDuplicate', () {
    test('flags near-identical titles differing only by stopwords/case', () {
      final existing = [task('Call dentist')];
      final match = DuplicateTaskService.findLikelyDuplicate(
          'call the dentist', existing);
      expect(match?.title, 'Call dentist');
    });

    test('does not flag genuinely different titles', () {
      final existing = [task('Buy milk')];
      final match =
          DuplicateTaskService.findLikelyDuplicate('Buy bread', existing);
      expect(match, isNull);
    });

    test('returns null for an empty title', () {
      final existing = [task('Call dentist')];
      final match = DuplicateTaskService.findLikelyDuplicate('', existing);
      expect(match, isNull);
    });

    test('returns null when there are no candidates', () {
      final match = DuplicateTaskService.findLikelyDuplicate('Call dentist', []);
      expect(match, isNull);
    });

    test('picks the best match among several candidates', () {
      final existing = [task('Buy bread'), task('Call the dentist today')];
      final match = DuplicateTaskService.findLikelyDuplicate(
          'call dentist', existing);
      expect(match?.title, 'Call the dentist today');
    });
  });
}
