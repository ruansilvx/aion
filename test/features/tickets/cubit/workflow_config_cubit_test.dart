// test/features/tickets/cubit/workflow_config_cubit_test.dart — WorkflowConfigCubit tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockWorkflowStatusRepository extends Mock
    implements WorkflowStatusRepository {}

class MockSddStageConfigRepository extends Mock
    implements SddStageConfigRepository {}

class MockTicketRepository extends Mock implements TicketRepository {}

class MockWorkflowSkillAttachmentRepository extends Mock
    implements WorkflowSkillAttachmentRepository {}

class MockWorkflowPromptTemplateRepository extends Mock
    implements WorkflowPromptTemplateRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(SddStage.exploring);
    registerFallbackValue(
      const WorkflowStatus(id: 'fallback', name: 'fallback', displayName: 'Fallback', sortOrder: 0),
    );
    registerFallbackValue(
      const SkillAttachment(
        id: 'fallback',
        workflowStatusId: 'fallback-status',
        kind: SkillAttachmentKind.delegatedSkill,
        skillName: 'fallback',
        confidence: AutomationConfidence.gated,
      ),
    );
    registerFallbackValue(
      const WorkflowPromptTemplate(id: 'fallback', name: 'fallback', body: 'fallback'),
    );
  });

  _mainBody();
}

Ticket _ticket({required String id, required String status}) => Ticket(
  id: id,
  ticketId: 'AIO-$id',
  type: TicketType.task,
  title: 'Ticket $id',
  status: status,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void _mainBody() {
  late MockWorkflowStatusRepository statusRepository;
  late MockSddStageConfigRepository sddStageConfigRepository;
  late MockTicketRepository ticketRepository;
  late MockWorkflowSkillAttachmentRepository attachmentRepository;
  late MockWorkflowPromptTemplateRepository templateRepository;

  final backlog = WorkflowStatus(
    id: 'id-backlog',
    name: 'backlog',
    displayName: 'Backlog',
    sortOrder: 0,
  );
  final inProgress = WorkflowStatus(
    id: 'id-in-progress',
    name: 'inProgress',
    displayName: 'In Progress',
    sortOrder: 1,
    role: WorkflowStatusRole.executionTrigger,
  );
  final done = WorkflowStatus(
    id: 'id-done',
    name: 'done',
    displayName: 'Done',
    sortOrder: 2,
    role: WorkflowStatusRole.done,
  );
  final baseStatuses = [backlog, inProgress, done];

  WorkflowConfigLoaded loadedState({
    List<WorkflowStatus>? statuses,
    bool designStagesEnabled = true,
    Map<SddStage, String> stageDisplayNameOverrides = const {},
    List<SkillAttachment> attachments = const [],
    List<WorkflowPromptTemplate> templates = const [],
  }) => WorkflowConfigLoaded(
    statuses: statuses ?? baseStatuses,
    designStagesEnabled: designStagesEnabled,
    stageDisplayNameOverrides: stageDisplayNameOverrides,
    attachments: attachments,
    templates: templates,
  );

  setUp(() {
    statusRepository = MockWorkflowStatusRepository();
    sddStageConfigRepository = MockSddStageConfigRepository();
    ticketRepository = MockTicketRepository();
    attachmentRepository = MockWorkflowSkillAttachmentRepository();
    templateRepository = MockWorkflowPromptTemplateRepository();
    when(() => statusRepository.onChanged).thenAnswer((_) => const Stream.empty());
    when(() => statusRepository.getAll()).thenAnswer((_) async => baseStatuses);
    when(
      () => sddStageConfigRepository.getDesignStagesEnabled(),
    ).thenAnswer((_) async => true);
    when(
      () => sddStageConfigRepository.getDisplayNameOverride(any()),
    ).thenAnswer((_) async => null);
    when(() => ticketRepository.getAllTickets()).thenAnswer((_) async => []);
    when(() => attachmentRepository.onChanged).thenAnswer((_) => const Stream.empty());
    when(() => attachmentRepository.getAll()).thenAnswer((_) async => []);
    when(() => templateRepository.getAll()).thenAnswer((_) async => []);
  });

  WorkflowConfigCubit buildCubit() => WorkflowConfigCubit(
    statusRepository,
    sddStageConfigRepository,
    ticketRepository,
    attachmentRepository,
    templateRepository,
  );

  group('load', () {
    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'emits WorkflowConfigLoaded with every configured status plus SDD settings',
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [loadedState()],
    );
  });

  group('createStatus', () {
    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects a name that collides with an existing base status',
      seed: loadedState,
      build: buildCubit,
      act: (cubit) => cubit.createStatus(
        WorkflowStatus(
          id: 'id-dupe',
          name: 'backlog',
          displayName: 'Backlog Again',
          sortOrder: 3,
        ),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => statusRepository.create(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'assigning an existing role to a new status moves it off the '
      'previous holder rather than rejecting',
      seed: loadedState,
      build: buildCubit,
      setUp: () {
        when(() => statusRepository.create(any())).thenAnswer((_) async {});
        when(() => statusRepository.update(any())).thenAnswer((_) async {});
      },
      act: (cubit) => cubit.createStatus(
        WorkflowStatus(
          id: 'id-new-done',
          name: 'closed',
          displayName: 'Closed',
          sortOrder: 3,
          role: WorkflowStatusRole.done,
        ),
      ),
      verify: (_) {
        verify(() => statusRepository.create(any())).called(1);
        // `done`'s prior holder is cleared, moving the role rather than
        // leaving two holders.
        verify(
          () => statusRepository.update(
            any(that: predicate<WorkflowStatus>((s) => s.id == done.id && s.role == null)),
          ),
        ).called(1);
      },
    );
  });

  group('updateStatus', () {
    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects clearing the sole holder of a role to none',
      seed: loadedState,
      build: buildCubit,
      act: (cubit) =>
          cubit.updateStatus(done.copyWith(role: () => null)),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => statusRepository.update(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects a rename that collides with another status name in scope',
      seed: loadedState,
      build: buildCubit,
      act: (cubit) => cubit.updateStatus(backlog.copyWith(name: 'done')),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => statusRepository.update(any()));
      },
    );
  });

  group('deleteStatus', () {
    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects deleting the sole holder of a role',
      seed: loadedState,
      build: buildCubit,
      act: (cubit) => cubit.deleteStatus(inProgress.id),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => statusRepository.delete(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects deleting a status currently in use by a live ticket',
      seed: loadedState,
      build: buildCubit,
      setUp: () {
        when(
          () => ticketRepository.getAllTickets(),
        ).thenAnswer((_) async => [_ticket(id: '1', status: 'backlog')]);
      },
      act: (cubit) => cubit.deleteStatus(backlog.id),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => statusRepository.delete(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'deletes a role-free, not-in-use status and reloads',
      seed: loadedState,
      build: buildCubit,
      setUp: () {
        when(() => statusRepository.delete(backlog.id)).thenAnswer((_) async {});
        when(
          () => statusRepository.getAll(),
        ).thenAnswer((_) async => [inProgress, done]);
      },
      act: (cubit) => cubit.deleteStatus(backlog.id),
      expect: () => [loadedState(statuses: [inProgress, done])],
    );
  });

  group('reorderStatuses', () {
    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'persists the new order and reloads',
      seed: loadedState,
      build: buildCubit,
      setUp: () {
        when(
          () => statusRepository.reorder([done.id, backlog.id, inProgress.id]),
        ).thenAnswer((_) async {});
      },
      act: (cubit) =>
          cubit.reorderStatuses([done.id, backlog.id, inProgress.id]),
      verify: (_) {
        verify(
          () => statusRepository.reorder([done.id, backlog.id, inProgress.id]),
        ).called(1);
      },
    );
  });

  group('setDesignStagesEnabled / setStageDisplayNameOverride', () {
    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'round-trips designStagesEnabled through the repository',
      seed: loadedState,
      build: buildCubit,
      setUp: () {
        when(
          () => sddStageConfigRepository.setDesignStagesEnabled(false),
        ).thenAnswer((_) async {});
        when(
          () => sddStageConfigRepository.getDesignStagesEnabled(),
        ).thenAnswer((_) async => false);
      },
      act: (cubit) => cubit.setDesignStagesEnabled(false),
      expect: () => [loadedState(designStagesEnabled: false)],
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'round-trips a stage display-name override through the repository',
      seed: loadedState,
      build: buildCubit,
      setUp: () {
        when(
          () => sddStageConfigRepository.setDisplayNameOverride(
            SddStage.exploring,
            'Kickoff',
          ),
        ).thenAnswer((_) async {});
        when(
          () => sddStageConfigRepository.getDisplayNameOverride(
            SddStage.exploring,
          ),
        ).thenAnswer((_) async => 'Kickoff');
      },
      act: (cubit) => cubit.setStageDisplayNameOverride(
        SddStage.exploring,
        'Kickoff',
      ),
      expect: () => [
        loadedState(
          stageDisplayNameOverrides: const {SddStage.exploring: 'Kickoff'},
        ),
      ],
    );
  });

  group('createAttachment / updateAttachment / deleteAttachment', () {
    final existing = SkillAttachment(
      id: 'attach-1',
      workflowStatusId: backlog.id,
      kind: SkillAttachmentKind.delegatedSkill,
      skillName: 'code-review',
      confidence: AutomationConfidence.gated,
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'creates an attachment on a free target and reloads',
      seed: loadedState,
      build: buildCubit,
      setUp: () {
        when(() => attachmentRepository.create(any())).thenAnswer((_) async {});
        when(
          () => attachmentRepository.getAll(),
        ).thenAnswer((_) async => [existing]);
      },
      act: (cubit) => cubit.createAttachment(existing),
      expect: () => [loadedState(attachments: [existing])],
      verify: (_) {
        verify(() => attachmentRepository.create(existing)).called(1);
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects creating an attachment with both workflowStatusId and '
      'sddStage set — /verify CRITICAL finding 3: neither entity nor '
      'either/or invariant is enforced anywhere',
      seed: loadedState,
      build: buildCubit,
      act: (cubit) => cubit.createAttachment(
        SkillAttachment(
          id: 'attach-both-targets',
          workflowStatusId: backlog.id,
          sddStage: SddStage.exploring,
          kind: SkillAttachmentKind.delegatedSkill,
          skillName: 'code-review',
          confidence: AutomationConfidence.gated,
        ),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => attachmentRepository.create(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects creating an attachment with neither workflowStatusId nor '
      'sddStage set',
      seed: loadedState,
      build: buildCubit,
      act: (cubit) => cubit.createAttachment(
        const SkillAttachment(
          id: 'attach-no-target',
          kind: SkillAttachmentKind.delegatedSkill,
          skillName: 'code-review',
          confidence: AutomationConfidence.gated,
        ),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => attachmentRepository.create(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects creating an aionNativeTemplate attachment that sets '
      'skillName instead of templateId',
      seed: loadedState,
      build: buildCubit,
      act: (cubit) => cubit.createAttachment(
        SkillAttachment(
          id: 'attach-kind-mismatch',
          workflowStatusId: backlog.id,
          kind: SkillAttachmentKind.aionNativeTemplate,
          skillName: 'code-review',
          confidence: AutomationConfidence.gated,
        ),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => attachmentRepository.create(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects creating a delegatedSkill attachment that sets templateId '
      'instead of skillName',
      seed: loadedState,
      build: buildCubit,
      act: (cubit) => cubit.createAttachment(
        SkillAttachment(
          id: 'attach-kind-mismatch-2',
          workflowStatusId: backlog.id,
          kind: SkillAttachmentKind.delegatedSkill,
          templateId: 'template-1',
          confidence: AutomationConfidence.gated,
        ),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => attachmentRepository.create(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects updating an attachment into an either/or-invariant '
      'violation, same as createAttachment',
      seed: () => loadedState(attachments: [existing]),
      build: buildCubit,
      act: (cubit) => cubit.updateAttachment(
        existing.copyWith(templateId: () => 'template-1'),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => attachmentRepository.update(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects creating a second attachment on a target that already has one',
      seed: () => loadedState(attachments: [existing]),
      build: buildCubit,
      act: (cubit) => cubit.createAttachment(
        SkillAttachment(
          id: 'attach-2',
          workflowStatusId: backlog.id,
          kind: SkillAttachmentKind.aionNativeTemplate,
          templateId: 'template-1',
          confidence: AutomationConfidence.auto,
        ),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => attachmentRepository.create(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects updating an attachment onto a different target already held',
      seed: () => loadedState(
        attachments: [
          existing,
          SkillAttachment(
            id: 'attach-2',
            workflowStatusId: inProgress.id,
            kind: SkillAttachmentKind.aionNativeTemplate,
            templateId: 'template-1',
            confidence: AutomationConfidence.auto,
          ),
        ],
      ),
      build: buildCubit,
      act: (cubit) => cubit.updateAttachment(
        existing.copyWith(workflowStatusId: () => inProgress.id),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => attachmentRepository.update(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'updates an attachment and reloads',
      seed: () => loadedState(attachments: [existing]),
      build: buildCubit,
      setUp: () {
        when(() => attachmentRepository.update(any())).thenAnswer((_) async {});
        final updated = existing.copyWith(confidence: AutomationConfidence.auto);
        when(
          () => attachmentRepository.getAll(),
        ).thenAnswer((_) async => [updated]);
      },
      act: (cubit) => cubit.updateAttachment(
        existing.copyWith(confidence: AutomationConfidence.auto),
      ),
      expect: () => [
        loadedState(
          attachments: [existing.copyWith(confidence: AutomationConfidence.auto)],
        ),
      ],
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'deletes an attachment and reloads',
      seed: () => loadedState(attachments: [existing]),
      build: buildCubit,
      setUp: () {
        when(() => attachmentRepository.delete(existing.id)).thenAnswer((_) async {});
        when(() => attachmentRepository.getAll()).thenAnswer((_) async => []);
      },
      act: (cubit) => cubit.deleteAttachment(existing.id),
      expect: () => [loadedState()],
      verify: (_) {
        verify(() => attachmentRepository.delete(existing.id)).called(1);
      },
    );
  });

  group('createTemplate / updateTemplate / deleteTemplate', () {
    const existingTemplate = WorkflowPromptTemplate(
      id: 'template-1',
      name: 'Repro Steps Request',
      body: 'Please provide steps to reproduce {{ticket.title}}.',
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'creates a template and reloads',
      seed: loadedState,
      build: buildCubit,
      setUp: () {
        when(() => templateRepository.create(any())).thenAnswer((_) async {});
        when(
          () => templateRepository.getAll(),
        ).thenAnswer((_) async => [existingTemplate]);
      },
      act: (cubit) => cubit.createTemplate(existingTemplate),
      expect: () => [loadedState(templates: [existingTemplate])],
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects a template name collision',
      seed: () => loadedState(templates: [existingTemplate]),
      build: buildCubit,
      act: (cubit) => cubit.createTemplate(
        const WorkflowPromptTemplate(
          id: 'template-2',
          name: 'Repro Steps Request',
          body: 'Different body.',
        ),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => templateRepository.create(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects a rename that collides with another template name',
      seed: () => loadedState(
        templates: const [
          existingTemplate,
          WorkflowPromptTemplate(id: 'template-2', name: 'Other', body: 'x'),
        ],
      ),
      build: buildCubit,
      act: (cubit) => cubit.updateTemplate(
        const WorkflowPromptTemplate(
          id: 'template-2',
          name: 'Repro Steps Request',
          body: 'x',
        ),
      ),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => templateRepository.update(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects deleting a template a live attachment still references',
      seed: () => loadedState(
        templates: [existingTemplate],
        attachments: [
          SkillAttachment(
            id: 'attach-1',
            workflowStatusId: backlog.id,
            kind: SkillAttachmentKind.aionNativeTemplate,
            templateId: existingTemplate.id,
            confidence: AutomationConfidence.gated,
          ),
        ],
      ),
      build: buildCubit,
      act: (cubit) => cubit.deleteTemplate(existingTemplate.id),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => templateRepository.delete(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'deletes an unreferenced template and reloads',
      seed: () => loadedState(templates: [existingTemplate]),
      build: buildCubit,
      setUp: () {
        when(
          () => templateRepository.delete(existingTemplate.id),
        ).thenAnswer((_) async {});
        when(() => templateRepository.getAll()).thenAnswer((_) async => []);
      },
      act: (cubit) => cubit.deleteTemplate(existingTemplate.id),
      expect: () => [loadedState()],
    );
  });
}
