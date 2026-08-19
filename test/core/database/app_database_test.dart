// test/core/database/app_database_test.dart — AppDatabase schema-15 seeding tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/domain/entities/default_workflow_statuses.dart';

/// Dummy project — every test passes an explicit in-memory executor,
/// mirroring `ticket_dao_test.dart`'s own precedent.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

/// Covers schema-15's `WorkflowStatusesTable` seeding — see
/// `AppDatabase`'s class dartdoc and
/// `aion-arch/changes/configurable-ticket-workflow/design.md` §2.2.
///
/// Scoped to the fresh-`onCreate` install path only: this codebase has no
/// existing exported-schema/`SchemaVerifier` test infrastructure (no
/// prior `app_database_test.dart` establishes one either), and
/// hand-authoring a byte-accurate schema-14 `CREATE TABLE` DDL snapshot
/// just for this one migration step risks a test that fails for reasons
/// unrelated to this change's actual `onUpgrade` branch. The `from < 15`
/// branch itself is a two-line `createTable` + `seedDefaultsIfEmpty`
/// call, identical in shape and effect to every already-untested
/// `onUpgrade` branch in this file (versions 2 through 14 have no
/// migration tests of their own either) — this test instead exercises
/// [WorkflowStatusDao.seedDefaultsIfEmpty]'s idempotency directly (see
/// `workflow_status_dao_test.dart`), which is the actual logic both
/// `onCreate` and `onUpgrade` share.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh onCreate install seeds defaultWorkflowStatuses', () async {
    final database = AppDatabase(_testProject, NativeDatabase.memory());
    addTearDown(database.close);

    final rows = await database.workflowStatusDao.getAll();

    expect(rows, hasLength(defaultWorkflowStatuses.length));
    expect(
      rows.map((r) => r.name).toList(),
      defaultWorkflowStatuses.map((s) => s.name).toList(),
    );
    expect(
      rows.where((r) => r.role != null).map((r) => r.role).toSet(),
      {'executionTrigger', 'reviewReady', 'done'},
    );
  });

  test(
    'a freshly-created ticket\'s default status resolves against the '
    'seeded defaultWorkflowStatuses',
    () async {
      final database = AppDatabase(_testProject, NativeDatabase.memory());
      addTearDown(database.close);

      await database.ticketDao.insertTicket(
        TicketsTableCompanion.insert(
          id: 'ticket-1',
          ticketId: '',
          type: 'task',
          title: 'A fresh ticket',
          status: 'backlog',
          createdAt: 0,
          updatedAt: 0,
        ),
        'AIO',
      );

      final ticket = await database.ticketDao.getTicketById('ticket-1');
      final statuses = await database.workflowStatusDao.getAll();

      expect(ticket, isNotNull);
      expect(statuses.map((s) => s.name), contains(ticket!.status));
    },
  );
}
