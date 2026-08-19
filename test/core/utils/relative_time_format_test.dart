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

  group('formatRelativeTime', () {
    final now = DateTime(2026, 7, 17, 12);

    test('returns "just now" under 60 seconds', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 30)), now: now),
        'just now',
      );
    });

    test('returns "1m ago" at exactly one minute', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 1)), now: now),
        '1m ago',
      );
    });

    test('returns "59m ago" just under an hour', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 59)), now: now),
        '59m ago',
      );
    });

    test('returns "1h ago" at exactly one hour', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 1)), now: now),
        '1h ago',
      );
    });

    test('returns "23h ago" just under a day', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 23)), now: now),
        '23h ago',
      );
    });

    test('returns "1d ago" at exactly one day', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 1)), now: now),
        '1d ago',
      );
    });

    test('returns "6d ago" just under a week', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 6)), now: now),
        '6d ago',
      );
    });

    test('returns "1w ago" at exactly seven days', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 7)), now: now),
        '1w ago',
      );
    });

    test('returns "4w ago" just under 30 days', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 29)), now: now),
        '4w ago',
      );
    });

    test('returns "1mo ago" at exactly 30 days', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 30)), now: now),
        '1mo ago',
      );
    });

    test('returns "3mo ago" well past 30 days', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 90)), now: now),
        '3mo ago',
      );
    });

    test('defaults now to DateTime.now() when omitted', () {
      expect(formatRelativeTime(DateTime.now()), 'just now');
    });
  });
}
