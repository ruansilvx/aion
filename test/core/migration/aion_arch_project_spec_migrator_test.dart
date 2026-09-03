import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/migration/aion_arch_project_spec_migrator.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

void main() {
  final migrator = AionArchProjectSpecMigrator();

  const projectMd = '''
# Project Context — Aion

## What Is Aion
A spec-based AI agentic code assistant.

---

## Foundational Decisions
Some decisions.
''';

  test('produces a type: spec, parentless ticket', () {
    final ticket = migrator.migrate(projectMd);

    expect(ticket.type, TicketType.spec);
    expect(ticket.parentId, isNull);
  });

  test('carries the [NEEDS RECONCILIATION] marker', () {
    final ticket = migrator.migrate(projectMd);
    expect(ticket.description, contains('[NEEDS RECONCILIATION]'));
  });

  test('preserves the body content verbatim', () {
    final ticket = migrator.migrate(projectMd);
    expect(
      ticket.description,
      contains('A spec-based AI agentic code assistant.'),
    );
    expect(ticket.description, contains('## Foundational Decisions'));
    expect(ticket.description, contains('Some decisions.'));
  });

  test('takes its title from the leading heading', () {
    final ticket = migrator.migrate(projectMd);
    expect(ticket.title, 'Project Context — Aion');
  });

  test(
    'generates a fresh id and leaves ticketId empty for the CLI to assign',
    () {
      final ticket = migrator.migrate(projectMd);
      expect(ticket.id, isNotEmpty);
      expect(ticket.ticketId, isEmpty);
    },
  );
}
