import 'package:drift/drift.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/models/ticket_link_model.dart';

part 'ticket_link_dao.g.dart';

@DriftAccessor(tables: [TicketLinksTable])
class TicketLinkDao extends DatabaseAccessor<AppDatabase> with _$TicketLinkDaoMixin {
  TicketLinkDao(super.db);

  Future<List<TicketLinkData>> getLinksForTicket(String ticketId) {
    return (select(ticketLinksTable)
          ..where((t) =>
              t.sourceTicketId.equals(ticketId) |
              t.targetTicketId.equals(ticketId)))
        .get();
  }

  Future<void> insertLink(TicketLinksTableCompanion entry) {
    return into(ticketLinksTable).insert(entry);
  }
}
