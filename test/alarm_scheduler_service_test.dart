import 'package:flutter_test/flutter_test.dart';
import 'package:inklist/services/alarm_scheduler_service.dart';

void main() {
  group('javaStringHashCode', () {
    test('matches known Java String.hashCode() reference values', () {
      expect(javaStringHashCode(''), 0);
      expect(javaStringHashCode('a'), 97);
      expect(javaStringHashCode('hello'), 99162322);
      expect(javaStringHashCode('InkList'), -681315964);
    });

    test('differs from Dart\'s built-in String.hashCode (the whole point)', () {
      // If these ever accidentally matched it wouldn't be wrong, but the
      // native Kotlin side always uses the Java algorithm — this pins down
      // that the port is doing real work, not silently falling through to
      // Dart's own hashCode.
      const taskId = '1752378962345123';
      expect(javaStringHashCode(taskId), isNot(taskId.hashCode));
    });

    test('always fits a signed 32-bit int, even for long strings', () {
      final long = 'x' * 500;
      final hash = javaStringHashCode(long);
      expect(hash, greaterThanOrEqualTo(-2147483648));
      expect(hash, lessThanOrEqualTo(2147483647));
    });

    test('is deterministic and stable across calls', () {
      const taskId = '1752378962345123';
      expect(javaStringHashCode(taskId), javaStringHashCode(taskId));
    });
  });
}
