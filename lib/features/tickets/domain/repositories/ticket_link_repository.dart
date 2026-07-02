import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

abstract interface class TicketLinkRepository {
  Future<List<TicketLinkData>> getLinksForTicket(String ticketId);
  Future<void> createLink({
    required String sourceTicketId,
    required String targetTicketId,
    required TicketLinkType linkType,
  });
}
