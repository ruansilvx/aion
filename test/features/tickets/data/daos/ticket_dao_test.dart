// test/features/tickets/data/daos/ticket_dao_test.dart — TicketDao.searchTickets pagination tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/daos/ticket_dao.dart';

/// Dummy project [AppDatabase] now requires per-project addressing —
/// unused here since every test passes an explicit in-memory executor.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

/// Direct [TicketDao] pagination tests against a real in-memory drift
/// instance — per `flutter-conventions.md`'s stated exception, this is
/// genuinely persistence behavior (the raw FTS `customSelect` branch's
/// string-concatenated `LIMIT ?/OFFSET ?` is exactly the kind of thing a
/// mock can't catch a mistake in), so it isn't mocked like most repository
/// tests. `DriftTicketRepository`'s own tests already cover the `limit + 1`
/// -> `hasMore` trim logic end to end; these tests isolate the DAO's own
/// `limit`/`offset` handling on both query branches.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TicketDao dao;

  Future<void> insertTicket({
    required String id,
    required String title,
    required int createdAtMs,
  }) async {
    await dao.insertTicket(
      TicketsTableCompanion.insert(
        id: id,
        ticketId: '',
        type: 'task',
        title: title,
        status: 'backlog',
        createdAt: createdAtMs,
        updatedAt: createdAtMs,
      ),
      'AIO',
    );
  }

  setUp(() {
    database = AppDatabase(_testProject, NativeDatabase.memory());
    dao = database.ticketDao;
  });

  tearDown(() async {
    await database.close();
  });

  group('typed-select branch (no query)', () {
    test('limit restricts the number of rows returned', () async {
      for (var i = 0; i < 5; i++) {
        await insertTicket(id: 'p$i', title: 'Ticket $i', createdAtMs: i);
      }

      final rows = await dao.searchTickets(limit: 2);

      expect(rows.length, 2);
    });

    test('offset skips the first N rows, ordered by createdAt desc', () async {
      for (var i = 0; i < 5; i++) {
        await insertTicket(id: 'p$i', title: 'Ticket $i', createdAtMs: i);
      }

      final firstPage = await dao.searchTickets(limit: 2, offset: 0);
      final secondPage = await dao.searchTickets(limit: 2, offset: 2);

      // Most recently created (highest createdAt) first: p4, p3, p2, p1, p0.
      expect(firstPage.map((t) => t.id), ['p4', 'p3']);
      expect(secondPage.map((t) => t.id), ['p2', 'p1']);
    });

    test(
      'requesting more than exists returns only what exists, no error',
      () async {
        for (var i = 0; i < 3; i++) {
          await insertTicket(id: 'p$i', title: 'Ticket $i', createdAtMs: i);
        }

        final rows = await dao.searchTickets(limit: 3, offset: 0);
        final overRequested = await dao.searchTickets(limit: 4, offset: 0);

        expect(rows.length, 3);
        expect(overRequested.length, 3);
      },
    );
  });

  group('FTS branch (query set)', () {
    test('limit and offset apply across pages with no duplicates', () async {
      for (var i = 0; i < 5; i++) {
        await insertTicket(
          id: 'p$i',
          title: 'Fix authentication bug $i',
          createdAtMs: i,
        );
      }

      final firstPage = await dao.searchTickets(
        query: 'authentication',
        limit: 2,
        offset: 0,
      );
      final secondPage = await dao.searchTickets(
        query: 'authentication',
        limit: 2,
        offset: 2,
      );

      expect(firstPage.length, 2);
      expect(secondPage.length, 2);
      expect(
        firstPage
            .map((t) => t.id)
            .toSet()
            .intersection(secondPage.map((t) => t.id).toSet()),
        isEmpty,
      );
    });

    test(
      'requesting more than exists returns only what matches, no error',
      () async {
        for (var i = 0; i < 3; i++) {
          await insertTicket(
            id: 'p$i',
            title: 'Fix authentication bug $i',
            createdAtMs: i,
          );
        }

        final rows = await dao.searchTickets(
          query: 'authentication',
          limit: 4,
          offset: 0,
        );

        expect(rows.length, 3);
      },
    );
  });
}
