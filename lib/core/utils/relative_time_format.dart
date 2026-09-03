// core/utils/relative_time_format.dart — Relative-time formatting helpers (core layer).

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

/// Formats how long ago [dateTime] happened as a short, generic label
/// (`"just now"`, `"2h ago"`, `"3d ago"`, `"2w ago"`, `"3mo ago"`) — used by
/// `InboxHistoryItem`'s timestamp (design.md §5.3), unlike
/// [formatTrashedAge]'s trash-specific `"Trashed ..."` phrasing. [now]
/// defaults to [DateTime.now] and only exists as a parameter for deterministic
/// tests. Added for `AIO-1300`.
String formatRelativeTime(DateTime dateTime, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final elapsed = current.difference(dateTime);

  if (elapsed.inSeconds < 60) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  if (elapsed.inDays < 30) return '${elapsed.inDays ~/ 7}w ago';
  return '${elapsed.inDays ~/ 30}mo ago';
}
