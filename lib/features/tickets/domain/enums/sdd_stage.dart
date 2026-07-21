// domain/enums/sdd_stage.dart — SddStage enum (domain layer).

/// An [epic] or [story] Ticket's progress through the SDD cycle
/// (explore → propose → verify → archive), mirroring the
/// `aion-arch/.claude/skills/` stage names. `null` on `Ticket.sddStage`
/// means the cycle hasn't started. Meaningful only for
/// `TicketType.epic`/`TicketType.story` — `TicketsCubit.advanceSddStage`
/// rejects every other type. Task-level execution has no stage of its
/// own; a Story's `verifying` transition is gated on its child Tasks'
/// `TicketStatus.done`, not a distinct Task-level stage value.
enum SddStage {
  /// The Exploration-stage chat is active or has completed.
  exploring,

  /// The Propose-stage chat produced children (Stories for an epic,
  /// Tasks for a story) and is awaiting their completion.
  proposed,

  /// The Verification-stage chat is active or has completed.
  verifying,

  /// The Archival-stage chat has completed; the cycle is closed.
  archived,
}
