// test/features/tickets/data/repositories/drift_notification_repository_test.dart — DriftNotificationRepository delegation/mapping tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/daos/notification_dao.dart';
import 'package:aion/features/tickets/data/repositories/drift_notification_repository.dart';
import 'package:aion/features/tickets/domain/entities/notification.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockNotificationDao extends Mock implements NotificationDao {}

/// [DriftNotificationRepository] is a thin delegate over [NotificationDao]
/// — per `project.md`'s repository-test convention, these tests mock the
/// DAO via mocktail rather than spinning up a real drift instance
/// (mirrors `drift_execution_queue_repository_test.dart`'s exact shape).
/// Added for `aion-arch/changes/pr-metadata-and-notification-center`.
void main() {
  late MockAppDatabase database;
  late MockNotificationDao dao;
  late DriftNotificationRepository repository;

  final unreadRow = NotificationData(
    id: 'row-1',
    ticketId: 'task-1',
    ticketTitle: 'Fix the thing',
    kind: 'executionPrOpened',
    message: 'PR #42 opened · 5 files changed',
    createdAt: 1000,
    readAt: null,
  );

  final readRow = NotificationData(
    id: 'row-2',
    ticketId: 'task-2',
    ticketTitle: 'Stage advanced',
    kind: 'stageAdvanceCompleted',
    message: 'Advanced to Design',
    createdAt: 2000,
    readAt: 3000,
  );

  setUp(() {
    database = MockAppDatabase();
    dao = MockNotificationDao();
    when(() => database.notificationDao).thenReturn(dao);
    repository = DriftNotificationRepository(database);
  });

  group('addNotification', () {
    test('delegates to NotificationDao.insert with the entity fields', () async {
      when(
        () => dao.insert(
          ticketId: any(named: 'ticketId'),
          ticketTitle: any(named: 'ticketTitle'),
          kind: any(named: 'kind'),
          message: any(named: 'message'),
          createdAt: any(named: 'createdAt'),
        ),
      ).thenAnswer((_) async {});

      await repository.addNotification(
        Notification(
          id: '',
          ticketId: 'task-1',
          ticketTitle: 'Fix the thing',
          kind: NotificationKind.executionPrOpened,
          message: 'PR #42 opened · 5 files changed',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );

      verify(
        () => dao.insert(
          ticketId: 'task-1',
          ticketTitle: 'Fix the thing',
          kind: 'executionPrOpened',
          message: 'PR #42 opened · 5 files changed',
          createdAt: 1000,
        ),
      ).called(1);
    });
  });

  group('getRecent', () {
    test('maps DAO rows to Notification entities, including read state', () async {
      when(() => dao.getRecent(20)).thenAnswer((_) async => [unreadRow, readRow]);

      final result = await repository.getRecent();

      expect(result, hasLength(2));
      expect(result[0].id, 'row-1');
      expect(result[0].kind, NotificationKind.executionPrOpened);
      expect(result[0].readAt, isNull);
      expect(result[0].isUnread, isTrue);
      expect(result[1].id, 'row-2');
      expect(result[1].kind, NotificationKind.stageAdvanceCompleted);
      expect(result[1].readAt, DateTime.fromMillisecondsSinceEpoch(3000));
      expect(result[1].isUnread, isFalse);
    });
  });

  group('getUnreadCount', () {
    test('delegates to NotificationDao.getUnreadCount', () async {
      when(() => dao.getUnreadCount()).thenAnswer((_) async => 3);

      expect(await repository.getUnreadCount(), 3);
    });
  });

  group('markRead', () {
    test('delegates to NotificationDao.markRead', () async {
      when(() => dao.markRead(any())).thenAnswer((_) async {});

      await repository.markRead('row-1');

      verify(() => dao.markRead('row-1')).called(1);
    });
  });

  group('markAllRead', () {
    test('delegates to NotificationDao.markAllRead', () async {
      when(() => dao.markAllRead()).thenAnswer((_) async {});

      await repository.markAllRead();

      verify(() => dao.markAllRead()).called(1);
    });
  });

  group('getMostRecentForTicket', () {
    test('maps a found row to a Notification entity', () async {
      when(
        () => dao.getMostRecentForTicket('task-1', 'executionPrOpened'),
      ).thenAnswer((_) async => unreadRow);

      final result = await repository.getMostRecentForTicket(
        'task-1',
        NotificationKind.executionPrOpened,
      );

      expect(result?.id, 'row-1');
      expect(result?.kind, NotificationKind.executionPrOpened);
    });

    test('returns null when the DAO finds no row', () async {
      when(
        () => dao.getMostRecentForTicket('task-nope', 'executionPrOpened'),
      ).thenAnswer((_) async => null);

      final result = await repository.getMostRecentForTicket(
        'task-nope',
        NotificationKind.executionPrOpened,
      );

      expect(result, isNull);
    });
  });
}
