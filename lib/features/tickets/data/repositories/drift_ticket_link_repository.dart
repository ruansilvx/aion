import 'package:uuid/uuid.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';

class DriftTicketLinkRepository implements TicketLinkRepository {
  DriftTicketLinkRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<List<TicketLinkData>> getLinksForTicket(String ticketId) {
    return _db.ticketLinkDao.getLinksForTicket(ticketId);
  }

  @override
  Future<void> createLink({
    required String sourceTicketId,
    required String targetTicketId,
    required TicketLinkType linkType,
  }) {
    final companion = TicketLinksTableCompanion.insert(
      id: _uuid.v4(),
      sourceTicketId: sourceTicketId,
      targetTicketId: targetTicketId,
      linkType: linkType.name,
    );

    return _db.ticketLinkDao.insertLink(companion);
  }
}
