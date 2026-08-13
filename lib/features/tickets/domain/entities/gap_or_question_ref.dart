// domain/entities/gap_or_question_ref.dart — GapOrQuestionRef record typedef (domain layer).

import 'package:aion/features/tickets/domain/entities/linked_ticket_ref.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// A resolved `knownGap`/`openQuestion` [ticket], recursively rolled up
/// onto the ticket currently being viewed: the gap/question [ticket]
/// itself, the specific [raisedOn] ticket it's `relatesTo`-linked to (the
/// viewed ticket itself, or one of its descendants), and the underlying
/// `TicketLink` row's own [linkId].
///
/// `raisedOn` is what lets the UI distinguish a gap/question raised
/// directly on the viewed ticket from one rolled up from a descendant —
/// e.g. rendering "Open question — on Login Flow (Story)" when viewed
/// from an Epic two levels up, vs. just the title when
/// `raisedOn.id == ticket.id`. Mirrors [LinkedTicketRef]'s shape. Added
/// for `aion-arch/changes/idea-gap-question-ticket-types`; populated by
/// `TicketsCubit.loadDocumentRelations`.
typedef GapOrQuestionRef = ({
  Ticket ticket,
  Ticket raisedOn,
  String linkId,
});
