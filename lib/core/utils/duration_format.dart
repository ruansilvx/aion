// core/utils/duration_format.dart — Minute-duration formatting/parsing helpers (core layer).

/// Formats [minutes] as a short human label (e.g. `'2h 30m'`, `'45m'`,
/// `'3h'`). Returns [placeholder] for `null` or non-positive input.
String formatDurationMinutes(int? minutes, {String placeholder = 'Not set'}) {
  if (minutes == null || minutes <= 0) return placeholder;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// Parses a free-form duration string (e.g. `'2h30m'`, `'2h 30m'`,
/// `'90m'`, `'2h'`, or a bare number of minutes like `'90'`) into total
/// minutes. Blank input returns `null` (no estimate/time). Throws
/// [FormatException] for anything else unrecognised.
int? parseDurationMinutes(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final match = RegExp(r'^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?$', caseSensitive: false)
      .firstMatch(trimmed);
  if (match != null && (match.group(1) != null || match.group(2) != null)) {
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final mins = int.tryParse(match.group(2) ?? '0') ?? 0;
    return hours * 60 + mins;
  }

  final bare = int.tryParse(trimmed);
  if (bare != null) return bare;

  throw FormatException('Not a valid duration: "$input"');
}
