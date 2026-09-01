// domain/enums/transition_outcome.dart — TransitionOutcome enum (domain layer).

/// The terminal result of walking a project-authored [SddStage] transition-
/// precondition graph (`utils/evaluate_transition_graph.dart`) — an
/// unconditional structural gate, evaluated regardless of any
/// `AutomationConfidence` setting. Deliberately a two-value outcome, unlike
/// `core/automation/decision_outcome.dart`'s four-value `DecisionOutcome` —
/// see `aion-arch/changes/sddstage-transition-preconditions/proposal.md`'s
/// "Why parallel types, not shared ones." Added for
/// `aion-arch/changes/sddstage-transition-preconditions`.
enum TransitionOutcome {
  /// The stage transition may proceed.
  allowed,

  /// The stage transition is blocked until the failing field check passes.
  blocked,
}
