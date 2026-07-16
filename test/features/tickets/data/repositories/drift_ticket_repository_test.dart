import 'dart:io';

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

  Ticket buildSearchable({
    required String id,
    required String title,
    String? description,
    TicketType type = TicketType.task,
    TicketStatus status = TicketStatus.backlog,
    TicketPriority priority = TicketPriority.none,
  }) {
    final now = DateTime(2026, 1, 1);
    return Ticket(
      id: id,
      ticketId: '',
      type: type,
      title: title,
      description: description,
      status: status,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
  }

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

  test('updateTicketParent changes the stored parent_id column', () async {
    await repository.createTicket(buildTicket(id: '1'));
    await repository.createTicket(buildTicket(id: '2'));
    await repository.updateTicketParent('1', '2');

    final found = await repository.getTicketById('1');
    expect(found!.parentId, '2');
  });

  test('updateTicketParent can clear parentId to null', () async {
    await repository.createTicket(buildTicket(id: '1'));
    await repository.createTicket(
      buildTicket(id: '2', parentId: '1'),
    );
    await repository.updateTicketParent('2', null);

    final found = await repository.getTicketById('2');
    expect(found!.parentId, isNull);
  });

  test('updateTicketParent does not change other fields', () async {
    await repository.createTicket(
      buildTicket(
        id: '1',
        title: 'Unchanged title',
        priority: TicketPriority.high,
      ),
    );
    await repository.createTicket(buildTicket(id: '2'));
    await repository.updateTicketParent('1', '2');

    final found = await repository.getTicketById('1');
    expect(found!.title, 'Unchanged title');
    expect(found.priority, TicketPriority.high);
    expect(found.status, TicketStatus.backlog);
    expect(found.type, TicketType.task);
  });

  test(
    'updateTicketParent sets updatedAt to a timestamp at or after the original',
    () async {
      await repository.createTicket(buildTicket(id: '1'));
      await repository.createTicket(buildTicket(id: '2'));
      final before = (await repository.getTicketById('1'))!.updatedAt;

      await repository.updateTicketParent('1', '2');
      final after = (await repository.getTicketById('1'))!.updatedAt;

      expect(after.isAtSameMomentAs(before) || after.isAfter(before), isTrue);
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

  group('searchTickets', () {
    test(
      'query matches title/description; a title hit ranks ahead of a description-only hit',
      () async {
        await repository.createTicket(
          buildSearchable(
            id: 'desc-hit',
            title: 'Unrelated title',
            description: 'mentions authentication in passing',
          ),
        );
        await repository.createTicket(
          buildSearchable(id: 'title-hit', title: 'Fix authentication bug'),
        );
        await repository.createTicket(
          buildSearchable(id: 'no-match', title: 'Completely different'),
        );

        final results = await repository.searchTickets(
          query: 'authentication',
        );

        expect(results.map((t) => t.id), ['title-hit', 'desc-hit']);
      },
    );

    test('status/type/priority filters return only exact matches', () async {
      await repository.createTicket(
        buildSearchable(
          id: 'match',
          title: 'A',
          type: TicketType.story,
          status: TicketStatus.inProgress,
          priority: TicketPriority.high,
        ),
      );
      await repository.createTicket(
        buildSearchable(
          id: 'wrong-type',
          title: 'B',
          type: TicketType.task,
          status: TicketStatus.inProgress,
          priority: TicketPriority.high,
        ),
      );

      final results = await repository.searchTickets(
        type: TicketType.story,
        status: TicketStatus.inProgress,
        priority: TicketPriority.high,
      );

      expect(results.map((t) => t.id), ['match']);
    });

    test('query and a structured filter combine (ANDed)', () async {
      await repository.createTicket(
        buildSearchable(
          id: 'match',
          title: 'Fix login bug',
          type: TicketType.task,
        ),
      );
      await repository.createTicket(
        buildSearchable(
          id: 'wrong-type',
          title: 'Fix login bug',
          type: TicketType.story,
        ),
      );
      await repository.createTicket(
        buildSearchable(id: 'wrong-query', title: 'Unrelated', type: TicketType.task),
      );

      final results = await repository.searchTickets(
        query: 'login',
        type: TicketType.task,
      );

      expect(results.map((t) => t.id), ['match']);
    });

    test(
      'every parameter null/omitted returns everything, parity with getAllTickets',
      () async {
        await repository.createTicket(buildSearchable(id: '1', title: 'A'));
        await repository.createTicket(buildSearchable(id: '2', title: 'B'));

        final all = await repository.getAllTickets();
        final searched = await repository.searchTickets();

        expect(
          searched.map((t) => t.id).toSet(),
          all.map((t) => t.id).toSet(),
        );
      },
    );

    test('a query containing FTS5-special characters does not throw', () async {
      await repository.createTicket(
        buildSearchable(id: '1', title: 'Fix drift-web init bug'),
      );

      await expectLater(
        () => repository.searchTickets(query: '-drift-web "quoted"'),
        returnsNormally,
      );
    });
  });

  group('schema migration (v1 -> v2)', () {
    test(
      'onUpgrade backfills existing rows into the FTS5 search index',
      () async {
        // In-memory SQLite doesn't persist across separate connections, so
        // this test needs a real file to genuinely close and reopen
        // against — exactly the scenario onUpgrade exists for (an
        // existing local database on disk).
        final tempDir = Directory.systemTemp.createTempSync(
          'aion_migration_test',
        );
        final dbFile = File('${tempDir.path}/test.sqlite');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // A fresh AppDatabase always runs onCreate at the *current*
        // schemaVersion (2), which already includes the search
        // infrastructure — so the v1 shape has to be built by hand:
        // strip back down to just the bare tables, insert data, then
        // stamp user_version back to 1.
        final v1Db = AppDatabase(NativeDatabase(dbFile));
        await v1Db.customStatement('DROP TABLE IF EXISTS tickets_fts;');
        await v1Db.customStatement('DROP TRIGGER IF EXISTS tickets_fts_ai;');
        await v1Db.customStatement('DROP TRIGGER IF EXISTS tickets_fts_ad;');
        await v1Db.customStatement('DROP TRIGGER IF EXISTS tickets_fts_au;');
        await v1Db.customStatement('DROP INDEX IF EXISTS idx_tickets_status;');
        await v1Db.customStatement('DROP INDEX IF EXISTS idx_tickets_type;');
        await v1Db.customStatement(
          'DROP INDEX IF EXISTS idx_tickets_priority;',
        );

        final preMigrationRepo = DriftTicketRepository(v1Db);
        await preMigrationRepo.createTicket(
          buildSearchable(id: 'pre-existing', title: 'Fix authentication bug'),
        );
        await v1Db.customStatement('PRAGMA user_version = 1;');
        await v1Db.close();

        // Reopen against the same file at the current schemaVersion (2).
        // Drift reads user_version=1, sees schemaVersion=2, and runs
        // onUpgrade automatically.
        final v2Db = AppDatabase(NativeDatabase(dbFile));
        final upgradedRepo = DriftTicketRepository(v2Db);

        final results = await upgradedRepo.searchTickets(
          query: 'authentication',
        );

        expect(results.map((t) => t.id), ['pre-existing']);
        await v2Db.close();
      },
    );
  });
}
