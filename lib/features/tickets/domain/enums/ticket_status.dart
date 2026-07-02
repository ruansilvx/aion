// domain/enums/ticket_status.dart — TicketStatus enum (domain layer).

/// The workflow state of a [Ticket](../entities/ticket.dart).
enum TicketStatus {
  /// Not yet scheduled or prioritized for work.
  backlog,

  /// Scheduled and ready to start, but work hasn't begun.
  todo,

  /// Actively being worked on.
  inProgress,

  /// Work is done and awaiting review before being marked [done].
  inReview,

  /// Work is complete and accepted.
  done,

  /// Abandoned without being completed.
  cancelled,
}
