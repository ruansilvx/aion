import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/tickets/data/repositories/git_projecting_ticket_repository.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketGitProjector extends Mock implements TicketGitProjector {}

void main() {
  late MockTicketRepository inner;
  late MockTicketGitProjector projector;
  late GitProjectingTicketRepository repository;

  const rootPath = '/root';

  final ticket = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Test ticket',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(ticket);
  });

  setUp(() {
    inner = MockTicketRepository();
    projector = MockTicketGitProjector();
    repository = GitProjectingTicketRepository(inner, projector, rootPath);
    when(
      () => projector.project(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(() => inner.getTicketById(ticket.id)).thenAnswer((_) async => ticket);
  });

  group('projected methods', () {
    test('createTicket delegates then projects "created"', () async {
      when(() => inner.createTicket(ticket)).thenAnswer((_) async {});

      await repository.createTicket(ticket);
      // The projection is fired unawaited — pump the event queue once so
      // the fire-and-forget Future has a chance to complete before
      // asserting on it.
      await pumpEventQueue();

      verify(() => inner.createTicket(ticket)).called(1);
      verify(() => projector.project(ticket, rootPath, 'created')).called(1);
    });

    test(
      'updateTicketStatus delegates then projects "status-changed"',
      () async {
        when(
          () => inner.updateTicketStatus(ticket.id, 'done'),
        ).thenAnswer((_) async {});

        await repository.updateTicketStatus(ticket.id, 'done');
        await pumpEventQueue();

        verify(() => inner.updateTicketStatus(ticket.id, 'done')).called(1);
        verify(
          () => projector.project(ticket, rootPath, 'status-changed'),
        ).called(1);
      },
    );

    test(
      'updateStatusForIds delegates then projects "status-changed" once '
      'per id',
      () async {
        final other = Ticket(
          id: '2',
          ticketId: 'AIO-2',
          type: TicketType.task,
          title: 'Other ticket',
          status: 'backlog',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => inner.updateStatusForIds([ticket.id, other.id], 'done'),
        ).thenAnswer((_) async {});
        when(
          () => inner.getTicketById(other.id),
        ).thenAnswer((_) async => other);

        await repository.updateStatusForIds([ticket.id, other.id], 'done');
        await pumpEventQueue();

        verify(
          () => projector.project(ticket, rootPath, 'status-changed'),
        ).called(1);
        verify(
          () => projector.project(other, rootPath, 'status-changed'),
        ).called(1);
      },
    );

    test(
      'updateTicketSddStage delegates then projects "stage-changed"',
      () async {
        when(
          () => inner.updateTicketSddStage(ticket.id, SddStage.exploring),
        ).thenAnswer((_) async {});

        await repository.updateTicketSddStage(ticket.id, SddStage.exploring);
        await pumpEventQueue();

        verify(
          () => inner.updateTicketSddStage(ticket.id, SddStage.exploring),
        ).called(1);
        verify(
          () => projector.project(ticket, rootPath, 'stage-changed'),
        ).called(1);
      },
    );

    test('updateTicketParent delegates then projects "reparented"', () async {
      when(
        () => inner.updateTicketParent(ticket.id, 'parent-1'),
      ).thenAnswer((_) async {});

      await repository.updateTicketParent(ticket.id, 'parent-1');
      await pumpEventQueue();

      verify(
        () => inner.updateTicketParent(ticket.id, 'parent-1'),
      ).called(1);
      verify(
        () => projector.project(ticket, rootPath, 'reparented'),
      ).called(1);
    });

    test(
      'trashTicket delegates then awaits its "trashed" projection before '
      'returning',
      () async {
        when(() => inner.trashTicket(ticket.id)).thenAnswer((_) async {});

        await repository.trashTicket(ticket.id);

        verify(() => inner.trashTicket(ticket.id)).called(1);
        // No `pumpEventQueue()` needed here — unlike the fire-and-forget
        // methods above, trashTicket awaits its own projection call, so
        // it's already complete by the time `await` above returns.
        verify(() => projector.project(ticket, rootPath, 'trashed')).called(1);
      },
    );

    test(
      'restoreTicket delegates then awaits its "restored" projection '
      'before returning',
      () async {
        when(() => inner.restoreTicket(ticket.id)).thenAnswer((_) async {});

        await repository.restoreTicket(ticket.id);

        verify(() => inner.restoreTicket(ticket.id)).called(1);
        verify(
          () => projector.project(ticket, rootPath, 'restored'),
        ).called(1);
      },
    );

    test(
      'trashTicket does not propagate a projection failure — the trash '
      'above already succeeded and must not be reported as an error',
      () async {
        when(() => inner.trashTicket(ticket.id)).thenAnswer((_) async {});
        when(
          () => projector.project(ticket, rootPath, 'trashed'),
        ).thenThrow(Exception('git blew up'));

        // Must complete normally (not throw) despite the projector
        // throwing — trashTicket already succeeded via `inner` above.
        await repository.trashTicket(ticket.id);

        verify(() => inner.trashTicket(ticket.id)).called(1);
      },
    );

    test(
      'restoreTicket does not propagate a projection failure — the '
      'restore above already succeeded and must not be reported as an '
      'error',
      () async {
        when(() => inner.restoreTicket(ticket.id)).thenAnswer((_) async {});
        when(
          () => projector.project(ticket, rootPath, 'restored'),
        ).thenThrow(Exception('git blew up'));

        await repository.restoreTicket(ticket.id);

        verify(() => inner.restoreTicket(ticket.id)).called(1);
      },
    );

    test(
      'no-ops projection when the ticket no longer exists after the write',
      () async {
        when(
          () => inner.getTicketById(ticket.id),
        ).thenAnswer((_) async => null);
        when(() => inner.createTicket(ticket)).thenAnswer((_) async {});

        await repository.createTicket(ticket);
        await pumpEventQueue();

        verifyNever(() => projector.project(any(), any(), any()));
      },
    );
  });

  group('pass-through methods (no projection)', () {
    test('updateTicket does not project', () async {
      when(() => inner.updateTicket(ticket)).thenAnswer((_) async {});

      await repository.updateTicket(ticket);
      await pumpEventQueue();

      verify(() => inner.updateTicket(ticket)).called(1);
      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('updatePriorityForIds does not project', () async {
      when(
        () => inner.updatePriorityForIds([ticket.id], TicketPriority.high),
      ).thenAnswer((_) async {});

      await repository.updatePriorityForIds([ticket.id], TicketPriority.high);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('addTimeSpent does not project', () async {
      when(
        () => inner.addTimeSpent(ticket.id, 30),
      ).thenAnswer((_) async {});

      await repository.addTimeSpent(ticket.id, 30);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('applyEstimationSuggestion does not project', () async {
      when(
        () => inner.applyEstimationSuggestion(ticket.id),
      ).thenAnswer((_) async {});

      await repository.applyEstimationSuggestion(ticket.id);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('updateRollup does not project (owned by TicketRollupRecomputer '
        "'s own batched projectBatch call)", () async {
      when(
        () => inner.updateRollup(
          ticket.id,
          estimateRollup: 5,
          timeSpentRollup: 5,
        ),
      ).thenAnswer((_) async {});

      await repository.updateRollup(
        ticket.id,
        estimateRollup: 5,
        timeSpentRollup: 5,
      );
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
      verifyNever(() => projector.projectBatch(any(), any(), any()));
    });

    test('importTicket does not project', () async {
      when(() => inner.importTicket(ticket)).thenAnswer((_) async {});

      await repository.importTicket(ticket);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('permanentlyDeleteTicket does not project', () async {
      when(
        () => inner.permanentlyDeleteTicket(ticket.id),
      ).thenAnswer((_) async {});

      await repository.permanentlyDeleteTicket(ticket.id);
      await pumpEventQueue();

      verifyNever(() => projector.project(any(), any(), any()));
    });

    test('getAllTickets delegates without touching the projector', () async {
      when(() => inner.getAllTickets()).thenAnswer((_) async => [ticket]);

      final result = await repository.getAllTickets();

      expect(result, [ticket]);
      verifyNever(() => projector.project(any(), any(), any()));
    });
  });
}
