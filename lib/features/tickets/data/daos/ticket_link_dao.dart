// data/daos/ticket_link_dao.dart — TicketLinkDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/ticket_link_model.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

part 'ticket_link_dao.g.dart';

/// Drift accessor for [TicketLinksTable], also reading [TicketsTable] to
/// filter out links to trashed tickets.
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
  /// sits in Trash. Deduplicated by [TicketLinkData.id]: a self-link (a
  /// ticket linked to itself) would otherwise match both the source-side
  /// and target-side query below and be returned twice.
  Future<List<TicketLinkData>> getLinksForTicket(String ticketId) async {
    final asSource =
        await (select(ticketLinksTable).join([
              innerJoin(
                ticketsTable,
                ticketsTable.id.equalsExp(ticketLinksTable.targetTicketId),
              ),
            ])..where(
              ticketLinksTable.sourceTicketId.equals(ticketId) &
                  ticketsTable.deletedAt.isNull(),
            ))
            .map((row) => row.readTable(ticketLinksTable))
            .get();

    final asTarget =
        await (select(ticketLinksTable).join([
              innerJoin(
                ticketsTable,
                ticketsTable.id.equalsExp(ticketLinksTable.sourceTicketId),
              ),
            ])..where(
              ticketLinksTable.targetTicketId.equals(ticketId) &
                  ticketsTable.deletedAt.isNull(),
            ))
            .map((row) => row.readTable(ticketLinksTable))
            .get();

    final byId = <String, TicketLinkData>{};
    for (final link in [...asSource, ...asTarget]) {
      byId[link.id] = link;
    }
    return byId.values.toList();
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

  /// Returns every live link row app-wide whose [TicketLinkData.linkType]
  /// (matched by [TicketLinkType.name]) is one of [types], excluding rows
  /// where either side's ticket is currently trashed. Whole-table-scoped,
  /// like [deleteLinksForTickets] — no per-ticket-id filter — because
  /// callers (the Board's blocked-set computation) need every matching row
  /// at once rather than one ticket's links at a time. Both sides of each
  /// link are joined against [ticketsTable] in a single query (aliased as
  /// source/target) so trashed-ticket filtering applies to each side
  /// independently, rather than [getLinksForTicket]'s two-pass
  /// source/target union.
  Future<List<TicketLinkData>> getLinksByTypes(
    List<TicketLinkType> types,
  ) async {
    final sourceTickets = alias(ticketsTable, 'source_tickets');
    final targetTickets = alias(ticketsTable, 'target_tickets');

    final rows =
        await (select(ticketLinksTable).join([
              innerJoin(
                sourceTickets,
                sourceTickets.id.equalsExp(ticketLinksTable.sourceTicketId),
              ),
              innerJoin(
                targetTickets,
                targetTickets.id.equalsExp(ticketLinksTable.targetTicketId),
              ),
            ])..where(
              ticketLinksTable.linkType.isIn(types.map((t) => t.name)) &
                  sourceTickets.deletedAt.isNull() &
                  targetTickets.deletedAt.isNull(),
            ))
            .get();

    return rows.map((row) => row.readTable(ticketLinksTable)).toList();
  }

  /// Returns the single row with id [linkId], or `null` if it doesn't
  /// exist. Unlike [getLinksForTicket]/[getLinksByTypes], this doesn't
  /// filter out rows whose other side is trashed — callers need the raw
  /// row (e.g. to check its [TicketLinkData.linkType] before a delete/
  /// update) regardless of the other ticket's current trash state.
  Future<TicketLinkData?> getLinkById(String linkId) {
    return (select(
      ticketLinksTable,
    )..where((t) => t.id.equals(linkId))).getSingleOrNull();
  }

  /// Deletes the single row with id [linkId]. No-ops if it doesn't exist.
  Future<void> deleteLink(String linkId) {
    return (delete(ticketLinksTable)..where((t) => t.id.equals(linkId))).go();
  }

  /// Updates the single row with id [linkId]'s [TicketLinkData.linkType]
  /// to [newType].name. No-ops if the row doesn't exist.
  Future<void> updateLinkType(String linkId, TicketLinkType newType) {
    return (update(ticketLinksTable)..where((t) => t.id.equals(linkId)))
        .write(TicketLinksTableCompanion(linkType: Value(newType.name)));
  }
}
