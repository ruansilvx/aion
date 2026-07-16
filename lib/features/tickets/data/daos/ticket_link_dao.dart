// data/daos/ticket_link_dao.dart — TicketLinkDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/ticket_link_model.dart';

part 'ticket_link_dao.g.dart';

/// Drift accessor for [TicketLinksTable].
@DriftAccessor(tables: [TicketLinksTable])
class TicketLinkDao extends DatabaseAccessor<AppDatabase>
    with _$TicketLinkDaoMixin {
  /// Creates a [TicketLinkDao] bound to [db].
  TicketLinkDao(super.db);

  /// Returns every link where [ticketId] is the source or the target.
  Future<List<TicketLinkData>> getLinksForTicket(String ticketId) {
    return (select(ticketLinksTable)..where(
          (t) =>
              t.sourceTicketId.equals(ticketId) |
              t.targetTicketId.equals(ticketId),
        ))
        .get();
  }

  /// Inserts [entry] as a new link row.
  Future<void> insertLink(TicketLinksTableCompanion entry) {
    return into(ticketLinksTable).insert(entry);
  }

  /// Deletes every link row where [ticketId] is the source or the target.
  Future<void> deleteLinksForTicket(String ticketId) {
    return (delete(ticketLinksTable)..where(
          (t) =>
              t.sourceTicketId.equals(ticketId) |
              t.targetTicketId.equals(ticketId),
        ))
        .go();
  }
}
