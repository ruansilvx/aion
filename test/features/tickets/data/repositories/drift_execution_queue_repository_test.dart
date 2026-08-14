// test/features/tickets/data/repositories/drift_execution_queue_repository_test.dart — DriftExecutionQueueRepository delegation tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/daos/execution_queue_dao.dart';
import 'package:aion/features/tickets/data/repositories/drift_execution_queue_repository.dart';
import 'package:aion/features/tickets/domain/entities/execution_queue_entry.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockExecutionQueueDao extends Mock implements ExecutionQueueDao {}

/// [DriftExecutionQueueRepository] is a thin delegate over
/// [ExecutionQueueDao] — per `project.md`'s repository-test convention,
/// these tests mock the DAO via mocktail rather than spinning up a real
/// drift instance.
void main() {
  late MockAppDatabase database;
  late MockExecutionQueueDao dao;
  late DriftExecutionQueueRepository repository;

  final row = ExecutionQueueEntryData(
    id: 'row-1',
    taskId: 'task-1',
    inFlight: true,
    queuePosition: null,
  );

  setUp(() {
    database = MockAppDatabase();
    dao = MockExecutionQueueDao();
    when(() => database.executionQueueDao).thenReturn(dao);
    repository = DriftExecutionQueueRepository(database);
  });

  group('getSnapshot', () {
    test('maps the DAO\'s rows to ExecutionQueueEntry entities', () async {
      when(() => dao.getSnapshot()).thenAnswer((_) async => [row]);

      final result = await repository.getSnapshot();

      expect(result, [
        const ExecutionQueueEntry(
          taskId: 'task-1',
          inFlight: true,
          queuePosition: null,
        ),
      ]);
    });
  });

  group('replaceSnapshot', () {
    test('delegates to ExecutionQueueDao.replaceSnapshot', () async {
      when(() => dao.replaceSnapshot(any())).thenAnswer((_) async {});

      await repository.replaceSnapshot(const [
        ExecutionQueueEntry(taskId: 'task-1', inFlight: true),
        ExecutionQueueEntry(taskId: 'task-2', inFlight: false, queuePosition: 0),
      ]);

      verify(
        () => dao.replaceSnapshot([
          (taskId: 'task-1', inFlight: true, queuePosition: null),
          (taskId: 'task-2', inFlight: false, queuePosition: 0),
        ]),
      ).called(1);
    });
  });
}
