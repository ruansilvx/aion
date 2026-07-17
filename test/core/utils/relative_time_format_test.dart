import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';

void main() {
  group('formatTrashedAge', () {
    final now = DateTime(2026, 7, 17, 12);

    test('returns "Trashed today" for the same calendar day', () {
      expect(
        formatTrashedAge(DateTime(2026, 7, 17, 2), now: now),
        'Trashed today',
      );
    });

    test('returns "Trashed yesterday" for the previous calendar day', () {
      expect(
        formatTrashedAge(DateTime(2026, 7, 16, 23), now: now),
        'Trashed yesterday',
      );
    });

    test('returns "Trashed N days ago" under two weeks', () {
      expect(
        formatTrashedAge(DateTime(2026, 7, 5, 12), now: now),
        'Trashed 12 days ago',
      );
    });

    test('returns "Trashed N weeks ago" between 14 and 29 days', () {
      expect(
        formatTrashedAge(DateTime(2026, 6, 27, 12), now: now),
        'Trashed 2 weeks ago',
      );
    });

    test('returns singular "Trashed 1 month ago" for 30-59 days', () {
      expect(
        formatTrashedAge(DateTime(2026, 6, 1, 12), now: now),
        'Trashed 1 month ago',
      );
    });

    test('returns "Trashed N months ago" at 60+ days', () {
      expect(
        formatTrashedAge(DateTime(2026, 4, 18, 12), now: now),
        'Trashed 3 months ago',
      );
    });

    test('defaults now to DateTime.now() when omitted', () {
      expect(formatTrashedAge(DateTime.now()), 'Trashed today');
    });
  });
}
