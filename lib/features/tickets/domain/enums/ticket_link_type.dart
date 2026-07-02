// domain/enums/ticket_link_type.dart — TicketLinkType enum (domain layer).

/// The relationship a `ticket_links` row expresses between two tickets.
///
/// Non-hierarchical relationships only. Structural parent/child hierarchy
/// is modelled exclusively by `parentId` on [Ticket](../entities/ticket.dart)
/// — never by a link type.
enum TicketLinkType {
  /// The source ticket blocks the target ticket from proceeding.
  blocks,

  /// The source ticket is blocked by the target ticket. Inverse of [blocks].
  blockedBy,

  /// The tickets are related but neither blocks nor duplicates the other.
  relatesTo,

  /// The source ticket duplicates the target ticket.
  duplicates,

  /// The source ticket is duplicated by the target ticket. Inverse of
  /// [duplicates].
  duplicatedBy,
}
