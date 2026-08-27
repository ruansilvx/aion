// core/automation/decision_outcome.dart — DecisionOutcome enum (core layer).

/// The terminal result of walking a [AutomationContext]-scoped decision
/// graph (see `decision_graph_evaluator.dart`) once a context's persisted
/// [AutomationConfidence] has already resolved to
/// `AutomationConfidence.auto`. Added for
/// `aion-arch/changes/automation-decision-graphs`.
enum DecisionOutcome {
  /// Apply the decision silently, exactly as plain `auto` confidence
  /// always has — no user interaction.
  proceed,

  /// Surface the decision and wait for explicit confirmation before
  /// applying it, via that call site's existing gated-surfacing
  /// mechanism (`_awaitProposalConfirmation`, the `executionAwaitingReview`
  /// banner path, etc.) — never a new UI surface.
  gated,

  /// Decline the action outright, via that call site's existing decline
  /// reason shape.
  decline,

  /// Evaluates identically to [proceed] at runtime — it exists as a
  /// distinct value so the node's condition description can be collected
  /// into prompt-surfaced context ahead of the model's own decision,
  /// rather than intercepting that decision afterward. No mechanism in
  /// this codebase pauses mid-tool-call to ask the model a follow-up and
  /// resume, so there is nothing else for this value to do at evaluation
  /// time.
  modelJudgment,
}
