import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/migration/aion_arch_change_migrator.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

void main() {
  final migrator = AionArchChangeMigrator();

  const proposalMd = '# Proposal: some-change\n\nWhy we did this.';
  const designMd = '# Design: Some Change\n\nHow it works.';
  const specDeltaMd = '# Spec delta: Some Change\n\n### ADDED\n\n- A thing.';

  const tasksWithSections = '''
# Tasks: Some Change

Ordered.

## First section

- [x] T1. Do the first thing
      with continuation detail.
- [x] T2. Do the second thing.

## Second section

- [x] T3. Do a third thing.
''';

  const tasksWithoutSections = '''
# Tasks: Some Change

- [x] T1. Do the only thing
      with continuation detail.
- [x] T2. Do another thing.
''';

  test('a tasks.md with clear section breaks produces multiple Stories', () {
    final migration = migrator.migrate(
      'some-change',
      proposalMd: proposalMd,
      designMd: designMd,
      specDeltaMd: specDeltaMd,
      tasksMd: tasksWithSections,
    );

    final stories = migration.storiesAndTasks
        .where((t) => t.type == TicketType.story)
        .toList();
    expect(stories, hasLength(2));
    expect(stories[0].title, 'First section');
    expect(stories[1].title, 'Second section');

    final tasks = migration.storiesAndTasks
        .where((t) => t.type == TicketType.task)
        .toList();
    expect(tasks, hasLength(3));
    expect(tasks.where((t) => t.parentId == stories[0].id), hasLength(2));
    expect(tasks.where((t) => t.parentId == stories[1].id), hasLength(1));
  });

  test('a tasks.md with no section breaks produces a single Story', () {
    final migration = migrator.migrate(
      'some-change',
      proposalMd: proposalMd,
      designMd: designMd,
      specDeltaMd: specDeltaMd,
      tasksMd: tasksWithoutSections,
    );

    final stories = migration.storiesAndTasks
        .where((t) => t.type == TicketType.story)
        .toList();
    expect(stories, hasLength(1));

    final tasks = migration.storiesAndTasks
        .where((t) => t.type == TicketType.task)
        .toList();
    expect(tasks, hasLength(2));
    expect(tasks.every((t) => t.parentId == stories.single.id), isTrue);
  });

  test('every produced Task/Story/Epic is status done-equivalent', () {
    final migration = migrator.migrate(
      'some-change',
      proposalMd: proposalMd,
      designMd: designMd,
      specDeltaMd: specDeltaMd,
      tasksMd: tasksWithSections,
    );

    expect(migration.epic.status, 'done');
    for (final t in migration.storiesAndTasks) {
      expect(t.status, 'done');
    }
  });

  test('the spec ticket carries the [NEEDS RECONCILIATION] marker', () {
    final migration = migrator.migrate(
      'some-change',
      proposalMd: proposalMd,
      designMd: designMd,
      specDeltaMd: specDeltaMd,
      tasksMd: tasksWithSections,
    );

    expect(migration.spec.type, TicketType.spec);
    expect(migration.spec.description, contains('[NEEDS RECONCILIATION]'));
    expect(migration.spec.description, contains('A thing.'));
  });

  test(
    'produces relatesTo link rows between the page and both the Epic and spec',
    () {
      final migration = migrator.migrate(
        'some-change',
        proposalMd: proposalMd,
        designMd: designMd,
        specDeltaMd: specDeltaMd,
        tasksMd: tasksWithSections,
      );

      expect(migration.page.type, TicketType.page);
      final targets = migration.links
          .where((l) => l.sourceTicketId == migration.page.id)
          .map((l) => l.targetTicketId)
          .toSet();
      expect(targets, {migration.epic.id, migration.spec.id});
      expect(
        migration.links.every((l) => l.type == TicketLinkType.relatesTo),
        isTrue,
      );
    },
  );

  test(
    'the Epic is titled from a humanized change name and its description is the proposal verbatim',
    () {
      final migration = migrator.migrate(
        'automatic-time-tracking-for-tickets',
        proposalMd: proposalMd,
        designMd: designMd,
        specDeltaMd: specDeltaMd,
        tasksMd: tasksWithSections,
      );

      expect(migration.epic.type, TicketType.epic);
      expect(migration.epic.title, 'Automatic Time Tracking For Tickets');
      expect(migration.epic.description, proposalMd);
    },
  );
}
