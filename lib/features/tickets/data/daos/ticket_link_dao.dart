// data/daos/ticket_link_dao.dart — TicketLinkDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/ticket_link_model.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';

part 'ticket_link_dao.g.dart';

/// Drift accessor for [TicketLinksTable].
@DriftAccessor(tables: [TicketLinksTable, TicketsTable])
class TicketLinkDao extends DatabaseAccessor<AppDatabase>
    with _$TicketLinkDaoMixin {
  /// Creates a [TicketLinkDao] bound to [db].
  TicketLinkDao(super.db);

  /// Returns every link where [ticketId] is the source or the target, and
  /// the *other* ticket in the link is not currently trashed. A link to a
  /// trashed ticket reappears automatically once that ticket is restored,
  /// and disappears for good once it's permanently deleted (which
  /// cascade-deletes the link row itself via [deleteLinksForTickets]) — so
  /// this filter only affects the interim window while the other ticket
  /// sits in Trash.
  Future<List<TicketLinkData>> getLinksForTicket(String ticketId) async {
    final asSource = await (select(ticketLinksTable).join([
          innerJoin(
            ticketsTable,
            ticketsTable.id.equalsExp(ticketLinksTable.targetTicketId),
          ),
        ])
          ..where(
            ticketLinksTable.sourceTicketId.equals(ticketId) &
                ticketsTable.deletedAt.isNull(),
          ))
        .map((row) => row.readTable(ticketLinksTable))
        .get();

    final asTarget = await (select(ticketLinksTable).join([
          innerJoin(
            ticketsTable,
            ticketsTable.id.equalsExp(ticketLinksTable.sourceTicketId),
          ),
        ])
          ..where(
            ticketLinksTable.targetTicketId.equals(ticketId) &
                ticketsTable.deletedAt.isNull(),
          ))
        .map((row) => row.readTable(ticketLinksTable))
        .get();

    return [...asSource, ...asTarget];
  }

  /// Inserts [entry] as a new link row.
  Future<void> insertLink(TicketLinksTableCompanion entry) {
    return into(ticketLinksTable).insert(entry);
  }

  /// Deletes every link row where the source or target is any ticket in
  /// [ticketIds]. Used by permanent ticket deletion (a whole subtree's
  /// worth of ids at once).
  Future<void> deleteLinksForTickets(List<String> ticketIds) {
    return (delete(ticketLinksTable)..where(
          (t) =>
              t.sourceTicketId.isIn(ticketIds) |
              t.targetTicketId.isIn(ticketIds),
        ))
        .go();
  }
}
