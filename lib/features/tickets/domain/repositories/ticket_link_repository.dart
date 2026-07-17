// domain/repositories/ticket_link_repository.dart — TicketLinkRepository interface (domain layer).

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

/// Read/write access to non-hierarchical ticket-to-ticket relationships
/// (`ticket_links`). `LinkCountLabel` (`tickets_list_screen.dart`) already
/// consumes [getLinksForTicket] for a per-ticket link count; there is
/// still no screen for browsing, creating, or editing individual links.
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
