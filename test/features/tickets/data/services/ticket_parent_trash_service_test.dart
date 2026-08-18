import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/data/services/ticket_parent_change_result.dart';
import 'package:aion/features/tickets/data/services/ticket_parent_trash_service.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketGitProjector extends Mock implements TicketGitProjector {}

void main() {
  late MockTicketRepository repository;
  late MockTicketGitProjector gitProjector;

  final ticket = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Test ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
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
  // Type is story (not task) so it remains a valid reparent target for
  // `ticket` (a task) under the type-compatibility rule: story can parent
  // task, task cannot parent task.
  final unrelated = Ticket(
    id: '3',
    ticketId: 'AIO-3',
    type: TicketType.story,
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
  final epic = Ticket(
    id: '4',
    ticketId: 'AIO-4',
    type: TicketType.epic,
    title: 'Epic ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final otherTask = Ticket(
    id: '5',
    ticketId: 'AIO-5',
    type: TicketType.task,
    title: 'Another task ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final inboxChat = Ticket(
    id: '6',
    ticketId: 'AIO-6',
    type: TicketType.chat,
    title: 'Inbox chat',
    status: TicketStatus.backlog,
    inboxPurpose: InboxPurpose.qa,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final trashedTicket = Ticket(
    id: '7',
    ticketId: 'AIO-7',
    type: TicketType.resource,
    title: 'Trashed ticket',
    status: TicketStatus.backlog,
    deletedAt: DateTime(2026, 1, 2),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(ticket);
  });

  setUp(() {
    repository = MockTicketRepository();
    gitProjector = MockTicketGitProjector();
    when(
      () => gitProjector.project(any(), any(), any()),
    ).thenAnswer((_) async {});
  });

  group('changeParent', () {
    test('persists a valid reparent and returns ParentChangeSuccess', () async {
      when(
        () => repository.getAllTickets(),
      ).thenAnswer((_) async => [ticket, child, unrelated]);
      when(
        () => repository.updateTicketParent(ticket.id, unrelated.id),
      ).thenAnswer((_) async {});
      when(
        () => repository.getTicketById(unrelated.id),
      ).thenAnswer((_) async => unrelated);
      when(
        () => repository.getTicketById(ticket.id),
      ).thenAnswer((_) async => reparented);

      final service = TicketParentTrashService(repository);
      final result = await service.changeParent(ticket, unrelated.id);

      expect(result, isA<ParentChangeSuccess>());
      expect((result as ParentChangeSuccess).ticket, reparented);
      verify(
        () => repository.updateTicketParent(ticket.id, unrelated.id),
      ).called(1);
    });

    test('rejects self-parenting without calling the repository', () async {
      final service = TicketParentTrashService(repository);
      final result = await service.changeParent(ticket, ticket.id);

      expect(result, const ParentChangeRejected());
      verifyNever(() => repository.updateTicketParent(any(), any()));
    });

    test(
      'rejects reparenting an always-root type (epic) without calling '
      'the repository',
      () async {
        final service = TicketParentTrashService(repository);
        final result = await service.changeParent(epic, unrelated.id);

        expect(result, const ParentChangeRejected());
        verifyNever(() => repository.updateTicketParent(any(), any()));
      },
    );

    test(
      'rejects reparenting an Inbox-spawned chat without calling the '
      'repository',
      () async {
        final service = TicketParentTrashService(repository);
        final result = await service.changeParent(inboxChat, ticket.id);

        expect(result, const ParentChangeRejected());
        verifyNever(() => repository.updateTicketParent(any(), any()));
      },
    );

    test(
      'rejects reparenting onto a descendant (cycle) without calling the '
      'repository',
      () async {
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [ticket, child, unrelated]);

        final service = TicketParentTrashService(repository);
        final result = await service.changeParent(ticket, child.id);

        expect(result, const ParentChangeRejected());
        verifyNever(() => repository.updateTicketParent(any(), any()));
      },
    );

    test(
      'rejects reparenting under a type-incompatible candidate (task '
      'under task) without calling the repository',
      () async {
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [ticket, otherTask]);
        when(
          () => repository.getTicketById(otherTask.id),
        ).thenAnswer((_) async => otherTask);

        final service = TicketParentTrashService(repository);
        final result = await service.changeParent(ticket, otherTask.id);

        expect(result, const ParentChangeRejected());
        verifyNever(() => repository.updateTicketParent(any(), any()));
      },
    );
  });

  group('trash', () {
    test(
      'calls TicketRepository.trashTicket and projects "trashed" when a '
      'TicketGitProjector is supplied',
      () async {
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
        when(() => repository.trashTicket(ticket.id)).thenAnswer((_) async {});

        final service = TicketParentTrashService(
          repository,
          gitProjector: gitProjector,
          projectRootPath: '/root',
        );
        final result = await service.trash(ticket.id);

        expect(result, ticket);
        verify(() => repository.trashTicket(ticket.id)).called(1);
        verify(
          () => gitProjector.project(ticket, '/root', 'trashed'),
        ).called(1);
      },
    );

    test('no-ops git projection when no TicketGitProjector is supplied', () async {
      when(
        () => repository.getTicketById(ticket.id),
      ).thenAnswer((_) async => ticket);
      when(() => repository.trashTicket(ticket.id)).thenAnswer((_) async {});

      final service = TicketParentTrashService(repository);
      final result = await service.trash(ticket.id);

      expect(result, ticket);
      verifyNever(() => gitProjector.project(any(), any(), any()));
    });
  });

  group('restore', () {
    test(
      'calls TicketRepository.restoreTicket and projects "restored" when '
      'a TicketGitProjector is supplied',
      () async {
        when(
          () => repository.getTicketById(trashedTicket.id),
        ).thenAnswer((_) async => trashedTicket);
        when(
          () => repository.restoreTicket(trashedTicket.id),
        ).thenAnswer((_) async {});

        final service = TicketParentTrashService(
          repository,
          gitProjector: gitProjector,
          projectRootPath: '/root',
        );
        final result = await service.restore(trashedTicket.id);

        expect(result, trashedTicket);
        verify(() => repository.restoreTicket(trashedTicket.id)).called(1);
        verify(
          () => gitProjector.project(trashedTicket, '/root', 'restored'),
        ).called(1);
      },
    );

    test('no-ops git projection when no TicketGitProjector is supplied', () async {
      when(
        () => repository.getTicketById(trashedTicket.id),
      ).thenAnswer((_) async => trashedTicket);
      when(
        () => repository.restoreTicket(trashedTicket.id),
      ).thenAnswer((_) async {});

      final service = TicketParentTrashService(repository);
      final result = await service.restore(trashedTicket.id);

      expect(result, trashedTicket);
      verifyNever(() => gitProjector.project(any(), any(), any()));
    });
  });

  group('applyFromParsedFields', () {
    test('applies a changed, valid parentId', () async {
      when(
        () => repository.getAllTickets(),
      ).thenAnswer((_) async => [ticket, unrelated]);
      when(
        () => repository.updateTicketParent(ticket.id, unrelated.id),
      ).thenAnswer((_) async {});
      when(
        () => repository.getTicketById(unrelated.id),
      ).thenAnswer((_) async => unrelated);
      when(
        () => repository.getTicketById(ticket.id),
      ).thenAnswer((_) async => reparented);

      final service = TicketParentTrashService(repository);
      final ok = await service.applyFromParsedFields(ticket, {
        'parentId': unrelated.id,
      });

      expect(ok, isTrue);
      verify(
        () => repository.updateTicketParent(ticket.id, unrelated.id),
      ).called(1);
    });

    test('rejects a changed, invalid parentId (self-parent)', () async {
      final service = TicketParentTrashService(repository);
      final ok = await service.applyFromParsedFields(ticket, {
        'parentId': ticket.id,
      });

      expect(ok, isFalse);
      verifyNever(() => repository.updateTicketParent(any(), any()));
    });

    test('an absent parentId key is a no-op', () async {
      final service = TicketParentTrashService(repository);
      final ok = await service.applyFromParsedFields(ticket, {});

      expect(ok, isTrue);
      verifyNever(() => repository.updateTicketParent(any(), any()));
    });

    test('an unchanged parentId value is a no-op', () async {
      final service = TicketParentTrashService(repository);
      final ok = await service.applyFromParsedFields(ticket, {
        'parentId': ticket.parentId,
      });

      expect(ok, isTrue);
      verifyNever(() => repository.updateTicketParent(any(), any()));
    });

    test('a deletedAt transition from null to a timestamp trashes', () async {
      when(
        () => repository.getTicketById(ticket.id),
      ).thenAnswer((_) async => ticket);
      when(() => repository.trashTicket(ticket.id)).thenAnswer((_) async {});

      final service = TicketParentTrashService(repository);
      final ok = await service.applyFromParsedFields(ticket, {
        'deletedAt': DateTime(2026, 1, 2),
      });

      expect(ok, isTrue);
      verify(() => repository.trashTicket(ticket.id)).called(1);
    });

    test('a deletedAt transition from a timestamp to null restores', () async {
      when(
        () => repository.getTicketById(trashedTicket.id),
      ).thenAnswer((_) async => trashedTicket);
      when(
        () => repository.restoreTicket(trashedTicket.id),
      ).thenAnswer((_) async {});

      final service = TicketParentTrashService(repository);
      final ok = await service.applyFromParsedFields(trashedTicket, {
        'deletedAt': null,
      });

      expect(ok, isTrue);
      verify(() => repository.restoreTicket(trashedTicket.id)).called(1);
    });

    test(
      'a changed-but-still-non-null deletedAt (re-trashing with a '
      'different stamp) is a no-op',
      () async {
        final service = TicketParentTrashService(repository);
        final ok = await service.applyFromParsedFields(trashedTicket, {
          'deletedAt': DateTime(2026, 5, 5),
        });

        expect(ok, isTrue);
        verifyNever(() => repository.trashTicket(any()));
        verifyNever(() => repository.restoreTicket(any()));
      },
    );
  });
}
