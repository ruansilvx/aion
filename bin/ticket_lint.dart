// bin/ticket_lint.dart — Standalone CLI: lint/reformat ticket Markdown files.
//
// Usage:
//   dart run bin/ticket_lint.dart <project-root> [--fix]
//
// Walks <project-root>/tickets/*.md, reporting each file's status:
//   ok                    — parses cleanly, no changes needed
//   reformatted           — had safe mechanical issues, fixed (only with --fix)
//   needs-fix             — has safe mechanical issues, not fixed (no --fix passed)
//   needs-repair-untouched — genuinely unparseable; use the in-app "restore
//                            from last known good" action instead
//
// Pure Dart, no Flutter/drift dependency — never touches the database.
// Shares its parse/reformat logic with the in-app repair action and the
// `ticket-lint` skill (see core/markdown/ticket_markdown_linter.dart),
// specifically so agentic/scripted repair calls stay cheap: this is a
// plain CLI invocation, not a skill invocation, for what's purely
// mechanical parsing.

import 'dart:io';

import 'package:aion/core/markdown/ticket_markdown_linter.dart';
import 'package:aion/core/markdown/ticket_markdown_parse_result.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final fix = args.contains('--fix');

  if (positional.isEmpty) {
    stderr.writeln('Usage: dart run bin/ticket_lint.dart <project-root> [--fix]');
    exitCode = 64; // EX_USAGE
    return;
  }

  final ticketsDir = Directory('${positional.first}/tickets');
  if (!await ticketsDir.exists()) {
    stderr.writeln('No tickets/ directory found under ${positional.first}');
    exitCode = 1;
    return;
  }

  final serializer = TicketMarkdownSerializer();
  var okCount = 0;
  var reformattedCount = 0;
  var needsFixCount = 0;
  var needsRepairCount = 0;

  await for (final entity in ticketsDir.list()) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;

    final original = await entity.readAsString();
    final result = serializer.parse(original);

    if (result is Unparseable) {
      needsRepairCount++;
      stdout.writeln('needs-repair-untouched  ${entity.path}');
      continue;
    }

    final reformatted = lintTicketMarkdown(original, serializer);
    if (reformatted == null || reformatted == original) {
      okCount++;
      stdout.writeln('ok                      ${entity.path}');
      continue;
    }

    if (fix) {
      await entity.writeAsString(reformatted);
      reformattedCount++;
      stdout.writeln('reformatted             ${entity.path}');
    } else {
      needsFixCount++;
      stdout.writeln('needs-fix               ${entity.path}');
    }
  }

  stdout.writeln(
    '\n$okCount ok, $reformattedCount reformatted, $needsFixCount '
    'need --fix, $needsRepairCount need manual repair.',
  );
  if (needsRepairCount > 0) exitCode = 1;
}
