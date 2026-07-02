// data/models/ticket_link_model.dart — Drift table definition for ticket_links (data layer).

import 'package:drift/drift.dart';

/// Drift table for non-hierarchical ticket-to-ticket relationships. Row type
/// is generated as `TicketLinkData`. No FK constraints — integrity is
/// enforced at the repository layer. Structural parent/child hierarchy is
/// modelled exclusively via `TicketsTable.parentId`, never here.
@DataClassName('TicketLinkData')
class TicketLinksTable extends Table {
  @override
  String get tableName => 'ticket_links';

  /// UUID v4 primary key.
  TextColumn get id => text()();

  /// UUID of the ticket the relationship originates from.
  TextColumn get sourceTicketId => text().named('source_ticket_id')();

  /// UUID of the ticket the relationship points to.
  TextColumn get targetTicketId => text().named('target_ticket_id')();

  /// `TicketLinkType.name` string.
  TextColumn get linkType => text().named('link_type')();

  @override
  Set<Column> get primaryKey => {id};
}
