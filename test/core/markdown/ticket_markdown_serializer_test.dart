import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/markdown/ticket_markdown_parse_result.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/core/markdown/ticket_markdown_template.dart';
import 'package:aion/features/tickets/tickets.dart';

void main() {
  final serializer = TicketMarkdownSerializer();

  final ticket = Ticket(
    id: 'internal-1',
    ticketId: 'AIO-42',
    type: TicketType.resource,
    title: 'A resource ticket',
    description: 'Some description text.',
    status: TicketStatus.backlog,
    priority: TicketPriority.medium,
    parentId: 'internal-parent',
    estimate: 30,
    timeSpent: null,
    createdAt: DateTime.utc(2026, 7, 18, 10),
    updatedAt: DateTime.utc(2026, 7, 18, 11),
  );

  group('serialize', () {
    test('is deterministic — same ticket produces byte-identical output', () {
      expect(serializer.serialize(ticket), serializer.serialize(ticket));
    });

    test('includes a leading # title heading in the body', () {
      final content = serializer.serialize(ticket);
      expect(content, contains('# A resource ticket'));
    });

    test('round-trips through parse as ParsedOk', () {
      final content = serializer.serialize(ticket);
      final result = serializer.parse(content);
      expect(result, isA<ParsedOk>());
      final ok = result as ParsedOk;
      expect(ok.title, ticket.title);
      expect(ok.body, ticket.description);
      expect(ok.fields[TicketMarkdownTemplate.ticketId], ticket.ticketId);
      expect(ok.fields[TicketMarkdownTemplate.type], ticket.type);
      expect(ok.fields[TicketMarkdownTemplate.status], ticket.status);
      expect(ok.fields[TicketMarkdownTemplate.priority], ticket.priority);
      expect(ok.fields[TicketMarkdownTemplate.parentId], ticket.parentId);
      expect(ok.fields[TicketMarkdownTemplate.estimate], ticket.estimate);
      expect(ok.fields[TicketMarkdownTemplate.timeSpent], isNull);
    });

    test('renders a null field as bare `null`', () {
      final content = serializer.serialize(ticket);
      expect(content, contains('timeSpent: null'));
    });
  });

  group('parse — ParsedPartial', () {
    test('degrades one invalid field, keeps the rest valid', () {
      final content = serializer.serialize(ticket).replaceFirst(
        'status: backlog',
        'status: not-a-real-status',
      );
      final result = serializer.parse(content);
      expect(result, isA<ParsedPartial>());
      final partial = result as ParsedPartial;
      expect(partial.invalidFieldNames, {TicketMarkdownTemplate.status});
      expect(
        partial.validFields[TicketMarkdownTemplate.type],
        ticket.type,
      );
      expect(partial.title, ticket.title);
      expect(partial.body, ticket.description);
    });
  });

  group('parse — Unparseable', () {
    test('missing opening delimiter', () {
      final result = serializer.parse('no frontmatter here at all');
      expect(result, isA<Unparseable>());
    });

    test('missing closing delimiter', () {
      final result = serializer.parse('---\nticketId: AIO-1\n');
      expect(result, isA<Unparseable>());
    });

    test('invalid YAML in the frontmatter block', () {
      final result = serializer.parse('---\n[not: valid: yaml\n---\nbody');
      expect(result, isA<Unparseable>());
    });

    test('frontmatter that parses but is not a map', () {
      final result = serializer.parse('---\n- just\n- a\n- list\n---\nbody');
      expect(result, isA<Unparseable>());
    });
  });
}
