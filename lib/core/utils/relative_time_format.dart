// core/utils/relative_time_format.dart — Trashed-ticket age formatting helper (core layer).

/// Formats how long ago [deletedAt] happened as a short label prefixed
/// `'Trashed '` (e.g. `'Trashed today'`, `'Trashed yesterday'`,
/// `'Trashed 12 days ago'`, `'Trashed 3 weeks ago'`, `'Trashed 2 months
/// ago'`). [now] defaults to [DateTime.now] and only exists as a
/// parameter for deterministic tests.
String formatTrashedAge(DateTime deletedAt, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final elapsedDays = _dayDifference(deletedAt, today);

  if (elapsedDays <= 0) return 'Trashed today';
  if (elapsedDays == 1) return 'Trashed yesterday';
  if (elapsedDays < 14) return 'Trashed $elapsedDays days ago';
  if (elapsedDays < 30) {
    final weeks = elapsedDays ~/ 7;
    return 'Trashed $weeks week${weeks == 1 ? '' : 's'} ago';
  }
  final months = elapsedDays ~/ 30;
  return 'Trashed $months month${months == 1 ? '' : 's'} ago';
}

/// Whole calendar days between [from] and [to], ignoring time-of-day.
int _dayDifference(DateTime from, DateTime to) {
  final fromDay = DateTime(from.year, from.month, from.day);
  final toDay = DateTime(to.year, to.month, to.day);
  return toDay.difference(fromDay).inDays;
}
