// data/models/notification_table.dart — Drift table definition for notifications (data layer).

import 'package:drift/drift.dart';

/// Drift table backing [Notification]. Row type generated as
/// `NotificationData`. No FK constraints — matches every other table in
/// this schema (integrity enforced at the repository layer). Added for
/// `aion-arch/changes/pr-metadata-and-notification-center`.
@DataClassName('NotificationData')
class NotificationsTable extends Table {
  @override
  String get tableName => 'notifications';

  /// UUID v4 primary key.
  TextColumn get id => text()();

  /// The Task/Bug/Epic/Story ticket this notification concerns.
  TextColumn get ticketId => text().named('ticket_id')();

  /// [ticketId]'s human-readable key (e.g. `"AIO-42"`), snapshotted at
  /// write time — `Ticket.ticketId`, not to be confused with this
  /// column's own [ticketId] (the internal UUID). Feeds the dropdown
  /// row's leading mono key segment (Component Spec §6.4).
  TextColumn get ticketKey => text().named('ticket_key')();

  /// [ticketId]'s title, snapshotted at write time.
  TextColumn get ticketTitle => text().named('ticket_title')();

  /// `NotificationKind.name` string.
  TextColumn get kind => text()();

  /// Precomputed, already-formatted display text.
  TextColumn get message => text()();

  /// Unix milliseconds.
  IntColumn get createdAt => integer().named('created_at')();

  /// Unix milliseconds. `null` while unread — see
  /// `Notification.readAt`'s dartdoc for why this is a nullable
  /// timestamp rather than a bool.
  IntColumn get readAt => integer().named('read_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
