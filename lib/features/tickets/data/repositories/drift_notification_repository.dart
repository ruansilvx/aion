// data/repositories/drift_notification_repository.dart — Drift implementation of NotificationRepository (data layer).

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/domain/entities/notification.dart';
import 'package:aion/features/tickets/domain/repositories/notification_repository.dart';

/// Drift-backed implementation of [NotificationRepository]. No business
/// logic here — maps [NotificationData] rows to [Notification] entities
/// and delegates every method straight to [NotificationDao], matching
/// [DriftExecutionQueueRepository]'s exact shape. Added for
/// `aion-arch/changes/pr-metadata-and-notification-center`.
class DriftNotificationRepository implements NotificationRepository {
  /// Creates a [DriftNotificationRepository] backed by [_db].
  DriftNotificationRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> addNotification(Notification notification) {
    return _db.notificationDao.insert(
      ticketId: notification.ticketId,
      ticketKey: notification.ticketKey,
      ticketTitle: notification.ticketTitle,
      kind: notification.kind.name,
      message: notification.message,
      createdAt: notification.createdAt.millisecondsSinceEpoch,
    );
  }

  @override
  Future<List<Notification>> getRecent({int limit = 20}) async {
    final rows = await _db.notificationDao.getRecent(limit);
    return rows.map(_toEntity).toList();
  }

  @override
  Future<int> getUnreadCount() => _db.notificationDao.getUnreadCount();

  @override
  Future<void> markRead(String id) => _db.notificationDao.markRead(id);

  @override
  Future<void> markAllRead() => _db.notificationDao.markAllRead();

  @override
  Future<Notification?> getMostRecentForTicket(
    String ticketId,
    NotificationKind kind,
  ) async {
    final row = await _db.notificationDao.getMostRecentForTicket(
      ticketId,
      kind.name,
    );
    return row == null ? null : _toEntity(row);
  }

  /// Maps a raw [NotificationData] row to its domain [Notification]
  /// entity.
  Notification _toEntity(NotificationData row) => Notification(
    id: row.id,
    ticketId: row.ticketId,
    ticketKey: row.ticketKey,
    ticketTitle: row.ticketTitle,
    kind: NotificationKind.values.byName(row.kind),
    message: row.message,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    readAt: row.readAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.readAt!),
  );
}
