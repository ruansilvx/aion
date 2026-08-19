// test/features/tickets/cubit/tickets_cubit_workflow_status_test.dart — TicketsCubit gate-check tests against a renamed WorkflowStatus fixture.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockWorkflowStatusRepository extends Mock
    implements WorkflowStatusRepository {}

/// Covers T32: every gate-check call site TicketsCubit migrated off
/// literal `TicketStatus` comparisons (T17/T18), re-verified against a
/// [WorkflowStatus] fixture where role assignments differ from the
/// default baseline preset — a project that renamed the
/// `executionTrigger`-role status from `"inProgress"` to `"working"` and
/// the `done`-role status from `"done"` to `"closed"`, with the literal
/// names `"inProgress"`/`"done"` repurposed as plain no-role statuses.
/// Confirms every gate keys off [WorkflowStatusRole], never the literal
/// status name.
void main() {
  late MockTicketRepository repository;
  late MockTicketLinkRepository linkRepository;
  late MockWorkflowStatusRepository workflowStatusRepository;

  // The renamed fixture: `working` (not `inProgress`) holds
  // executionTrigger; `closed` (not `done`) holds done. `inProgress`/
  // `done` are still present as plain, role-free statuses — proving a
  // literal-name check would behave exactly backwards against this set.
  final renamedStatuses = [
    const WorkflowStatus(
      id: 'id-backlog',
      name: 'backlog',
      displayName: 'Backlog',
      sortOrder: 0,
    ),
    const WorkflowStatus(
      id: 'id-in-progress-literal',
      name: 'inProgress',
      displayName: 'In Progress (unused, no role)',
      sortOrder: 1,
    ),
    const WorkflowStatus(
      id: 'id-working',
      name: 'working',
      displayName: 'Working',
      sortOrder: 2,
      role: WorkflowStatusRole.executionTrigger,
    ),
    const WorkflowStatus(
      id: 'id-done-literal',
      name: 'done',
      displayName: 'Done (unused, no role)',
      sortOrder: 3,
    ),
    const WorkflowStatus(
      id: 'id-closed',
      name: 'closed',
      displayName: 'Closed',
      sortOrder: 4,
      role: WorkflowStatusRole.done,
    ),
  ];

  Ticket ticket({required String id, required String status, String? parentId}) =>
      Ticket(
        id: id,
        ticketId: 'AIO-$id',
        type: TicketType.task,
        title: 'Ticket $id',
        status: status,
        parentId: parentId,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  setUpAll(() {
    registerFallbackValue(
      ticket(id: 'fallback', status: 'backlog'),
    );
  });

  setUp(() {
    repository = MockTicketRepository();
    linkRepository = MockTicketLinkRepository();
    workflowStatusRepository = MockWorkflowStatusRepository();
    when(
      () => workflowStatusRepository.onChanged,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => workflowStatusRepository.getAll(),
    ).thenAnswer((_) async => renamedStatuses);
  });

  TicketsCubit buildCubit() => TicketsCubit(
    repository,
    linkRepository: linkRepository,
    workflowStatusRepository: workflowStatusRepository,
  );

  group('_interceptBlockedDependencyTrigger (via changeTicketStatus)', () {
    test(
      'moving to the role-holding "working" status is blocked by an '
      'unresolved dependency, even though its name is not "inProgress"',
      () async {
        final blocker = ticket(id: 'blocker', status: 'backlog');
        final blocked = ticket(id: 'blocked', status: 'backlog');
        when(
          () => linkRepository.getLinksForTicket(blocked.id),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: blocked.id,
              targetTicketId: blocker.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(
          () => repository.getTicketById(blocker.id),
        ).thenAnswer((_) async => blocker);

        final cubit = buildCubit();
        await untilCalled(() => workflowStatusRepository.getAll());

        await cubit.changeTicketStatus(blocked, 'working');

        verifyNever(() => repository.updateTicketStatus(any(), any()));
      },
    );

    test(
      'moving to the literal "inProgress" status is NOT blocked — that '
      'name holds no role in this project\'s renamed configuration',
      () async {
        final blocker = ticket(id: 'blocker', status: 'backlog');
        final blocked = ticket(id: 'blocked', status: 'backlog');
        when(
          () => linkRepository.getLinksForTicket(blocked.id),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: blocked.id,
              targetTicketId: blocker.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(
          () => repository.updateTicketStatus(blocked.id, 'inProgress'),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(blocked.id),
        ).thenAnswer((_) async => blocked.copyWith(status: 'inProgress'));

        final cubit = buildCubit();
        await untilCalled(() => workflowStatusRepository.getAll());

        await cubit.changeTicketStatus(blocked, 'inProgress');

        verify(
          () => repository.updateTicketStatus(blocked.id, 'inProgress'),
        ).called(1);
      },
    );
  });

  group('_isTicketBlocked blocker-resolution check (T18)', () {
    test(
      'a blocker sitting at "closed" (the renamed done-role status) '
      'resolves the block, even though its name is not "done"',
      () async {
        final blocker = ticket(id: 'blocker', status: 'closed');
        final blocked = ticket(id: 'blocked', status: 'backlog');
        when(
          () => linkRepository.getLinksForTicket(blocked.id),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: blocked.id,
              targetTicketId: blocker.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(
          () => repository.getTicketById(blocker.id),
        ).thenAnswer((_) async => blocker);
        when(
          () => repository.updateTicketStatus(blocked.id, 'working'),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(blocked.id),
        ).thenAnswer((_) async => blocked.copyWith(status: 'working'));

        final cubit = buildCubit();
        await untilCalled(() => workflowStatusRepository.getAll());

        await cubit.changeTicketStatus(blocked, 'working');

        // Not blocked — the blocker is at the done-role status, so the
        // write proceeds.
        verify(
          () => repository.updateTicketStatus(blocked.id, 'working'),
        ).called(1);
      },
    );

    test(
      'a blocker sitting at the literal "done" status does NOT resolve '
      'the block — that name holds no role in this renamed configuration',
      () async {
        final blocker = ticket(id: 'blocker', status: 'done');
        final blocked = ticket(id: 'blocked', status: 'backlog');
        when(
          () => linkRepository.getLinksForTicket(blocked.id),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: blocked.id,
              targetTicketId: blocker.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(
          () => repository.getTicketById(blocker.id),
        ).thenAnswer((_) async => blocker);

        final cubit = buildCubit();
        await untilCalled(() => workflowStatusRepository.getAll());

        await cubit.changeTicketStatus(blocked, 'working');

        verifyNever(() => repository.updateTicketStatus(any(), any()));
      },
    );
  });
}
