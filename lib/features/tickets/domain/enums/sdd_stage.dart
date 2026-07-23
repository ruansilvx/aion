// domain/enums/sdd_stage.dart — SddStage enum (domain layer).

import 'package:aion/features/providers/domain/enums/model_phase.dart';

/// An [epic] or [story] Ticket's progress through the SDD cycle, mirroring
/// the `aion-arch/.claude/skills/` stage names. `null` on `Ticket.sddStage`
/// means the cycle hasn't started. Meaningful only for
/// `TicketType.epic`/`TicketType.story` — `TicketsCubit.advanceSddStage`
/// rejects every other type. Task-level execution has no stage of its
/// own; a Story's `verifying` transition is gated on its child Tasks'
/// `TicketStatus.done`, not a distinct Task-level stage value.
///
/// The full cycle is `exploring → proposed → designBrief → designSync →
/// verifying → archived`, but [designBrief]/[designSync] are skippable —
/// they're only ever reached by a [TicketType.story] ticket whose child
/// Tasks indicate UI work (`TicketsCubit._storyNeedsDesignReview`).
/// Every Epic, and every Story whose Tasks don't, goes `proposed →
/// verifying` directly, exactly as before this pair of stages existed.
/// See `aion-arch/changes/sdd-design-gate/design.md` §1.
enum SddStage {
  /// The Exploration-stage chat is active or has completed.
  exploring,

  /// The Propose-stage chat produced children (Stories for an epic,
  /// Tasks for a story) and is awaiting their completion.
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

  /// The Verification-stage chat is active or has completed.
  verifying,

  /// The Archival-stage chat has completed; the cycle is closed.
  archived,
}

/// Maps each [SddStage] to the [ModelPhase] that drives its spawned
/// chat's model choice, per
/// `aion-arch/changes/per-phase-tier-based-model-routing/design.md` §1.2's
/// confirmed split: `exploring`/`proposed`/`verifying` are epic/story-level
/// judgment calls ([ModelPhase.frontier]); `designBrief`/`designSync`/
/// `archived` are comparatively mechanical work ([ModelPhase.capable]).
extension SddStageModelPhase on SddStage {
  /// The [ModelPhase] this stage's spawned chat resolves its model
  /// through.
  ModelPhase get modelPhase => switch (this) {
    SddStage.exploring || SddStage.proposed || SddStage.verifying =>
      ModelPhase.frontier,
    SddStage.designBrief || SddStage.designSync || SddStage.archived =>
      ModelPhase.capable,
  };
}
