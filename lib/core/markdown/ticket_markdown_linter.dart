// core/markdown/ticket_markdown_linter.dart — Ticket Markdown lint/reformat (core layer).

import 'package:aion/core/markdown/ticket_markdown_parse_result.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';

/// Attempts a safe, mechanical reformat of raw ticket Markdown [content].
///
/// Deliberately conservative: the only fix applied is trailing-whitespace
/// trimming on every line, and only when [content] already parses as
/// [ParsedOk] or [ParsedPartial] (i.e. the frontmatter block itself is
/// structurally sound). If [content] is genuinely [Unparseable] — a
/// missing/malformed frontmatter block — this returns `null` rather than
/// guessing at a repair; reconstructing broken YAML with any confidence
/// is out of scope for a "purely mechanical" tool. The caller (
/// `TicketRepairService`/`bin/ticket_lint.dart`) should fall back to
/// restore-from-last-known-good in that case.
///
/// DB-agnostic and pure Dart — shared by `TicketRepairService` (data
/// layer, DB-aware) and `bin/ticket_lint.dart` (standalone CLI, no DB
/// access at all).
String? lintTicketMarkdown(
  String content,
  TicketMarkdownSerializer serializer,
) {
  final trimmed = content
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+$'), ''))
      .join('\n');

  final result = serializer.parse(trimmed);
  if (result is Unparseable) return null;
  return trimmed;
}
