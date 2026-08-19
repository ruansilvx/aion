// core/markdown/ticket_markdown_parse_result.dart — TicketMarkdownParseResult sealed type (core layer).

/// Outcome of [TicketMarkdownSerializer.parse]. Exactly one of
/// [ParsedOk], [ParsedPartial], or [Unparseable].
sealed class TicketMarkdownParseResult {
  const TicketMarkdownParseResult();
}

/// Every frontmatter field parsed and validated successfully.
class ParsedOk extends TicketMarkdownParseResult {
  /// Creates a [ParsedOk] with every field successfully parsed.
  const ParsedOk({
    required this.fields,
    required this.title,
    required this.body,
  });

  /// Parsed frontmatter, keyed by [TicketMarkdownTemplate] field name.
  /// Values are already converted to their target Dart type (e.g. a
  /// `type` field's value is the `TicketType` enum, not the raw string —
  /// `status` is itself already a plain, project-defined `String`, so no
  /// conversion happens for it beyond the non-empty check).
  final Map<String, Object?> fields;

  /// The ticket's title, extracted from the body's leading `# ` heading.
  final String title;

  /// The ticket's description — the body content after the title heading.
  final String body;
}

/// Frontmatter parsed as valid YAML, but one or more fields failed
/// validation (e.g. a `type` value that isn't a known `TicketType` name,
/// or a `status` value that's missing/empty). Valid fields are usable
/// as-is; invalid ones are named so the
/// caller can keep the database's last value for just those fields
/// instead of rejecting the whole update.
class ParsedPartial extends TicketMarkdownParseResult {
  /// Creates a [ParsedPartial] result.
  const ParsedPartial({
    required this.validFields,
    required this.invalidFieldNames,
    required this.title,
    required this.body,
  });

  /// Successfully parsed and validated fields, keyed by
  /// [TicketMarkdownTemplate] field name.
  final Map<String, Object?> validFields;

  /// Names of frontmatter fields present but invalid — the caller should
  /// retain the database's existing value for each of these.
  final Set<String> invalidFieldNames;

  /// The ticket's title, extracted from the body's leading `# ` heading.
  /// Title/body extraction is independent of frontmatter validity, so
  /// this is always populated even when some frontmatter fields aren't.
  final String title;

  /// The ticket's description — the body content after the title heading.
  final String body;
}

/// The frontmatter block itself is missing or not valid YAML. Nothing is
/// usable — the caller must not write to the database or overwrite the
/// file (either action could destroy data: writing garbage to the DB, or
/// clobbering a user's in-progress hand edit).
class Unparseable extends TicketMarkdownParseResult {
  /// Creates an [Unparseable] result explaining [reason].
  const Unparseable(this.reason);

  /// Human-readable explanation of why parsing failed, suitable for
  /// surfacing in a "needs repair" UI.
  final String reason;
}
