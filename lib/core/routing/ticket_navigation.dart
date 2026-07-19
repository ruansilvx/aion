// core/routing/ticket_navigation.dart — ticketDetailRoute navigation resolver (core layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Resolves the correct detail route for any ticket, accounting for
/// `page` tickets living in their own module
/// (`/workspace/pages/:id`) since the `page-content-markdown-editor`
/// change — every other type still resolves to
/// `/workspace/tickets/:id`. Used by every call site that navigates to a
/// ticket generically by id (Documentation tree taps, linked-tickets/
/// backlinks taps, board/list navigation) instead of hardcoding
/// `/workspace/tickets/${ticket.id}`.
String ticketDetailRoute(Ticket ticket) => ticket.type == TicketType.page
    ? '/workspace/pages/${ticket.id}'
    : '/workspace/tickets/${ticket.id}';
