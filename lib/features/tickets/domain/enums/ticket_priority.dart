// domain/enums/ticket_priority.dart — TicketPriority enum (domain layer).

/// The urgency of a [Ticket](../entities/ticket.dart).
///
/// Defaults to [none] at creation. The [PriorityBadge] widget omits itself
/// entirely when a ticket's priority is [none], rather than rendering an
/// empty slot.
enum TicketPriority {
  /// Drop-everything urgency.
  critical,

  /// Should be worked on ahead of most other open work.
  high,

  /// Normal priority.
  medium,

  /// Lower priority than the default; can slip without much cost.
  low,

  /// No priority assigned — the default. Hidden from the UI rather than
  /// shown as an empty badge.
  none,
}
