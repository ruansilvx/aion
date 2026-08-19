// test/features/tickets/cubit/workflow_config_cubit_test.dart — WorkflowConfigCubit tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/tickets/tickets.dart';

class MockWorkflowStatusRepository extends Mock
    implements WorkflowStatusRepository {}

class MockSddStageConfigRepository extends Mock
    implements SddStageConfigRepository {}

class MockTicketRepository extends Mock implements TicketRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(SddStage.exploring);
    registerFallbackValue(
      const WorkflowStatus(id: 'fallback', name: 'fallback', displayName: 'Fallback', sortOrder: 0),
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

  setUp(() {
    statusRepository = MockWorkflowStatusRepository();
    sddStageConfigRepository = MockSddStageConfigRepository();
    ticketRepository = MockTicketRepository();
    when(() => statusRepository.onChanged).thenAnswer((_) => const Stream.empty());
    when(() => statusRepository.getAll()).thenAnswer((_) async => baseStatuses);
    when(
      () => sddStageConfigRepository.getDesignStagesEnabled(),
    ).thenAnswer((_) async => true);
    when(
      () => sddStageConfigRepository.getDisplayNameOverride(any()),
    ).thenAnswer((_) async => null);
    when(() => ticketRepository.getAllTickets()).thenAnswer((_) async => []);
  });

  WorkflowConfigCubit buildCubit() =>
      WorkflowConfigCubit(statusRepository, sddStageConfigRepository, ticketRepository);

  group('load', () {
    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'emits WorkflowConfigLoaded with every configured status plus SDD settings',
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [
        WorkflowConfigLoaded(
          statuses: baseStatuses,
          designStagesEnabled: true,
          stageDisplayNameOverrides: const {},
        ),
      ],
    );
  });

  group('createStatus', () {
    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects a name that collides with an existing base status',
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
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
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
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
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
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
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
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
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
      build: buildCubit,
      act: (cubit) => cubit.deleteStatus(inProgress.id),
      expect: () => [isA<WorkflowConfigError>()],
      verify: (_) {
        verifyNever(() => statusRepository.delete(any()));
      },
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'rejects deleting a status currently in use by a live ticket',
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
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
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
      build: buildCubit,
      setUp: () {
        when(() => statusRepository.delete(backlog.id)).thenAnswer((_) async {});
        when(
          () => statusRepository.getAll(),
        ).thenAnswer((_) async => [inProgress, done]);
      },
      act: (cubit) => cubit.deleteStatus(backlog.id),
      expect: () => [
        WorkflowConfigLoaded(
          statuses: [inProgress, done],
          designStagesEnabled: true,
          stageDisplayNameOverrides: const {},
        ),
      ],
    );
  });

  group('reorderStatuses', () {
    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'persists the new order and reloads',
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
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
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
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
      expect: () => [
        WorkflowConfigLoaded(
          statuses: baseStatuses,
          designStagesEnabled: false,
          stageDisplayNameOverrides: const {},
        ),
      ],
    );

    blocTest<WorkflowConfigCubit, WorkflowConfigState>(
      'round-trips a stage display-name override through the repository',
      seed: () => WorkflowConfigLoaded(
        statuses: baseStatuses,
        designStagesEnabled: true,
        stageDisplayNameOverrides: const {},
      ),
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
        WorkflowConfigLoaded(
          statuses: baseStatuses,
          designStagesEnabled: true,
          stageDisplayNameOverrides: const {SddStage.exploring: 'Kickoff'},
        ),
      ],
    );
  });
}
