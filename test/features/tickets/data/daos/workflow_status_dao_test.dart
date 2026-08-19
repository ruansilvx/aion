// test/features/tickets/data/daos/workflow_status_dao_test.dart — WorkflowStatusDao CRUD and seeding tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drift/drift.dart' show Value;

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/daos/workflow_status_dao.dart';
import 'package:aion/features/tickets/domain/entities/default_workflow_statuses.dart';

/// Dummy project — unused since every test passes an explicit in-memory
/// executor, mirroring `ticket_dao_test.dart`'s own precedent.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

/// Direct [WorkflowStatusDao] tests against a real in-memory drift
/// instance — genuinely persistence behavior (ordering,
/// insert/update/delete, and [WorkflowStatusDao.reorder]'s transactional
/// write), so this isn't mocked like most repository tests, per
/// `ticket_dao_test.dart`'s own precedent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late WorkflowStatusDao dao;

  setUp(() async {
    database = AppDatabase(_testProject, NativeDatabase.memory());
    dao = database.workflowStatusDao;
    // AppDatabase's own onCreate already seeds defaultWorkflowStatuses
    // (see app_database_test.dart) — cleared here so each test below
    // starts from a genuinely empty table, matching what it actually
    // asserts.
    for (final row in await dao.getAll()) {
      await dao.deleteOne(row.id);
    }
  });

  tearDown(() async {
    await database.close();
  });

  group('seedDefaultsIfEmpty', () {
    test('seeds defaultWorkflowStatuses into an empty table', () async {
      await dao.seedDefaultsIfEmpty();

      final rows = await dao.getAll();
      expect(rows, hasLength(defaultWorkflowStatuses.length));
      expect(
        rows.map((r) => r.name).toList(),
        defaultWorkflowStatuses.map((s) => s.name).toList(),
      );
    });

    test('is idempotent — calling twice never duplicates rows', () async {
      await dao.seedDefaultsIfEmpty();
      await dao.seedDefaultsIfEmpty();

      final rows = await dao.getAll();
      expect(rows, hasLength(defaultWorkflowStatuses.length));
    });

    test('is a no-op on an already-populated table', () async {
      await dao.insertOne(
        WorkflowStatusesTableCompanion.insert(
          id: 'custom-1',
          name: 'triage',
          displayName: 'Triage',
          ticketType: const Value(null),
          sortOrder: 0,
          role: const Value(null),
        ),
      );

      await dao.seedDefaultsIfEmpty();

      final rows = await dao.getAll();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'triage');
    });
  });

  group('getAll', () {
    test('returns rows ordered by sortOrder ascending', () async {
      await dao.insertOne(
        WorkflowStatusesTableCompanion.insert(
          id: 'a',
          name: 'a',
          displayName: 'A',
          ticketType: const Value(null),
          sortOrder: 2,
          role: const Value(null),
        ),
      );
      await dao.insertOne(
        WorkflowStatusesTableCompanion.insert(
          id: 'b',
          name: 'b',
          displayName: 'B',
          ticketType: const Value(null),
          sortOrder: 0,
          role: const Value(null),
        ),
      );
      await dao.insertOne(
        WorkflowStatusesTableCompanion.insert(
          id: 'c',
          name: 'c',
          displayName: 'C',
          ticketType: const Value(null),
          sortOrder: 1,
          role: const Value(null),
        ),
      );

      final rows = await dao.getAll();
      expect(rows.map((r) => r.id).toList(), ['b', 'c', 'a']);
    });
  });

  group('insertOne / updateOne / deleteOne', () {
    test('CRUD round-trips a row', () async {
      await dao.insertOne(
        WorkflowStatusesTableCompanion.insert(
          id: 'needs-repro',
          name: 'needsRepro',
          displayName: 'Needs Repro',
          ticketType: const Value('bug'),
          sortOrder: 0,
          role: const Value(null),
        ),
      );
      var rows = await dao.getAll();
      expect(rows.single.displayName, 'Needs Repro');

      await dao.updateOne(
        WorkflowStatusesTableCompanion(
          id: const Value('needs-repro'),
          name: const Value('needsRepro'),
          displayName: const Value('Repro Needed'),
          ticketType: const Value('bug'),
          sortOrder: const Value(0),
          role: const Value(null),
        ),
      );
      rows = await dao.getAll();
      expect(rows.single.displayName, 'Repro Needed');

      await dao.deleteOne('needs-repro');
      rows = await dao.getAll();
      expect(rows, isEmpty);
    });
  });

  group('reorder', () {
    test('writes a fresh sortOrder for every id, matching list index', () async {
      await dao.seedDefaultsIfEmpty();
      final seeded = await dao.getAll();
      final reversedIds = seeded.map((r) => r.id).toList().reversed.toList();

      await dao.reorder(reversedIds);

      final rows = await dao.getAll();
      expect(rows.map((r) => r.id).toList(), reversedIds);
    });
  });
}
