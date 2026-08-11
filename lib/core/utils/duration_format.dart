// core/utils/duration_format.dart — Minute-duration formatting/parsing helpers (core layer).

/// Formats [minutes] as a short human label (e.g. `'2h 30m'`, `'45m'`,
/// `'3h'`). Returns [placeholder] for `null` or non-positive input.
/// [placeholder] has no default so callers must supply localized text
/// explicitly — this function has no [BuildContext] to resolve one itself.
String formatDurationMinutes(int? minutes, {required String placeholder}) {
  if (minutes == null || minutes <= 0) return placeholder;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// Compact human-readable duration for a rollup total. Input: whole
/// minutes, `>= 0`. Unlike [formatDurationMinutes], `0` renders as
/// `'0m'` rather than falling back to a placeholder — a rollup with live
/// children but no set values is still a real (zero) total, not an
/// absent one; the "nothing to roll up" case is handled by gating the
/// rollup UI on `Ticket.estimateRollup`/`.timeSpentRollup` being
/// non-null before this is ever called, not by this formatter. Thin
/// wrapper over [formatDurationMinutes] with `'0m'` as the placeholder,
/// so both share one h/m formatting rule.
String formatRollupMinutes(int minutes) =>
    formatDurationMinutes(minutes, placeholder: '0m');

/// Parses a free-form duration string (e.g. `'2h30m'`, `'2h 30m'`,
/// `'90m'`, `'2h'`, or a bare number of minutes like `'90'`) into total
/// minutes. Blank input returns `null` (no estimate/time). Throws
/// [FormatException] for anything else unrecognised.
int? parseDurationMinutes(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final match = RegExp(
    r'^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match != null && (match.group(1) != null || match.group(2) != null)) {
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final mins = int.tryParse(match.group(2) ?? '0') ?? 0;
    return hours * 60 + mins;
  }

  final bare = int.tryParse(trimmed);
  if (bare != null) return bare;

  throw FormatException('Not a valid duration: "$input"');
}
