// core/markdown/ticket_markdown_serializer.dart — TicketMarkdownSerializer (core layer).

import 'package:yaml/yaml.dart';

import 'package:aion/core/markdown/ticket_markdown_parse_result.dart';
import 'package:aion/core/markdown/ticket_markdown_template.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Converts between a [Ticket] and its Markdown-with-YAML-frontmatter
/// file representation, per the schema in [TicketMarkdownTemplate].
///
/// [title] is modelled as the body's leading `# ` heading rather than a
/// frontmatter field — design.md's frontmatter example omitted `title`
/// entirely, which this class corrects; see [TicketMarkdownTemplate]'s
/// doc for the reasoning.
///
/// Pure Dart, no Flutter dependency (`Ticket` and its enums are
/// Flutter-free) — deliberately, so `bin/ticket_lint.dart` can import
/// this directly without pulling in Flutter.
class TicketMarkdownSerializer {
  /// Serializes [ticket] to its Markdown file content. Pure and
  /// deterministic: the same ticket always produces byte-identical
  /// output, so diffs reflect real changes only.
  String serialize(Ticket ticket) {
    final buffer = StringBuffer()..writeln(TicketMarkdownTemplate.delimiter);
    final values = <String, Object?>{
      TicketMarkdownTemplate.ticketId: ticket.ticketId,
      TicketMarkdownTemplate.type: ticket.type.name,
      TicketMarkdownTemplate.status: ticket.status.name,
      TicketMarkdownTemplate.priority: ticket.priority.name,
      TicketMarkdownTemplate.parentId: ticket.parentId,
      TicketMarkdownTemplate.estimate: ticket.estimate,
      TicketMarkdownTemplate.timeSpent: ticket.timeSpent,
      TicketMarkdownTemplate.createdAt: ticket.createdAt.toIso8601String(),
      TicketMarkdownTemplate.updatedAt: ticket.updatedAt.toIso8601String(),
    };
    for (final key in TicketMarkdownTemplate.fieldOrder) {
      buffer.writeln('$key: ${_yamlScalar(values[key])}');
    }
    buffer.writeln(TicketMarkdownTemplate.delimiter);
    buffer.writeln('# ${ticket.title}');
    buffer.writeln();
    if (ticket.description != null) buffer.write(ticket.description);
    return buffer.toString();
  }

  /// Renders [value] as a bare YAML scalar. Every field this schema
  /// writes is a constrained value (enum name, id, int, or ISO-8601
  /// timestamp) — none need quoting.
  String _yamlScalar(Object? value) => value == null ? 'null' : '$value';

  /// Parses [content] (a full ticket Markdown file) into a
  /// [TicketMarkdownParseResult].
  TicketMarkdownParseResult parse(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty ||
        lines.first.trim() != TicketMarkdownTemplate.delimiter) {
      return const Unparseable('Missing opening frontmatter delimiter.');
    }
    final closingIndex = lines.indexWhere(
      (line) => line.trim() == TicketMarkdownTemplate.delimiter,
      1,
    );
    if (closingIndex == -1) {
      return const Unparseable('Missing closing frontmatter delimiter.');
    }

    final yamlBlock = lines.sublist(1, closingIndex).join('\n');
    final bodyLines = lines.sublist(closingIndex + 1);

    final Object? parsedYaml;
    try {
      parsedYaml = loadYaml(yamlBlock);
    } on YamlException catch (e) {
      return Unparseable('Frontmatter is not valid YAML: ${e.message}');
    }
    if (parsedYaml is! YamlMap) {
      return const Unparseable('Frontmatter did not parse to a map.');
    }

    final validFields = <String, Object?>{};
    final invalidFieldNames = <String>{};
    for (final key in TicketMarkdownTemplate.fieldOrder) {
      final raw = parsedYaml[key];
      final converted = _convertField(key, raw);
      if (converted case (final value,)) {
        validFields[key] = value;
      } else {
        invalidFieldNames.add(key);
      }
    }

    final (title, body) = _splitTitleAndBody(bodyLines);

    if (invalidFieldNames.isEmpty) {
      return ParsedOk(fields: validFields, title: title, body: body);
    }
    return ParsedPartial(
      validFields: validFields,
      invalidFieldNames: invalidFieldNames,
      title: title,
      body: body,
    );
  }

  /// Converts a raw YAML [value] for frontmatter [key] into its typed
  /// Dart form. Returns `(value,)` (a 1-tuple, used as an Option-style
  /// wrapper so a legitimately-`null` field value is distinguishable
  /// from "conversion failed") on success, or `null` if [value] is
  /// missing or doesn't validate for [key].
  (Object?,)? _convertField(String key, Object? value) {
    switch (key) {
      case TicketMarkdownTemplate.ticketId:
        return value is String && value.isNotEmpty ? (value,) : null;
      case TicketMarkdownTemplate.type:
        for (final t in TicketType.values) {
          if (t.name == value) return (t,);
        }
        return null;
      case TicketMarkdownTemplate.status:
        for (final s in TicketStatus.values) {
          if (s.name == value) return (s,);
        }
        return null;
      case TicketMarkdownTemplate.priority:
        for (final p in TicketPriority.values) {
          if (p.name == value) return (p,);
        }
        return null;
      case TicketMarkdownTemplate.parentId:
        if (value == null) return (null,);
        return value is String && value.isNotEmpty ? (value,) : null;
      case TicketMarkdownTemplate.estimate:
      case TicketMarkdownTemplate.timeSpent:
        if (value == null) return (null,);
        return value is int ? (value,) : null;
      case TicketMarkdownTemplate.createdAt:
      case TicketMarkdownTemplate.updatedAt:
        if (value is! String) return null;
        final parsed = DateTime.tryParse(value);
        return parsed == null ? null : (parsed,);
      default:
        return null;
    }
  }

  /// Splits the body into `(title, description)`: [title] is the text of
  /// the first non-blank line if it starts with `# `, otherwise empty;
  /// [description] is everything after that heading (and the blank line
  /// following it, if present), trimmed of leading/trailing blank lines.
  (String, String) _splitTitleAndBody(List<String> bodyLines) {
    final firstContentIndex = bodyLines.indexWhere((l) => l.trim().isNotEmpty);
    if (firstContentIndex == -1) return ('', '');

    final firstLine = bodyLines[firstContentIndex].trim();
    if (!firstLine.startsWith('# ')) {
      return ('', bodyLines.join('\n').trim());
    }

    final title = firstLine.substring(2).trim();
    final rest = bodyLines.sublist(firstContentIndex + 1).join('\n').trim();
    return (title, rest);
  }
}
