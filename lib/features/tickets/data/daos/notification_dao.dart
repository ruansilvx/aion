// data/daos/notification_dao.dart — NotificationDao Drift accessor (data layer).

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/notification_table.dart';

part 'notification_dao.g.dart';

/// Drift accessor for [NotificationsTable]. See
/// `AIO-1586` §2.
@DriftAccessor(tables: [NotificationsTable])
class NotificationDao extends DatabaseAccessor<AppDatabase>
    with _$NotificationDaoMixin {
  /// Creates a [NotificationDao] bound to [db].
  NotificationDao(super.db);

  static const _uuid = Uuid();

  /// Inserts a new, unread row. [id] is generated internally (UUID v4).
  Future<void> insert({
    required String ticketId,
    required String ticketKey,
    required String ticketTitle,
    required String kind,
    required String message,
    required int createdAt,
  }) {
    return into(notificationsTable).insert(
      NotificationsTableCompanion.insert(
        id: _uuid.v4(),
        ticketId: ticketId,
        ticketKey: ticketKey,
        ticketTitle: ticketTitle,
        kind: kind,
        message: message,
        createdAt: createdAt,
      ),
    );
  }

  /// Returns the [limit] most recent rows, newest first.
  Future<List<NotificationData>> getRecent(int limit) {
    return (select(notificationsTable)
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.createdAt,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(limit))
        .get();
  }

  /// Returns the count of rows with `readAt == null`.
  Future<int> getUnreadCount() {
    final query = selectOnly(notificationsTable)
      ..addColumns([notificationsTable.id.count()])
      ..where(notificationsTable.readAt.isNull());
    return query
        .map((row) => row.read(notificationsTable.id.count()) ?? 0)
        .getSingle();
  }

  /// Sets [id]'s `readAt` to now.
  Future<void> markRead(String id) {
    return (update(notificationsTable)..where((t) => t.id.equals(id))).write(
      NotificationsTableCompanion(
        readAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Sets every currently-unread row's `readAt` to now.
  Future<void> markAllRead() {
    return (update(
      notificationsTable,
    )..where((t) => t.readAt.isNull())).write(
      NotificationsTableCompanion(
        readAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Returns [ticketId]'s most recent row of [kind], or `null` if none
  /// exists.
  Future<NotificationData?> getMostRecentForTicket(
    String ticketId,
    String kind,
  ) {
    return (select(notificationsTable)
          ..where((t) => t.ticketId.equals(ticketId) & t.kind.equals(kind))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.createdAt,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1))
        .getSingleOrNull();
  }
}
