// domain/enums/sdd_stage.dart — SddStage enum (domain layer).

import 'package:aion/features/providers/domain/enums/model_phase.dart';

/// An [epic]/[story]/[bug] Ticket's progress through the SDD cycle,
/// mirroring the `aion-arch/.claude/skills/` stage names. `null` on
/// `Ticket.sddStage` means the cycle hasn't started. Meaningful only for
/// `TicketType.epic`/`TicketType.story`/`TicketType.bug` —
/// `TicketsCubit.advanceSddStage` rejects every other type (`task`
/// explicitly excluded — see `AIO-2898`'s "explicit scope decisions").
/// Task-level execution has no stage of its own; a Story's `verifying`
/// transition is gated on its child Tasks' `TicketStatus.done`, not a
/// distinct Task-level stage value.
///
/// The full cycle is
/// `exploring → proposed → designBrief → designSync → applying → verifying →
/// archived`, but most tickets skip most of the middle: [designBrief]/
/// [designSync] are only ever reached by a [TicketType.story] ticket whose
/// child Tasks indicate UI work (`TicketsCubit._storyNeedsDesignReview`) —
/// every Epic, and every Story whose Tasks don't, goes `proposed →
/// verifying` directly, exactly as before those two stages existed. [applying]
/// is only ever reached by a [TicketType.bug] — an Epic/Story never visits it
/// (their own `proposed → verifying`/`designSync → verifying` transitions are
/// unchanged); it exists because a Bug has no children to delegate actual
/// code-writing to (unlike a Story delegating to child Tasks), so it needs an
/// explicit stage of its own for that. See `AIO-1834` §1, `AIO-2898`.
enum SddStage {
  /// The Exploration-stage chat is active or has completed.
  exploring,

  /// The Propose-stage chat produced children (Stories for an epic,
  /// Tasks for a story) and is awaiting their completion — or, for a
  /// [TicketType.bug] (which has no children), wrote a fix plan and is
  /// awaiting its own `PROPOSE GATE: APPROVED` verdict. See `AIO-2898`.
  proposed,

  /// The Design Brief-stage chat generated a ready-to-paste Claude
  /// Design prompt; awaiting the human's pasted export in the linked
  /// design Page ticket. Story-only, skipped when no child Task
  /// indicates UI work.
  designBrief,

  /// The Design Sync-stage chat is validating the pasted design export
  /// against Aion's Non-Material constraint and design tokens. Story-only,
  /// skipped alongside [designBrief].
  designSync,

  /// A [TicketType.bug]-only stage — entering it fires the same autonomous
  /// coding-execution run that a Task/Bug's plain-status executionTrigger
  /// shortcut already fires, seeded with the approved Explore diagnosis +
  /// Proposed fix plan as context. Never reached by an Epic/Story (they
  /// delegate actual code-writing to child Task tickets instead, which have
  /// no stage of their own — see this enum's own dartdoc). Added for
  /// `AIO-2898`, this project's SDD cycle's first stage explicitly named
  /// "apply" (`explore → propose → apply → verify → archive`).
  applying,

  /// The Verification-stage chat is active or has completed — for a
  /// [TicketType.bug], this reviews whatever [applying] just did (a real
  /// diff/PR, or "nothing to fix"), the same self-assessed `VERIFY GATE`
  /// mechanism Epic/Story already use, unchanged. See `AIO-2898`.
  verifying,

  /// The Archival-stage chat has completed; the cycle is closed.
  archived,
}

/// Maps each [SddStage] to the [ModelPhase] that drives its spawned chat's
/// model choice, per `AIO-1491` §1.2's confirmed split:
/// `exploring`/`proposed`/`verifying` are epic/story-level judgment calls
/// ([ModelPhase.frontier]); `designBrief`/`designSync`/ `archived` are
/// comparatively mechanical work ([ModelPhase.capable]).
extension SddStageModelPhase on SddStage {
  /// The [ModelPhase] this stage's spawned chat resolves its model
  /// through. [SddStage.applying] never actually spawns a "stage chat" via
  /// this mechanism at all — entering it fires the coding-execution
  /// mechanism directly (see `TicketsCubit.advanceSddStage`'s dedicated
  /// branch), which resolves its own model via [ModelPhase.execution]
  /// independently. [ModelPhase.execution] is given here anyway, for an
  /// exhaustive switch and in case some future caller queries it directly.
  ModelPhase get modelPhase => switch (this) {
    SddStage.exploring || SddStage.proposed || SddStage.verifying =>
      ModelPhase.frontier,
    SddStage.designBrief || SddStage.designSync || SddStage.archived =>
      ModelPhase.capable,
    SddStage.applying => ModelPhase.execution,
  };
}
