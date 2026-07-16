import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';

void main() {
  group('formatDurationMinutes', () {
    test('returns placeholder for null', () {
      expect(formatDurationMinutes(null, placeholder: 'Not set'), 'Not set');
    });

    test('returns placeholder for zero', () {
      expect(formatDurationMinutes(0, placeholder: 'Not set'), 'Not set');
    });

    test('returns placeholder for negative', () {
      expect(formatDurationMinutes(-5, placeholder: 'Not set'), 'Not set');
    });

    test('uses a custom placeholder when given', () {
      expect(
        formatDurationMinutes(null, placeholder: 'Add an estimate…'),
        'Add an estimate…',
      );
    });

    test('formats minutes-only durations', () {
      expect(formatDurationMinutes(45, placeholder: 'Not set'), '45m');
    });

    test('formats whole-hour durations', () {
      expect(formatDurationMinutes(120, placeholder: 'Not set'), '2h');
    });

    test('formats mixed hour+minute durations', () {
      expect(formatDurationMinutes(150, placeholder: 'Not set'), '2h 30m');
    });
  });

  group('parseDurationMinutes', () {
    test('parses "2h30m"', () {
      expect(parseDurationMinutes('2h30m'), 150);
    });

    test('parses "2h 30m"', () {
      expect(parseDurationMinutes('2h 30m'), 150);
    });

    test('parses "90m"', () {
      expect(parseDurationMinutes('90m'), 90);
    });

    test('parses "2h"', () {
      expect(parseDurationMinutes('2h'), 120);
    });

    test('parses a bare number as minutes', () {
      expect(parseDurationMinutes('90'), 90);
    });

    test('returns null for empty input', () {
      expect(parseDurationMinutes(''), isNull);
    });

    test('returns null for whitespace-only input', () {
      expect(parseDurationMinutes('   '), isNull);
    });

    test('throws FormatException for unparseable input', () {
      expect(() => parseDurationMinutes('abc'), throwsFormatException);
    });
  });
}
