// domain/enums/ticket_complexity.dart — TicketComplexity enum (domain layer).

/// A rough size estimate for a [Ticket](../entities/ticket.dart), set
/// manually by the user (no automated estimation yet). `null` means
/// unset — omitted from display, mirroring [TicketPriority.none]'s
/// "hidden rather than shown empty" convention, but via nullability
/// instead of a fourth enum value since unlike priority there is no
/// meaningful "no complexity" ticket state, only "not sized yet."
enum TicketComplexity {
  /// A small, quick unit of work.
  small,

  /// A moderate unit of work.
  medium,

  /// A large unit of work, a candidate for further breakdown.
  large,
}
