// test/features/tickets/data/repositories/drift_workflow_skill_attachment_repository_test.dart — DriftWorkflowSkillAttachmentRepository delegation tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:drift/drift.dart' show Value;

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/daos/workflow_skill_attachment_dao.dart';
import 'package:aion/features/tickets/data/repositories/drift_workflow_skill_attachment_repository.dart';
import 'package:aion/features/tickets/domain/entities/skill_attachment.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/skill_attachment_kind.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockWorkflowSkillAttachmentDao extends Mock
    implements WorkflowSkillAttachmentDao {}

/// [DriftWorkflowSkillAttachmentRepository] is a thin delegate over
/// [WorkflowSkillAttachmentDao] — mirrors
/// `drift_workflow_status_repository_test.dart`'s mocked-DAO convention.
void main() {
  setUpAll(() {
    registerFallbackValue(
      const WorkflowSkillAttachmentsTableCompanion(id: Value('fallback')),
    );
  });

  late MockAppDatabase database;
  late MockWorkflowSkillAttachmentDao dao;
  late DriftWorkflowSkillAttachmentRepository repository;

  final row = WorkflowSkillAttachmentData(
    id: 'row-1',
    workflowStatusId: 'status-1',
    sddStage: null,
    kind: 'delegatedSkill',
    templateId: null,
    skillName: 'code-review',
    confidence: 'gated',
  );

  setUp(() {
    database = MockAppDatabase();
    dao = MockWorkflowSkillAttachmentDao();
    when(() => database.workflowSkillAttachmentDao).thenReturn(dao);
    repository = DriftWorkflowSkillAttachmentRepository(database);
  });

  group('getAll', () {
    test('maps the DAO\'s rows to SkillAttachment entities', () async {
      when(() => dao.getAll()).thenAnswer((_) async => [row]);

      final result = await repository.getAll();

      expect(result, [
        const SkillAttachment(
          id: 'row-1',
          workflowStatusId: 'status-1',
          kind: SkillAttachmentKind.delegatedSkill,
          skillName: 'code-review',
          confidence: AutomationConfidence.gated,
        ),
      ]);
    });

    test('maps an unrecognized sddStage/kind/confidence string defensively',
        () async {
      when(() => dao.getAll()).thenAnswer(
        (_) async => [
          WorkflowSkillAttachmentData(
            id: 'row-2',
            workflowStatusId: null,
            sddStage: 'not-a-real-stage',
            kind: 'not-a-real-kind',
            templateId: null,
            skillName: null,
            confidence: 'not-a-real-confidence',
          ),
        ],
      );

      final result = await repository.getAll();

      expect(result.single.sddStage, isNull);
      expect(result.single.kind, SkillAttachmentKind.aionNativeTemplate);
      expect(result.single.confidence, AutomationConfidence.gated);
    });
  });

  group('create / update / delete', () {
    test('create delegates to WorkflowSkillAttachmentDao.insertOne', () async {
      when(() => dao.insertOne(any())).thenAnswer((_) async {});

      await repository.create(
        const SkillAttachment(
          id: 'new-id',
          sddStage: SddStage.exploring,
          kind: SkillAttachmentKind.aionNativeTemplate,
          templateId: 'template-1',
          confidence: AutomationConfidence.auto,
        ),
      );

      verify(() => dao.insertOne(any())).called(1);
    });

    test('update delegates to WorkflowSkillAttachmentDao.updateOne', () async {
      when(() => dao.updateOne(any())).thenAnswer((_) async {});

      await repository.update(
        const SkillAttachment(
          id: 'row-1',
          workflowStatusId: 'status-1',
          kind: SkillAttachmentKind.delegatedSkill,
          skillName: 'code-review',
          confidence: AutomationConfidence.manual,
        ),
      );

      verify(() => dao.updateOne(any())).called(1);
    });

    test('delete delegates to WorkflowSkillAttachmentDao.deleteOne', () async {
      when(() => dao.deleteOne('row-1')).thenAnswer((_) async {});

      await repository.delete('row-1');

      verify(() => dao.deleteOne('row-1')).called(1);
    });
  });

  group('onChanged', () {
    test('fires after a successful create/update/delete', () async {
      when(() => dao.insertOne(any())).thenAnswer((_) async {});
      when(() => dao.deleteOne(any())).thenAnswer((_) async {});

      final events = <void>[];
      final sub = repository.onChanged.listen(events.add);

      await repository.create(
        const SkillAttachment(
          id: 'x',
          workflowStatusId: 'status-1',
          kind: SkillAttachmentKind.delegatedSkill,
          skillName: 'x',
          confidence: AutomationConfidence.auto,
        ),
      );
      await repository.delete('x');

      expect(events, hasLength(2));
      await sub.cancel();
    });
  });
}
