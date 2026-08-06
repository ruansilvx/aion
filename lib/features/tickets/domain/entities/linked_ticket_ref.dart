// domain/entities/linked_ticket_ref.dart — LinkedTicketRef record typedef (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';

/// A resolved `TicketLink` row, from the perspective of whichever ticket
/// is being viewed: the other-side [ticket] it resolves to, the
/// relationship's [relativeType] as it reads *from the viewing ticket's
/// side* (see `ticket_link_direction.dart`'s `relativeLinkType`), and the
/// underlying link row's own [linkId] — needed so a caller can delete or
/// retype the exact row this ref came from without re-resolving it.
///
/// Replaces the bare `Ticket` `TicketDetailLoaded.linkedTickets`/
/// `.backlinks` used to carry: a link's type never survived past
/// `TicketsCubit.loadDocumentRelations` before this, so nothing could
/// render it or mutate it.
typedef LinkedTicketRef = ({
  Ticket ticket,
  TicketLinkType relativeType,
  String linkId,
});
