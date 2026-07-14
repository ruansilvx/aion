import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/exceptions/ticket_has_children_exception.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

void main() {
  late MockTicketRepository repository;

  final ticket = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Test ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(ticket);
    registerFallbackValue(TicketStatus.backlog);
  });

  setUp(() {
    repository = MockTicketRepository();
  });

  group('TicketsCubit', () {
    blocTest<TicketsCubit, TicketsState>(
      'loadTickets emits [TicketsLoading, TicketsLoaded] on success',
      setUp: () {
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [ticket]);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.loadTickets(),
      expect: () => [
        const TicketsLoading(),
        TicketsLoaded([ticket]),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'loadTickets emits [TicketsLoading, TicketsError] on exception',
      setUp: () {
        when(() => repository.getAllTickets()).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.loadTickets(),
      expect: () => [const TicketsLoading(), isA<TicketsError>()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'createTicket emits [TicketCreating, TicketCreated] on success',
      setUp: () {
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [ticket]);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) =>
          cubit.createTicket(type: TicketType.task, title: 'New ticket'),
      expect: () => [
        const TicketCreating([]),
        TicketCreated([ticket]),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'createTicket emits [TicketCreating, TicketsError] on exception',
      setUp: () {
        when(() => repository.createTicket(any())).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) =>
          cubit.createTicket(type: TicketType.task, title: 'New ticket'),
      expect: () => [const TicketCreating([]), isA<TicketsError>()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicketStatus emits [TicketStatusUpdating, TicketStatusUpdated] on success',
      setUp: () {
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [ticket.copyWith(status: TicketStatus.done)]);
      },
      build: () => TicketsCubit(repository),
      seed: () => TicketsLoaded([ticket]),
      act: (cubit) => cubit.updateTicketStatus(ticket.id, TicketStatus.done),
      expect: () => [
        TicketStatusUpdating([ticket.copyWith(status: TicketStatus.done)]),
        TicketStatusUpdated([ticket.copyWith(status: TicketStatus.done)]),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicketStatus emits [TicketStatusUpdating, TicketsError] on exception',
      setUp: () {
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      seed: () => TicketsLoaded([ticket]),
      act: (cubit) => cubit.updateTicketStatus(ticket.id, TicketStatus.done),
      expect: () => [
        TicketStatusUpdating([ticket.copyWith(status: TicketStatus.done)]),
        isA<TicketsError>(),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicket emits [TicketDetailLoaded] with the refreshed ticket on success',
      setUp: () {
        when(() => repository.updateTicket(any())).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket.copyWith(title: 'Updated title'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) =>
          cubit.updateTicket(ticket.copyWith(title: 'Updated title')),
      expect: () => [
        TicketDetailLoaded(ticket.copyWith(title: 'Updated title')),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicket emits [TicketsError] when the repository throws',
      setUp: () {
        when(() => repository.updateTicket(any())).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.updateTicket(ticket),
      expect: () => [isA<TicketsError>()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'changeTicketStatus emits [TicketDetailLoaded] with the refreshed ticket on success',
      setUp: () {
        when(
          () => repository.updateTicketStatus(ticket.id, TicketStatus.done),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket.copyWith(status: TicketStatus.done));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.changeTicketStatus(ticket, TicketStatus.done),
      expect: () => [
        TicketDetailLoaded(ticket.copyWith(status: TicketStatus.done)),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'changeTicketStatus emits [TicketsError] when the repository throws',
      setUp: () {
        when(
          () => repository.updateTicketStatus(ticket.id, TicketStatus.done),
        ).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.changeTicketStatus(ticket, TicketStatus.done),
      verify: (_) {
        verifyNever(() => repository.getTicketById(any()));
      },
      expect: () => [isA<TicketsError>()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'deleteTicket emits [TicketDeleting, TicketDeleted] on success',
      setUp: () {
        when(() => repository.deleteTicket(ticket.id)).thenAnswer((_) async {});
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.deleteTicket(ticket.id),
      expect: () => [const TicketDeleting(), const TicketDeleted()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'deleteTicket emits [TicketDeleting, TicketsError(hasChildren), '
      'TicketDetailLoaded] when blocked by structural children',
      setUp: () {
        when(
          () => repository.deleteTicket(ticket.id),
        ).thenThrow(const TicketHasChildrenException(2));
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.deleteTicket(ticket.id),
      expect: () => [
        const TicketDeleting(),
        const TicketsError(
          '',
          reason: TicketsErrorReason.hasChildren,
          childCount: 2,
        ),
        TicketDetailLoaded(ticket),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'deleteTicket emits [TicketDeleting, TicketsError] on a generic failure',
      setUp: () {
        when(
          () => repository.deleteTicket(ticket.id),
        ).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.deleteTicket(ticket.id),
      expect: () => [const TicketDeleting(), isA<TicketsError>()],
    );

    // Multi-level hierarchy fixture: ticket (root) -> child -> grandchild,
    // plus an unrelated ticket with no parent (a valid reparent target).
    final child = Ticket(
      id: '2',
      ticketId: 'AIO-2',
      type: TicketType.task,
      title: 'Child ticket',
      status: TicketStatus.backlog,
      parentId: ticket.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final grandchild = Ticket(
      id: '3',
      ticketId: 'AIO-3',
      type: TicketType.task,
      title: 'Grandchild ticket',
      status: TicketStatus.backlog,
      parentId: child.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final unrelated = Ticket(
      id: '4',
      ticketId: 'AIO-4',
      type: TicketType.task,
      title: 'Unrelated ticket',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final reparented = Ticket(
      id: ticket.id,
      ticketId: ticket.ticketId,
      type: ticket.type,
      title: ticket.title,
      status: ticket.status,
      parentId: unrelated.id,
      createdAt: ticket.createdAt,
      updatedAt: ticket.updatedAt,
    );
    final cleared = Ticket(
      id: ticket.id,
      ticketId: ticket.ticketId,
      type: ticket.type,
      title: ticket.title,
      status: ticket.status,
      createdAt: ticket.createdAt,
      updatedAt: ticket.updatedAt,
    );
    final epic = Ticket(
      id: '5',
      ticketId: 'AIO-5',
      type: TicketType.epic,
      title: 'Epic ticket',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    group('getValidParentCandidates', () {
      test('excludes self and the full multi-level descendant chain', () async {
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [ticket, child, grandchild, unrelated]);

        final candidates = await TicketsCubit(
          repository,
        ).getValidParentCandidates(ticket);

        expect(candidates.map((t) => t.id), [unrelated.id]);
      });
    });

    group('updateTicketParent', () {
      blocTest<TicketsCubit, TicketsState>(
        'persists a valid reparent and emits [TicketDetailLoaded]',
        setUp: () {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [ticket, child, unrelated]);
          when(
            () => repository.updateTicketParent(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => reparented);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, unrelated.id),
        verify: (_) {
          verify(
            () => repository.updateTicketParent(ticket.id, unrelated.id),
          ).called(1);
        },
        expect: () => [TicketDetailLoaded(reparented)],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects self-parenting without calling the repository',
        setUp: () {
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, ticket.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(ticket),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting an epic without calling the repository',
        setUp: () {
          when(
            () => repository.getTicketById(epic.id),
          ).thenAnswer((_) async => epic);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(epic, unrelated.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(epic),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting onto a descendant without calling the repository',
        setUp: () {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [ticket, child, unrelated]);
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, child.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(ticket),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'persists clearing the parent to null',
        setUp: () {
          when(
            () => repository.updateTicketParent(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => cleared);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, null),
        verify: (_) {
          verify(
            () => repository.updateTicketParent(ticket.id, null),
          ).called(1);
        },
        expect: () => [TicketDetailLoaded(cleared)],
      );
    });
  });
}
