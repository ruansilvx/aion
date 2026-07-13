import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/repositories/drift_comment_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_link_repository.dart';
import 'package:aion/features/tickets/data/repositories/drift_ticket_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/exceptions/ticket_has_children_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DriftTicketRepository repository;

  Ticket buildTicket({
    String id = '1',
    String title = 'Test ticket',
    TicketPriority priority = TicketPriority.none,
    int? estimate,
    int? timeSpent,
    String? parentId,
  }) {
    final now = DateTime(2026, 1, 1);
    return Ticket(
      id: id,
      ticketId: '',
      type: TicketType.task,
      title: title,
      status: TicketStatus.backlog,
      priority: priority,
      estimate: estimate,
      timeSpent: timeSpent,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftTicketRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('createTicket then getAllTickets returns the created ticket', () async {
    await repository.createTicket(buildTicket());
    final tickets = await repository.getAllTickets();

    expect(tickets, hasLength(1));
    expect(tickets.first.title, 'Test ticket');
  });

  test('getTicketById returns correct ticket when found', () async {
    await repository.createTicket(buildTicket(id: 'abc'));
    final found = await repository.getTicketById('abc');

    expect(found, isNotNull);
    expect(found!.id, 'abc');
  });

  test('getTicketById returns null when not found', () async {
    final found = await repository.getTicketById('missing');
    expect(found, isNull);
  });

  test(
    'enum round-trip: type, status, and priority survive write/read',
    () async {
      final now = DateTime(2026, 1, 1);
      final ticket = Ticket(
        id: '1',
        ticketId: '',
        type: TicketType.epic,
        title: 'Epic ticket',
        status: TicketStatus.inReview,
        priority: TicketPriority.critical,
        createdAt: now,
        updatedAt: now,
      );

      await repository.createTicket(ticket);
      final tickets = await repository.getAllTickets();

      expect(tickets.first.type, TicketType.epic);
      expect(tickets.first.status, TicketStatus.inReview);
      expect(tickets.first.priority, TicketPriority.critical);
    },
  );

  test('priority defaults to TicketPriority.none when not supplied', () async {
    await repository.createTicket(buildTicket());
    final tickets = await repository.getAllTickets();

    expect(tickets.first.priority, TicketPriority.none);
  });

  test('estimate and time_spent nullable fields survive write/read', () async {
    await repository.createTicket(
      buildTicket(id: '1', estimate: null, timeSpent: null),
    );
    await repository.createTicket(
      buildTicket(id: '2', estimate: 30, timeSpent: 15),
    );

    final tickets = await repository.getAllTickets();
    final withNulls = tickets.firstWhere((t) => t.id == '1');
    final withValues = tickets.firstWhere((t) => t.id == '2');

    expect(withNulls.estimate, isNull);
    expect(withNulls.timeSpent, isNull);
    expect(withValues.estimate, 30);
    expect(withValues.timeSpent, 15);
  });

  test('first ticket generated ticketId is "AIO-1" (default prefix)', () async {
    await repository.createTicket(buildTicket());
    final tickets = await repository.getAllTickets();

    expect(tickets.first.ticketId, 'AIO-1');
  });

  test(
    'second ticket generated ticketId is "AIO-2" (sequence increments)',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      await repository.createTicket(buildTicket(id: '2'));

      final tickets = await repository.getAllTickets();
      final ticketIds = tickets.map((t) => t.ticketId).toSet();

      expect(ticketIds, containsAll(['AIO-1', 'AIO-2']));
    },
  );

  test('ticketId field survives entity mapping round-trip', () async {
    await repository.createTicket(buildTicket(id: 'xyz'));
    final found = await repository.getTicketById('xyz');

    expect(found!.ticketId, 'AIO-1');
  });

  test('updateTicketStatus changes the stored status column', () async {
    await repository.createTicket(buildTicket(id: '1'));
    await repository.updateTicketStatus('1', TicketStatus.done);

    final found = await repository.getTicketById('1');
    expect(found!.status, TicketStatus.done);
  });

  test('updateTicketStatus does not change other fields', () async {
    await repository.createTicket(
      buildTicket(
        id: '1',
        title: 'Unchanged title',
        priority: TicketPriority.high,
      ),
    );
    await repository.updateTicketStatus('1', TicketStatus.done);

    final found = await repository.getTicketById('1');
    expect(found!.title, 'Unchanged title');
    expect(found.priority, TicketPriority.high);
    expect(found.type, TicketType.task);
    expect(found.parentId, isNull);
  });

  test(
    'updateTicketStatus sets updatedAt to a timestamp at or after the original',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      final before = (await repository.getTicketById('1'))!.updatedAt;

      await repository.updateTicketStatus('1', TicketStatus.done);
      final after = (await repository.getTicketById('1'))!.updatedAt;

      expect(after.isAtSameMomentAs(before) || after.isAfter(before), isTrue);
    },
  );

  test(
    'updateTicket persists title, description, priority, type, estimate, and timeSpent',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      final original = (await repository.getTicketById('1'))!;

      await repository.updateTicket(
        original.copyWith(
          title: 'Updated title',
          description: () => 'Updated description',
          priority: TicketPriority.high,
          type: TicketType.story,
          estimate: () => 90,
          timeSpent: () => 45,
        ),
      );

      final found = await repository.getTicketById('1');
      expect(found!.title, 'Updated title');
      expect(found.description, 'Updated description');
      expect(found.priority, TicketPriority.high);
      expect(found.type, TicketType.story);
      expect(found.estimate, 90);
      expect(found.timeSpent, 45);
    },
  );

  test(
    'updateTicket leaves status, parentId, embedding, and createdAt untouched',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      final original = (await repository.getTicketById('1'))!;

      await repository.updateTicket(original.copyWith(title: 'Changed title'));

      final found = await repository.getTicketById('1');
      expect(found!.status, original.status);
      expect(found.parentId, original.parentId);
      expect(found.embedding, original.embedding);
      expect(found.createdAt, original.createdAt);
    },
  );

  test(
    'updateTicket sets updatedAt to a timestamp at or after the original',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      final before = (await repository.getTicketById('1'))!.updatedAt;

      await repository.updateTicket(
        (await repository.getTicketById('1'))!.copyWith(title: 'New'),
      );
      final after = (await repository.getTicketById('1'))!.updatedAt;

      expect(after.isAtSameMomentAs(before) || after.isAfter(before), isTrue);
    },
  );

  test(
    'updateTicket can explicitly clear estimate, timeSpent, and description to null',
    () async {
      await repository.createTicket(
        buildTicket(id: '1', estimate: 60, timeSpent: 30),
      );
      final original = (await repository.getTicketById('1'))!;

      await repository.updateTicket(
        original.copyWith(
          description: () => null,
          estimate: () => null,
          timeSpent: () => null,
        ),
      );

      final found = await repository.getTicketById('1');
      expect(found!.description, isNull);
      expect(found.estimate, isNull);
      expect(found.timeSpent, isNull);
    },
  );

  group('deleteTicket', () {
    test(
      'deletes a childless ticket, its comments, and its links (as source and target)',
      () async {
        await repository.createTicket(buildTicket(id: '1'));
        await repository.createTicket(buildTicket(id: 'other'));

        final commentRepository = DriftCommentRepository(database);
        await commentRepository.addComment(
          TicketComment(
            id: '',
            ticketId: '1',
            content: 'A comment',
            authorType: CommentAuthorType.human,
            createdAt: DateTime(2026, 1, 1),
          ),
        );

        final linkRepository = DriftTicketLinkRepository(database);
        await linkRepository.createLink(
          sourceTicketId: '1',
          targetTicketId: 'other',
          linkType: TicketLinkType.relatesTo,
        );
        await linkRepository.createLink(
          sourceTicketId: 'other',
          targetTicketId: '1',
          linkType: TicketLinkType.blocks,
        );

        await repository.deleteTicket('1');

        expect(await repository.getTicketById('1'), isNull);
        expect(await commentRepository.getCommentsForTicket('1'), isEmpty);
        expect(await linkRepository.getLinksForTicket('1'), isEmpty);
        // The unrelated ticket and its own data are untouched.
        expect(await repository.getTicketById('other'), isNotNull);
      },
    );

    test(
      'throws TicketHasChildrenException and deletes nothing when the ticket has children',
      () async {
        await repository.createTicket(buildTicket(id: 'parent'));
        await repository.createTicket(
          buildTicket(id: 'child', parentId: 'parent'),
        );

        await expectLater(
          () => repository.deleteTicket('parent'),
          throwsA(
            isA<TicketHasChildrenException>().having(
              (e) => e.childCount,
              'childCount',
              1,
            ),
          ),
        );

        expect(await repository.getTicketById('parent'), isNotNull);
        expect(await repository.getTicketById('child'), isNotNull);
      },
    );

    test('throws StateError when the ticket does not exist', () async {
      await expectLater(
        () => repository.deleteTicket('missing'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
