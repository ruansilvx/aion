// domain/enums/model_phase.dart — ModelPhase enum (domain layer).

/// The three capability tiers Aion buckets model calls into, by how much
/// reasoning weight the job needs — independent of the separate
/// tool-access axis (`no-tools | read-only | full`) established by
/// `sdd-design-gate`/`task-to-coding-execution-trigger`. A stage's tool
/// access and its model tier are configured separately. See
/// `aion-arch/changes/per-phase-tier-based-model-routing/design.md` §1.1.
enum ModelPhase {
  /// Epic/story-level judgment calls: `SddStage.exploring`, `.proposed`,
  /// `.verifying`.
  frontier,

  /// Comparatively mechanical work: `SddStage.designBrief`, `.designSync`,
  /// `.archived` — prompt generation, checklist-style validation, doc
  /// updates.
  capable,

  /// Task coding-execution runs (`TicketsCubit._runCodingExecution`).
  execution,
}
