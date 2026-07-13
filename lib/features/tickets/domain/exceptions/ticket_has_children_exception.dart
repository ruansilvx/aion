// domain/exceptions/ticket_has_children_exception.dart — TicketHasChildrenException (domain layer).

/// Thrown by [TicketRepository.deleteTicket] when the target ticket has
/// one or more structural children (other tickets whose `parentId` points
/// at it). Deletion is blocked rather than cascading to children, so the
/// caller must reparent or delete them first.
class TicketHasChildrenException implements Exception {
  /// Creates a [TicketHasChildrenException] for a ticket with [childCount]
  /// structural children.
  const TicketHasChildrenException(this.childCount);

  /// How many tickets have `parentId` pointing at the ticket that failed
  /// to delete.
  final int childCount;

  @override
  String toString() => 'TicketHasChildrenException($childCount children)';
}
