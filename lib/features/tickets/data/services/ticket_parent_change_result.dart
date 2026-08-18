// data/services/ticket_parent_change_result.dart — ParentChangeResult sealed type (data layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// Outcome of [TicketParentTrashService.changeParent]. Exactly one of
/// [ParentChangeSuccess] or [ParentChangeRejected].
sealed class ParentChangeResult {
  const ParentChangeResult();
}

/// The reparent passed every validation check and was persisted.
class ParentChangeSuccess extends ParentChangeResult {
  /// Creates a [ParentChangeSuccess] carrying the refreshed [ticket].
  const ParentChangeSuccess(this.ticket);

  /// The ticket as it exists in the database after the reparent —
  /// reflects the new `parentId`.
  final Ticket ticket;
}

/// The reparent was rejected — self-parenting, an always-root ticket
/// type, an Inbox-spawned chat, a cycle (the candidate parent is one of
/// the ticket's own descendants), or a candidate parent whose type
/// cannot structurally parent the ticket's type. Nothing was written to
/// the database.
class ParentChangeRejected extends ParentChangeResult {
  /// Creates a [ParentChangeRejected]. No reason payload — every
  /// existing caller treats every rejection cause identically.
  const ParentChangeRejected();
}
