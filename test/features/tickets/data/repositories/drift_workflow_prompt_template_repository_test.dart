// test/features/tickets/data/repositories/drift_workflow_prompt_template_repository_test.dart — DriftWorkflowPromptTemplateRepository delegation tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:drift/drift.dart' show Value;

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/daos/workflow_prompt_template_dao.dart';
import 'package:aion/features/tickets/data/repositories/drift_workflow_prompt_template_repository.dart';
import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockWorkflowPromptTemplateDao extends Mock
    implements WorkflowPromptTemplateDao {}

/// [DriftWorkflowPromptTemplateRepository] is a thin delegate over
/// [WorkflowPromptTemplateDao] — mirrors
/// `drift_workflow_status_repository_test.dart`'s mocked-DAO convention.
/// No `onChanged` coverage — [WorkflowPromptTemplateRepository] declares
/// no such stream (see its own dartdoc).
void main() {
  setUpAll(() {
    registerFallbackValue(
      const WorkflowPromptTemplatesTableCompanion(id: Value('fallback')),
    );
  });

  late MockAppDatabase database;
  late MockWorkflowPromptTemplateDao dao;
  late DriftWorkflowPromptTemplateRepository repository;

  const row = WorkflowPromptTemplateData(
    id: 'row-1',
    name: 'Repro Steps Request',
    body: 'Please provide steps to reproduce {{ticket.title}}.',
  );

  setUp(() {
    database = MockAppDatabase();
    dao = MockWorkflowPromptTemplateDao();
    when(() => database.workflowPromptTemplateDao).thenReturn(dao);
    repository = DriftWorkflowPromptTemplateRepository(database);
  });

  group('getAll', () {
    test('maps the DAO\'s rows to WorkflowPromptTemplate entities', () async {
      when(() => dao.getAll()).thenAnswer((_) async => [row]);

      final result = await repository.getAll();

      expect(result, const [
        WorkflowPromptTemplate(
          id: 'row-1',
          name: 'Repro Steps Request',
          body: 'Please provide steps to reproduce {{ticket.title}}.',
        ),
      ]);
    });
  });

  group('create / update / delete', () {
    test('create delegates to WorkflowPromptTemplateDao.insertOne', () async {
      when(() => dao.insertOne(any())).thenAnswer((_) async {});

      await repository.create(
        const WorkflowPromptTemplate(id: 'new-id', name: 'New', body: 'Body'),
      );

      verify(() => dao.insertOne(any())).called(1);
    });

    test('update delegates to WorkflowPromptTemplateDao.updateOne', () async {
      when(() => dao.updateOne(any())).thenAnswer((_) async {});

      await repository.update(
        const WorkflowPromptTemplate(
          id: 'row-1',
          name: 'Renamed',
          body: 'New body',
        ),
      );

      verify(() => dao.updateOne(any())).called(1);
    });

    test('delete delegates to WorkflowPromptTemplateDao.deleteOne', () async {
      when(() => dao.deleteOne('row-1')).thenAnswer((_) async {});

      await repository.delete('row-1');

      verify(() => dao.deleteOne('row-1')).called(1);
    });
  });
}
