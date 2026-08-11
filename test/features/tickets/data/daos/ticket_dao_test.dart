// test/features/tickets/data/daos/ticket_dao_test.dart — TicketDao.searchTickets
// pagination and insertTicketPreservingId tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drift/drift.dart' show Value;

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/daos/ticket_dao.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// The pre-existing default ordering (`createdAt` descending) — passed
/// explicitly to every `searchTickets` call in this file that isn't
/// itself exercising the new sort-control behavior (see
/// `aion-arch/changes/ticket-sort-control-and-board-as-default-view`),
/// so those calls keep exercising exactly the ordering they did before
/// `sort` became a required parameter.
const _defaultSort = TicketListSort(
  field: TicketSortField.createdAt,
  direction: TicketSortDirection.descending,
);

/// The pre-existing implicit relevance ordering used whenever a search
/// query was active, before `sort` became a required parameter.
const _relevanceSort = TicketListSort(
  field: TicketSortField.relevance,
  direction: TicketSortDirection.descending,
);

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

  Future<String> insertTicketReturningId({
    required String id,
    required String title,
  }) {
    return dao.insertTicket(
      TicketsTableCompanion.insert(
        id: id,
        ticketId: '',
        type: 'task',
        title: title,
        status: 'backlog',
        createdAt: 0,
        updatedAt: 0,
      ),
      'AIO',
    );
  }

  Future<void> insertPreservingId({
    required String id,
    required String ticketId,
  }) async {
    await dao.insertTicketPreservingId(
      TicketsTableCompanion.insert(
        id: id,
        ticketId: ticketId,
        type: 'task',
        title: id,
        status: 'backlog',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  }

  Future<void> insertDoc({
    required String id,
    required TicketType type,
    String? parentId,
    bool deleted = false,
  }) async {
    await dao.insertTicket(
      TicketsTableCompanion.insert(
        id: id,
        ticketId: '',
        type: type.name,
        title: id,
        status: 'backlog',
        parentId: Value(parentId),
        deletedAt: Value(deleted ? 1 : null),
        createdAt: 0,
        updatedAt: 0,
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

      final rows = await dao.searchTickets(sort: _defaultSort, limit: 2);

      expect(rows.length, 2);
    });

    test('offset skips the first N rows, ordered by createdAt desc', () async {
      for (var i = 0; i < 5; i++) {
        await insertTicket(id: 'p$i', title: 'Ticket $i', createdAtMs: i);
      }

      final firstPage = await dao.searchTickets(
        sort: _defaultSort,
        limit: 2,
        offset: 0,
      );
      final secondPage = await dao.searchTickets(
        sort: _defaultSort,
        limit: 2,
        offset: 2,
      );

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

        final rows = await dao.searchTickets(
          sort: _defaultSort,
          limit: 3,
          offset: 0,
        );
        final overRequested = await dao.searchTickets(
          sort: _defaultSort,
          limit: 4,
          offset: 0,
        );

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
        sort: _relevanceSort,
        limit: 2,
        offset: 0,
      );
      final secondPage = await dao.searchTickets(
        query: 'authentication',
        sort: _relevanceSort,
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
          sort: _relevanceSort,
          limit: 4,
          offset: 0,
        );

        expect(rows.length, 3);
      },
    );
  });

  group('searchTickets filtering (status/type/priority sets)', () {
    Future<void> insertFiltered({
      required String id,
      required String title,
      required TicketStatus status,
      required TicketType type,
      required TicketPriority priority,
      int createdAtMs = 0,
    }) async {
      await dao.insertTicket(
        TicketsTableCompanion.insert(
          id: id,
          ticketId: '',
          type: type.name,
          title: title,
          status: status.name,
          priority: Value(priority.name),
          createdAt: createdAtMs,
          updatedAt: createdAtMs,
        ),
        'AIO',
      );
    }

    group('no-query (typed-select) path', () {
      test(
        'empty sets apply no constraint, same as the old null behavior',
        () async {
          await insertFiltered(
            id: 'a',
            title: 'A',
            status: TicketStatus.backlog,
            type: TicketType.task,
            priority: TicketPriority.none,
          );
          await insertFiltered(
            id: 'b',
            title: 'B',
            status: TicketStatus.todo,
            type: TicketType.bug,
            priority: TicketPriority.high,
            createdAtMs: 1,
          );

          final rows = await dao.searchTickets(sort: _defaultSort, limit: 10);

          expect(rows.map((t) => t.id).toSet(), {'a', 'b'});
        },
      );

      test('a single-value set matches only that value, same as the old '
          'single-value behavior', () async {
        await insertFiltered(
          id: 'a',
          title: 'A',
          status: TicketStatus.backlog,
          type: TicketType.task,
          priority: TicketPriority.none,
        );
        await insertFiltered(
          id: 'b',
          title: 'B',
          status: TicketStatus.todo,
          type: TicketType.task,
          priority: TicketPriority.none,
          createdAtMs: 1,
        );

        final rows = await dao.searchTickets(
          statuses: {TicketStatus.todo},
          sort: _defaultSort,
          limit: 10,
        );

        expect(rows.map((t) => t.id), ['b']);
      });

      test('a multi-value set OR-matches within the field', () async {
        await insertFiltered(
          id: 'a',
          title: 'A',
          status: TicketStatus.backlog,
          type: TicketType.task,
          priority: TicketPriority.none,
        );
        await insertFiltered(
          id: 'b',
          title: 'B',
          status: TicketStatus.todo,
          type: TicketType.task,
          priority: TicketPriority.none,
          createdAtMs: 1,
        );
        await insertFiltered(
          id: 'c',
          title: 'C',
          status: TicketStatus.done,
          type: TicketType.task,
          priority: TicketPriority.none,
          createdAtMs: 2,
        );

        final rows = await dao.searchTickets(
          statuses: {TicketStatus.backlog, TicketStatus.todo},
          sort: _defaultSort,
          limit: 10,
        );

        expect(rows.map((t) => t.id).toSet(), {'a', 'b'});
      });

      test('sets across multiple fields AND together', () async {
        await insertFiltered(
          id: 'a',
          title: 'A',
          status: TicketStatus.todo,
          type: TicketType.task,
          priority: TicketPriority.high,
        );
        await insertFiltered(
          id: 'b',
          title: 'B',
          status: TicketStatus.todo,
          type: TicketType.bug,
          priority: TicketPriority.high,
          createdAtMs: 1,
        );
        await insertFiltered(
          id: 'c',
          title: 'C',
          status: TicketStatus.done,
          type: TicketType.task,
          priority: TicketPriority.high,
          createdAtMs: 2,
        );

        final rows = await dao.searchTickets(
          statuses: {TicketStatus.todo},
          types: {TicketType.task},
          sort: _defaultSort,
          limit: 10,
        );

        expect(rows.map((t) => t.id), ['a']);
      });
    });

    group('FTS (query set) path', () {
      test(
        'empty sets apply no constraint, same as the old null behavior',
        () async {
          await insertFiltered(
            id: 'a',
            title: 'Fix bug alpha',
            status: TicketStatus.backlog,
            type: TicketType.task,
            priority: TicketPriority.none,
          );
          await insertFiltered(
            id: 'b',
            title: 'Fix bug beta',
            status: TicketStatus.todo,
            type: TicketType.bug,
            priority: TicketPriority.high,
            createdAtMs: 1,
          );

          final rows = await dao.searchTickets(
            query: 'fix',
            sort: _relevanceSort,
            limit: 10,
          );

          expect(rows.map((t) => t.id).toSet(), {'a', 'b'});
        },
      );

      test('a single-value set matches only that value, same as the old '
          'single-value behavior', () async {
        await insertFiltered(
          id: 'a',
          title: 'Fix bug alpha',
          status: TicketStatus.backlog,
          type: TicketType.task,
          priority: TicketPriority.none,
        );
        await insertFiltered(
          id: 'b',
          title: 'Fix bug beta',
          status: TicketStatus.todo,
          type: TicketType.task,
          priority: TicketPriority.none,
          createdAtMs: 1,
        );

        final rows = await dao.searchTickets(
          query: 'fix',
          statuses: {TicketStatus.todo},
          sort: _relevanceSort,
          limit: 10,
        );

        expect(rows.map((t) => t.id), ['b']);
      });

      test('a multi-value set OR-matches within the field', () async {
        await insertFiltered(
          id: 'a',
          title: 'Fix bug alpha',
          status: TicketStatus.backlog,
          type: TicketType.task,
          priority: TicketPriority.none,
        );
        await insertFiltered(
          id: 'b',
          title: 'Fix bug beta',
          status: TicketStatus.todo,
          type: TicketType.task,
          priority: TicketPriority.none,
          createdAtMs: 1,
        );
        await insertFiltered(
          id: 'c',
          title: 'Fix bug gamma',
          status: TicketStatus.done,
          type: TicketType.task,
          priority: TicketPriority.none,
          createdAtMs: 2,
        );

        final rows = await dao.searchTickets(
          query: 'fix',
          statuses: {TicketStatus.backlog, TicketStatus.todo},
          sort: _relevanceSort,
          limit: 10,
        );

        expect(rows.map((t) => t.id).toSet(), {'a', 'b'});
      });

      test('sets across multiple fields AND together', () async {
        await insertFiltered(
          id: 'a',
          title: 'Fix bug alpha',
          status: TicketStatus.todo,
          type: TicketType.task,
          priority: TicketPriority.high,
        );
        await insertFiltered(
          id: 'b',
          title: 'Fix bug beta',
          status: TicketStatus.todo,
          type: TicketType.bug,
          priority: TicketPriority.high,
          createdAtMs: 1,
        );
        await insertFiltered(
          id: 'c',
          title: 'Fix bug gamma',
          status: TicketStatus.done,
          type: TicketType.task,
          priority: TicketPriority.high,
          createdAtMs: 2,
        );

        final rows = await dao.searchTickets(
          query: 'fix',
          statuses: {TicketStatus.todo},
          types: {TicketType.task},
          sort: _relevanceSort,
          limit: 10,
        );

        expect(rows.map((t) => t.id), ['a']);
      });
    });
  });

  group(
    'searchTickets sort (ticket-sort-control-and-board-as-default-view)',
    () {
      /// Inserts three tickets spanning every field [TicketDao.searchTickets]
      /// can sort by, each with a distinct value so sorted order is
      /// unambiguous: `low` is oldest/least-urgent/first-in-declaration-order
      /// on every enum field and least-recently-updated; `critical` is the
      /// opposite on every field. Every title contains "Fix bug" so an FTS
      /// query for `'fix'` matches all three, letting the same fixture cover
      /// both the no-query and FTS branches.
      Future<void> insertSortFixtures() async {
        await dao.insertTicket(
          TicketsTableCompanion.insert(
            id: 'low',
            ticketId: '',
            type: TicketType.epic.name,
            title: 'Fix bug low',
            status: TicketStatus.backlog.name,
            priority: const Value('low'),
            createdAt: 0,
            updatedAt: 2,
          ),
          'AIO',
        );
        await dao.insertTicket(
          TicketsTableCompanion.insert(
            id: 'medium',
            ticketId: '',
            type: TicketType.story.name,
            title: 'Fix bug medium',
            status: TicketStatus.inProgress.name,
            priority: const Value('medium'),
            createdAt: 1,
            updatedAt: 1,
          ),
          'AIO',
        );
        await dao.insertTicket(
          TicketsTableCompanion.insert(
            id: 'critical',
            ticketId: '',
            type: TicketType.task.name,
            title: 'Fix bug critical',
            status: TicketStatus.done.name,
            priority: const Value('critical'),
            createdAt: 2,
            updatedAt: 0,
          ),
          'AIO',
        );
      }

      group('no-query (typed-select) path', () {
        test('priority ascending orders by declaration order', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.priority,
              direction: TicketSortDirection.ascending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['critical', 'medium', 'low']);
        });

        test('priority descending reverses declaration order', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.priority,
              direction: TicketSortDirection.descending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['low', 'medium', 'critical']);
        });

        test('status ascending orders by declaration order', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.status,
              direction: TicketSortDirection.ascending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['low', 'medium', 'critical']);
        });

        test('status descending reverses declaration order', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.status,
              direction: TicketSortDirection.descending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['critical', 'medium', 'low']);
        });

        test('type ascending orders by declaration order', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.type,
              direction: TicketSortDirection.ascending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['low', 'medium', 'critical']);
        });

        test('type descending reverses declaration order', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.type,
              direction: TicketSortDirection.descending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['critical', 'medium', 'low']);
        });

        test('createdAt ascending orders oldest first', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.createdAt,
              direction: TicketSortDirection.ascending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['low', 'medium', 'critical']);
        });

        test('createdAt descending orders newest first', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.createdAt,
              direction: TicketSortDirection.descending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['critical', 'medium', 'low']);
        });

        test(
          'updatedAt ascending orders least-recently-touched first',
          () async {
            await insertSortFixtures();

            final rows = await dao.searchTickets(
              sort: const TicketListSort(
                field: TicketSortField.updatedAt,
                direction: TicketSortDirection.ascending,
              ),
              limit: 10,
            );

            expect(rows.map((t) => t.id), ['critical', 'medium', 'low']);
          },
        );

        test(
          'updatedAt descending orders most-recently-touched first',
          () async {
            await insertSortFixtures();

            final rows = await dao.searchTickets(
              sort: const TicketListSort(
                field: TicketSortField.updatedAt,
                direction: TicketSortDirection.descending,
              ),
              limit: 10,
            );

            expect(rows.map((t) => t.id), ['low', 'medium', 'critical']);
          },
        );

        test('relevance falls back to createdAt descending — no query to '
            'score against', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.relevance,
              direction: TicketSortDirection.descending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['critical', 'medium', 'low']);
        });

        test('the createdAt DESC tiebreaker breaks ties for a non-createdAt '
            'field', () async {
          // Both share priority: high — only createdAt (the tiebreaker)
          // distinguishes them.
          await dao.insertTicket(
            TicketsTableCompanion.insert(
              id: 'older',
              ticketId: '',
              type: 'task',
              title: 'Older',
              status: 'backlog',
              priority: const Value('high'),
              createdAt: 5,
              updatedAt: 5,
            ),
            'AIO',
          );
          await dao.insertTicket(
            TicketsTableCompanion.insert(
              id: 'newer',
              ticketId: '',
              type: 'task',
              title: 'Newer',
              status: 'backlog',
              priority: const Value('high'),
              createdAt: 15,
              updatedAt: 15,
            ),
            'AIO',
          );

          final rows = await dao.searchTickets(
            sort: const TicketListSort(
              field: TicketSortField.priority,
              direction: TicketSortDirection.ascending,
            ),
            limit: 10,
          );

          // Newest (highest createdAt) wins the tiebreak, regardless of
          // the primary field's own direction.
          expect(rows.map((t) => t.id), ['newer', 'older']);
        });
      });

      group('FTS (query set) path', () {
        test('priority ascending orders by declaration order', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            query: 'fix',
            sort: const TicketListSort(
              field: TicketSortField.priority,
              direction: TicketSortDirection.ascending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['critical', 'medium', 'low']);
        });

        test('createdAt descending orders newest first', () async {
          await insertSortFixtures();

          final rows = await dao.searchTickets(
            query: 'fix',
            sort: const TicketListSort(
              field: TicketSortField.createdAt,
              direction: TicketSortDirection.descending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['critical', 'medium', 'low']);
        });

        test('relevance keeps bm25 ordering — a title hit ranks ahead of a '
            'description-only hit', () async {
          await dao.insertTicket(
            TicketsTableCompanion.insert(
              id: 'desc-hit',
              ticketId: '',
              type: 'task',
              title: 'Unrelated title',
              description: const Value('mentions authentication in passing'),
              status: 'backlog',
              createdAt: 0,
              updatedAt: 0,
            ),
            'AIO',
          );
          await dao.insertTicket(
            TicketsTableCompanion.insert(
              id: 'title-hit',
              ticketId: '',
              type: 'task',
              title: 'Fix authentication bug',
              status: 'backlog',
              createdAt: 1,
              updatedAt: 1,
            ),
            'AIO',
          );

          final rows = await dao.searchTickets(
            query: 'authentication',
            sort: const TicketListSort(
              field: TicketSortField.relevance,
              direction: TicketSortDirection.descending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), ['title-hit', 'desc-hit']);
        });

        test('sorting by a non-relevance field drops bm25 ordering while the '
            'MATCH filter still applies', () async {
          // A worse text match (description-only) but a higher priority
          // — priority ordering should win over match quality once a
          // non-relevance sort is requested.
          await dao.insertTicket(
            TicketsTableCompanion.insert(
              id: 'better-match-lower-priority',
              ticketId: '',
              type: 'task',
              title: 'Fix authentication bug',
              status: 'backlog',
              priority: const Value('low'),
              createdAt: 0,
              updatedAt: 0,
            ),
            'AIO',
          );
          await dao.insertTicket(
            TicketsTableCompanion.insert(
              id: 'worse-match-higher-priority',
              ticketId: '',
              type: 'task',
              title: 'Unrelated title',
              description: const Value('mentions authentication in passing'),
              status: 'backlog',
              priority: const Value('critical'),
              createdAt: 1,
              updatedAt: 1,
            ),
            'AIO',
          );

          final rows = await dao.searchTickets(
            query: 'authentication',
            sort: const TicketListSort(
              field: TicketSortField.priority,
              direction: TicketSortDirection.ascending,
            ),
            limit: 10,
          );

          expect(rows.map((t) => t.id), [
            'worse-match-higher-priority',
            'better-match-lower-priority',
          ]);
        });
      });
    },
  );

  group('getTicketsByParent', () {
    test(
      'returns root-level docs of the given types when parentId is null',
      () async {
        await insertDoc(id: 'root-page', type: TicketType.page);
        await insertDoc(id: 'root-resource', type: TicketType.resource);
        await insertDoc(id: 'root-task', type: TicketType.task);
        await insertDoc(
          id: 'nested-page',
          type: TicketType.page,
          parentId: 'root-page',
        );

        final rows = await dao.getTicketsByParent(
          null,
          types: const [TicketType.page, TicketType.resource],
        );

        expect(rows.map((t) => t.id).toSet(), {'root-page', 'root-resource'});
      },
    );

    test('returns a page\'s direct children of the given types', () async {
      await insertDoc(id: 'parent-page', type: TicketType.page);
      await insertDoc(
        id: 'child-page',
        type: TicketType.page,
        parentId: 'parent-page',
      );
      await insertDoc(
        id: 'child-resource',
        type: TicketType.resource,
        parentId: 'parent-page',
      );
      await insertDoc(
        id: 'grandchild',
        type: TicketType.page,
        parentId: 'child-page',
      );

      final rows = await dao.getTicketsByParent(
        'parent-page',
        types: const [TicketType.page, TicketType.resource],
      );

      expect(rows.map((t) => t.id).toSet(), {'child-page', 'child-resource'});
    });

    test('excludes soft-deleted tickets', () async {
      await insertDoc(id: 'live', type: TicketType.page);
      await insertDoc(id: 'trashed', type: TicketType.page, deleted: true);

      final rows = await dao.getTicketsByParent(
        null,
        types: const [TicketType.page],
      );

      expect(rows.map((t) => t.id), ['live']);
    });
  });

  group('getAllTicketsByType', () {
    test(
      'returns every live ticket of the given types regardless of nesting',
      () async {
        await insertDoc(id: 'root-page', type: TicketType.page);
        await insertDoc(
          id: 'nested-page',
          type: TicketType.page,
          parentId: 'root-page',
        );
        await insertDoc(
          id: 'nested-resource',
          type: TicketType.resource,
          parentId: 'nested-page',
        );
        await insertDoc(id: 'unrelated-task', type: TicketType.task);

        final rows = await dao.getAllTicketsByType(const [
          TicketType.page,
          TicketType.resource,
        ]);

        expect(rows.map((t) => t.id).toSet(), {
          'root-page',
          'nested-page',
          'nested-resource',
        });
      },
    );

    test('excludes soft-deleted tickets', () async {
      await insertDoc(id: 'live', type: TicketType.resource);
      await insertDoc(id: 'trashed', type: TicketType.resource, deleted: true);

      final rows = await dao.getAllTicketsByType(const [TicketType.resource]);

      expect(rows.map((t) => t.id), ['live']);
    });
  });

  group('insertTicketPreservingId', () {
    test(
      'preserves the given ticketId verbatim, not sequence-generated',
      () async {
        await insertPreservingId(id: 'imported-1', ticketId: 'AIO-99');

        final row = await dao.getTicketById('imported-1');

        expect(row?.ticketId, 'AIO-99');
      },
    );

    test('advances the sequence so a later insertTicket never re-issues an '
        'already-imported number', () async {
      await insertPreservingId(id: 'imported-1', ticketId: 'AIO-5');

      final generated = await insertTicketReturningId(
        id: 'created-1',
        title: 'Created after import',
      );

      expect(int.parse(generated.split('-').last), greaterThanOrEqualTo(6));
    });

    test('a non-numeric suffix still inserts successfully and leaves the '
        'sequence unchanged', () async {
      await insertPreservingId(id: 'imported-1', ticketId: 'AIO-abc');

      final row = await dao.getTicketById('imported-1');
      final generated = await insertTicketReturningId(
        id: 'created-1',
        title: 'Created after import',
      );

      expect(row?.ticketId, 'AIO-abc');
      expect(generated, 'AIO-1');
    });
  });

  group('updateStatusByIds', () {
    test(
      'writes the given status to every id in the list and bumps updated_at',
      () async {
        await insertTicket(id: 'a', title: 'A', createdAtMs: 0);
        await insertTicket(id: 'b', title: 'B', createdAtMs: 0);

        await dao.updateStatusByIds(['a', 'b'], TicketStatus.inProgress, 999);

        final a = await dao.getTicketById('a');
        final b = await dao.getTicketById('b');
        expect(a?.status, TicketStatus.inProgress.name);
        expect(a?.updatedAt, 999);
        expect(b?.status, TicketStatus.inProgress.name);
        expect(b?.updatedAt, 999);
      },
    );

    test('leaves tickets not in the id list untouched', () async {
      await insertTicket(id: 'a', title: 'A', createdAtMs: 0);
      await insertTicket(id: 'other', title: 'Other', createdAtMs: 0);

      await dao.updateStatusByIds(['a'], TicketStatus.done, 500);

      final other = await dao.getTicketById('other');
      expect(other?.status, TicketStatus.backlog.name);
      expect(other?.updatedAt, 0);
    });
  });

  group('updatePriorityByIds', () {
    test(
      'writes the given priority to every id in the list and bumps updated_at',
      () async {
        await insertTicket(id: 'a', title: 'A', createdAtMs: 0);
        await insertTicket(id: 'b', title: 'B', createdAtMs: 0);

        await dao.updatePriorityByIds(['a', 'b'], TicketPriority.critical, 777);

        final a = await dao.getTicketById('a');
        final b = await dao.getTicketById('b');
        expect(a?.priority, TicketPriority.critical.name);
        expect(a?.updatedAt, 777);
        expect(b?.priority, TicketPriority.critical.name);
        expect(b?.updatedAt, 777);
      },
    );

    test('leaves tickets not in the id list untouched', () async {
      await insertTicket(id: 'a', title: 'A', createdAtMs: 0);
      await insertTicket(id: 'other', title: 'Other', createdAtMs: 0);

      await dao.updatePriorityByIds(['a'], TicketPriority.high, 500);

      final other = await dao.getTicketById('other');
      expect(other?.priority, TicketPriority.none.name);
      expect(other?.updatedAt, 0);
    });
  });
}
