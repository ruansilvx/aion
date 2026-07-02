// domain/repositories/ticket_link_repository.dart — TicketLinkRepository interface (domain layer).

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

/// Read/write access to non-hierarchical ticket-to-ticket relationships
/// (`ticket_links`). No link UI exists yet in this slice — schema and
/// domain layer only, ready for a future change.
abstract interface class TicketLinkRepository {
  /// Returns every link where [ticketId] is either the source or the target.
  Future<List<TicketLinkData>> getLinksForTicket(String ticketId);

  /// Creates a [linkType] relationship from [sourceTicketId] to
  /// [targetTicketId].
  Future<void> createLink({
    required String sourceTicketId,
    required String targetTicketId,
    required TicketLinkType linkType,
  });
}
