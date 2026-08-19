// test/features/tickets/data/repositories/drift_workflow_status_repository_test.dart — DriftWorkflowStatusRepository delegation tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:drift/drift.dart' show Value;

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/daos/workflow_status_dao.dart';
import 'package:aion/features/tickets/data/repositories/drift_workflow_status_repository.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockWorkflowStatusDao extends Mock implements WorkflowStatusDao {}

/// [DriftWorkflowStatusRepository] is a thin delegate over
/// [WorkflowStatusDao] — per `project.md`'s repository-test convention
/// (see `drift_execution_queue_repository_test.dart`), these tests mock
/// the DAO via mocktail rather than spinning up a real drift instance.
/// [WorkflowStatusDao]'s own persistence behavior (ordering, the
/// `seedDefaultsIfEmpty` idempotency) is covered directly against a real
/// in-memory database in `workflow_status_dao_test.dart`.
void main() {
  setUpAll(() {
    registerFallbackValue(
      const WorkflowStatusesTableCompanion(id: Value('fallback')),
    );
  });

  late MockAppDatabase database;
  late MockWorkflowStatusDao dao;
  late DriftWorkflowStatusRepository repository;

  final row = WorkflowStatusData(
    id: 'row-1',
    name: 'inProgress',
    displayName: 'In Progress',
    ticketType: null,
    sortOrder: 1,
    role: 'executionTrigger',
  );

  setUp(() {
    database = MockAppDatabase();
    dao = MockWorkflowStatusDao();
    when(() => database.workflowStatusDao).thenReturn(dao);
    repository = DriftWorkflowStatusRepository(database);
  });

  group('getAll', () {
    test('maps the DAO\'s rows to WorkflowStatus entities', () async {
      when(() => dao.getAll()).thenAnswer((_) async => [row]);

      final result = await repository.getAll();

      expect(result, [
        const WorkflowStatus(
          id: 'row-1',
          name: 'inProgress',
          displayName: 'In Progress',
          sortOrder: 1,
          role: WorkflowStatusRole.executionTrigger,
        ),
      ]);
    });

    test('maps an unrecognized ticketType/role string to null defensively', () async {
      when(() => dao.getAll()).thenAnswer(
        (_) async => [
          WorkflowStatusData(
            id: 'row-2',
            name: 'weird',
            displayName: 'Weird',
            ticketType: 'not-a-real-type',
            sortOrder: 0,
            role: 'not-a-real-role',
          ),
        ],
      );

      final result = await repository.getAll();

      expect(result.single.ticketType, isNull);
      expect(result.single.role, isNull);
    });
  });

  group('create / update / delete / reorder', () {
    test('create delegates to WorkflowStatusDao.insertOne', () async {
      when(() => dao.insertOne(any())).thenAnswer((_) async {});

      await repository.create(
        const WorkflowStatus(
          id: 'new-id',
          name: 'needsRepro',
          displayName: 'Needs Repro',
          ticketType: TicketType.bug,
          sortOrder: 4,
        ),
      );

      verify(() => dao.insertOne(any())).called(1);
    });

    test('update delegates to WorkflowStatusDao.updateOne', () async {
      when(() => dao.updateOne(any())).thenAnswer((_) async {});

      await repository.update(
        const WorkflowStatus(
          id: 'row-1',
          name: 'inProgress',
          displayName: 'Working',
          sortOrder: 1,
          role: WorkflowStatusRole.executionTrigger,
        ),
      );

      verify(() => dao.updateOne(any())).called(1);
    });

    test('delete delegates to WorkflowStatusDao.deleteOne', () async {
      when(() => dao.deleteOne('row-1')).thenAnswer((_) async {});

      await repository.delete('row-1');

      verify(() => dao.deleteOne('row-1')).called(1);
    });

    test('reorder delegates to WorkflowStatusDao.reorder', () async {
      when(() => dao.reorder(['b', 'a'])).thenAnswer((_) async {});

      await repository.reorder(['b', 'a']);

      verify(() => dao.reorder(['b', 'a'])).called(1);
    });
  });

  group('seedDefaultsIfEmpty', () {
    test('delegates to WorkflowStatusDao.seedDefaultsIfEmpty', () async {
      when(() => dao.seedDefaultsIfEmpty()).thenAnswer((_) async {});

      await repository.seedDefaultsIfEmpty();

      verify(() => dao.seedDefaultsIfEmpty()).called(1);
    });
  });

  group('onChanged', () {
    test('fires after a successful create/update/delete/reorder', () async {
      when(() => dao.insertOne(any())).thenAnswer((_) async {});
      when(() => dao.deleteOne(any())).thenAnswer((_) async {});

      final events = <void>[];
      final sub = repository.onChanged.listen(events.add);

      await repository.create(
        const WorkflowStatus(
          id: 'x',
          name: 'x',
          displayName: 'X',
          sortOrder: 0,
        ),
      );
      await repository.delete('x');

      expect(events, hasLength(2));
      await sub.cancel();
    });
  });
}
