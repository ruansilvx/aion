// domain/enums/ticket_severity.dart — TicketSeverity enum (domain layer).

/// The impact of a [Ticket](../entities/ticket.dart) of type
/// [TicketType](ticket_type.dart) `bug` — independent of `TicketPriority`,
/// which is scheduling urgency, not impact. Meaningless for every other
/// `TicketType`; `null` on `Ticket.severity` means "not sized yet,"
/// mirroring `TicketComplexity`'s nullable-until-set treatment (no `none`
/// member, unlike `TicketPriority`).
enum TicketSeverity {
  /// The bug makes the product unusable or causes data loss/corruption.
  critical,

  /// The bug significantly degrades a core flow but has a workaround.
  high,

  /// The bug is a real problem but affects a non-critical flow.
  medium,

  /// The bug is cosmetic or a minor inconvenience.
  low,
}
