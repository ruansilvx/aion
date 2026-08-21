// test/features/tickets/data/daos/notification_dao_test.dart — NotificationDao persistence-behavior tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/daos/notification_dao.dart';

/// Dummy project — [AppDatabase] requires per-project addressing, unused
/// here since every test passes an explicit in-memory executor.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

/// Direct [NotificationDao] tests against a real in-memory drift instance
/// — same precedent as `page_wikilink_dao_test.dart`/
/// `ticket_link_dao_test.dart`. Added for
/// `aion-arch/changes/pr-metadata-and-notification-center`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late NotificationDao dao;

  setUp(() {
    database = AppDatabase(_testProject, NativeDatabase.memory());
    dao = database.notificationDao;
  });

  tearDown(() async {
    await database.close();
  });

  group('insert / getRecent', () {
    test('round-trips an inserted row', () async {
      await dao.insert(
        ticketId: 'task-1',
        ticketKey: 'AIO-1',
        ticketTitle: 'Fix the thing',
        kind: 'executionPrOpened',
        message: 'PR #42 opened · 5 files changed',
        createdAt: 1000,
      );

      final rows = await dao.getRecent(20);
      expect(rows, hasLength(1));
      expect(rows.single.ticketId, 'task-1');
      expect(rows.single.ticketKey, 'AIO-1');
      expect(rows.single.ticketTitle, 'Fix the thing');
      expect(rows.single.kind, 'executionPrOpened');
      expect(rows.single.message, 'PR #42 opened · 5 files changed');
      expect(rows.single.createdAt, 1000);
      expect(rows.single.readAt, isNull);
    });

    test('orders newest first', () async {
      await dao.insert(
        ticketId: 'task-1',
        ticketKey: 'AIO-1',
        ticketTitle: 'Older',
        kind: 'executionPrOpened',
        message: 'older',
        createdAt: 1000,
      );
      await dao.insert(
        ticketId: 'task-2',
        ticketKey: 'AIO-2',
        ticketTitle: 'Newer',
        kind: 'executionPrOpened',
        message: 'newer',
        createdAt: 2000,
      );

      final rows = await dao.getRecent(20);
      expect(rows.map((r) => r.ticketTitle), ['Newer', 'Older']);
    });

    test('respects the limit', () async {
      for (var i = 0; i < 5; i++) {
        await dao.insert(
          ticketId: 'task-$i',
          ticketKey: 'AIO-$i',
          ticketTitle: 'Ticket $i',
          kind: 'executionPrOpened',
          message: 'msg',
          createdAt: i,
        );
      }

      final rows = await dao.getRecent(2);
      expect(rows, hasLength(2));
    });
  });

  group('getUnreadCount', () {
    test('counts only rows with readAt == null', () async {
      await dao.insert(
        ticketId: 'task-1',
        ticketKey: 'AIO-1',
        ticketTitle: 'A',
        kind: 'executionPrOpened',
        message: 'a',
        createdAt: 1,
      );
      await dao.insert(
        ticketId: 'task-2',
        ticketKey: 'AIO-2',
        ticketTitle: 'B',
        kind: 'executionPrOpened',
        message: 'b',
        createdAt: 2,
      );

      expect(await dao.getUnreadCount(), 2);

      final rows = await dao.getRecent(20);
      await dao.markRead(rows.first.id);

      expect(await dao.getUnreadCount(), 1);
    });

    test('returns 0 for an empty table', () async {
      expect(await dao.getUnreadCount(), 0);
    });
  });

  group('markRead', () {
    test('sets readAt on the matching row only', () async {
      await dao.insert(
        ticketId: 'task-1',
        ticketKey: 'AIO-1',
        ticketTitle: 'A',
        kind: 'executionPrOpened',
        message: 'a',
        createdAt: 1,
      );
      await dao.insert(
        ticketId: 'task-2',
        ticketKey: 'AIO-2',
        ticketTitle: 'B',
        kind: 'executionPrOpened',
        message: 'b',
        createdAt: 2,
      );
      final rows = await dao.getRecent(20);
      final target = rows.firstWhere((r) => r.ticketId == 'task-1');

      await dao.markRead(target.id);

      final refreshed = await dao.getRecent(20);
      final marked = refreshed.firstWhere((r) => r.ticketId == 'task-1');
      final untouched = refreshed.firstWhere((r) => r.ticketId == 'task-2');
      expect(marked.readAt, isNotNull);
      expect(untouched.readAt, isNull);
    });
  });

  group('markAllRead', () {
    test('sets readAt on every unread row', () async {
      for (var i = 0; i < 3; i++) {
        await dao.insert(
          ticketId: 'task-$i',
          ticketKey: 'AIO-$i',
          ticketTitle: 'Ticket $i',
          kind: 'executionPrOpened',
          message: 'msg',
          createdAt: i,
        );
      }

      await dao.markAllRead();

      final rows = await dao.getRecent(20);
      expect(rows.every((r) => r.readAt != null), isTrue);
      expect(await dao.getUnreadCount(), 0);
    });
  });

  group('getMostRecentForTicket', () {
    test('returns the newest row matching ticketId and kind', () async {
      await dao.insert(
        ticketId: 'task-1',
        ticketKey: 'AIO-1',
        ticketTitle: 'A',
        kind: 'executionPrOpened',
        message: 'first',
        createdAt: 1000,
      );
      await dao.insert(
        ticketId: 'task-1',
        ticketKey: 'AIO-1',
        ticketTitle: 'A',
        kind: 'executionPrOpened',
        message: 'second',
        createdAt: 2000,
      );
      await dao.insert(
        ticketId: 'task-1',
        ticketKey: 'AIO-1',
        ticketTitle: 'A',
        kind: 'executionFailed',
        message: 'wrong kind',
        createdAt: 3000,
      );

      final result = await dao.getMostRecentForTicket(
        'task-1',
        'executionPrOpened',
      );
      expect(result?.message, 'second');
    });

    test('returns null when no row matches', () async {
      final result = await dao.getMostRecentForTicket(
        'task-nope',
        'executionPrOpened',
      );
      expect(result, isNull);
    });
  });
}
