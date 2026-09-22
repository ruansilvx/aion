// domain/enums/model_phase.dart — ModelPhase enum (domain layer).

import 'package:aion/core/contracts/tool_access_tier.dart';

/// The capability tiers Aion buckets model calls into, by how much
/// reasoning weight the job needs — independent of the separate tool-access
/// axis (`no-tools | read-only | full`) established by
/// `sdd-design-gate`/`task-to-coding-execution-trigger`. A stage's tool access
/// and its model tier are configured separately. See `AIO-1491` §1.1.
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

  /// The independent per-Task review of a coding-execution diff, run
  /// after mechanical verification passes and before the PR is opened
  /// (AIO-2999). Routed separately from [execution] so a stronger model
  /// can review a cheaper model's work.
  taskVerify,
}

/// The [ToolAccessTier] each [ModelPhase] actually requires — makes what every
/// call site already passes as a literal `toolsEnabled: true`/ `false` into
/// declared data, used to filter which providers' models a phase's Settings
/// dropdown may offer. Deliberately not used to derive
/// `AgentRequest.toolsEnabled` at request-construction time — the two stay
/// independently authored for now (see `AIO-1544` §3).
extension ModelPhaseToolAccess on ModelPhase {
  /// The [ToolAccessTier] this phase's model calls require.
  ToolAccessTier get requiredToolAccessTier => switch (this) {
    ModelPhase.frontier || ModelPhase.capable => ToolAccessTier.noTools,
    // taskVerify's call site narrows its own turn to read-only tools; the
    // phase-wide tier only governs which providers' models Settings offers.
    ModelPhase.execution || ModelPhase.taskVerify => ToolAccessTier.full,
  };
}
