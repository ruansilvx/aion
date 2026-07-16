// data/repositories/drift_ticket_link_repository.dart — Drift implementation of TicketLinkRepository (data layer).

import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';

/// Drift-backed implementation of [TicketLinkRepository].
class DriftTicketLinkRepository implements TicketLinkRepository {
  /// Creates a [DriftTicketLinkRepository] backed by [_db].
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
