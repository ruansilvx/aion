import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/migration/aion_arch_idea_migrator.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

void main() {
  final migrator = AionArchIdeaMigrator();

  String ideaFile({
    required String title,
    required String status,
    List<String> relatedIdeas = const [],
    String body = 'Some body content.',
  }) {
    final relatedIdeasYaml = relatedIdeas.isEmpty
        ? '[]'
        : '[${relatedIdeas.join(', ')}]';
    return '''
---
title: $title
status: $status
related_specs: []
related_ideas: $relatedIdeasYaml
complexity: medium
created: 2026-01-01
last_touched: 2026-01-05
summary: A summary.
next_action: /explore
---

$body
''';
  }

  test('a plain raw idea migrates to an idea ticket', () {
    final content = ideaFile(title: 'A plain idea', status: 'raw');
    final (ticket, links) = migrator.migrate(
      content,
      migratedIdeaSlugs: {'a-plain-idea'},
    );

    expect(ticket.type, TicketType.idea);
    expect(ticket.title, 'A plain idea');
    expect(ticket.status, 'backlog');
    expect(ticket.description, contains('Some body content.'));
    expect(links, isEmpty);
  });

  test('an idea unambiguously naming one specific migrated target becomes '
      'a knownGap with its link row', () {
    final content = ideaFile(
      title: 'Known gap: missing rate limit handling',
      status: 'raw',
      relatedIdeas: ['target-idea'],
    );
    final (ticket, links) = migrator.migrate(
      content,
      migratedIdeaSlugs: {'this-idea', 'target-idea'},
    );

    expect(ticket.type, TicketType.knownGap);
    expect(links, hasLength(1));
    expect(links.single.sourceTicketId, ticket.id);
    expect(links.single.targetTicketId, 'target-idea');
    expect(links.single.type, TicketLinkType.relatesTo);
  });

  test('an "Open question:" idea with one migrated target becomes an '
      'openQuestion with its link row', () {
    final content = ideaFile(
      title: 'Open question: should X be configurable',
      status: 'raw',
      relatedIdeas: ['target-idea'],
    );
    final (ticket, links) = migrator.migrate(
      content,
      migratedIdeaSlugs: {'target-idea'},
    );

    expect(ticket.type, TicketType.openQuestion);
    expect(links, hasLength(1));
  });

  test(
    'a gap/question-marker title with no migrated target stays a plain idea',
    () {
      final content = ideaFile(
        title: 'Known gap: something',
        status: 'raw',
        relatedIdeas: ['not-migrated'],
      );
      final (ticket, links) = migrator.migrate(
        content,
        migratedIdeaSlugs: {'this-idea'},
      );

      expect(ticket.type, TicketType.idea);
      expect(links, isEmpty);
    },
  );

  test('related_ideas entries both inside and outside migratedIdeaSlugs: only '
      'the migrated ones produce link rows, the rest are noted in the '
      'description', () {
    final content = ideaFile(
      title: 'An idea with mixed related ideas',
      status: 'raw',
      relatedIdeas: ['migrated-one', 'not-migrated-one'],
    );
    final (ticket, links) = migrator.migrate(
      content,
      migratedIdeaSlugs: {'this-idea', 'migrated-one'},
    );

    expect(links, hasLength(1));
    expect(links.single.targetTicketId, 'migrated-one');
    expect(ticket.description, contains('not-migrated-one'));
  });

  test('every status value maps to the correct WorkflowStatus name', () {
    final expectations = {
      'raw': 'backlog',
      'resolved': 'backlog',
      'explored': 'backlog',
      'specced': 'done',
      'archived': 'done',
    };
    for (final entry in expectations.entries) {
      final content = ideaFile(title: 'An idea', status: entry.key);
      final (ticket, _) = migrator.migrate(content, migratedIdeaSlugs: {});
      expect(
        ticket.status,
        entry.value,
        reason: 'status "${entry.key}" should map to "${entry.value}"',
      );
    }
  });

  test(
    'generates a fresh id and leaves ticketId empty for the CLI to assign',
    () {
      final content = ideaFile(title: 'An idea', status: 'raw');
      final (ticket, _) = migrator.migrate(content, migratedIdeaSlugs: {});
      expect(ticket.id, isNotEmpty);
      expect(ticket.ticketId, isEmpty);
    },
  );

  test('a summary/next_action field with an unquoted mid-sentence colon still '
      'parses (real aion-arch/ideas/*.md files are not strict YAML)', () {
    const content = '''
---
title: An idea with a tricky summary
status: archived
related_specs: []
related_ideas: []
complexity: medium
created: 2026-01-01
last_touched: 2026-01-05
summary: Replaces the old tool entirely rather than keeping it alongside: found every invocation happens inside the same window.
next_action: none — shipped, see specs/tickets.md's "Section" for details
---

Body content.
''';
    final (ticket, _) = migrator.migrate(content, migratedIdeaSlugs: {});
    expect(ticket.title, 'An idea with a tricky summary');
    expect(ticket.status, 'done');
  });
}
