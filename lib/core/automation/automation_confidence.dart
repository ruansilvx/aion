// core/automation/automation_confidence.dart — AutomationConfidence enum (core layer).

/// The shared three-state confidence level for an automated decision
/// point, per `project.md` §5's "Shared automation-confidence pattern."
/// This change ships its first real instance and consumer
/// (SDD-stage-triggering, see `TicketsCubit.advanceSddStage`) — later
/// automated points (a budget gate, a batch-flush gate) get their own
/// [AutomationConfidence] instance via
/// `AutomationSettingsRepository` once they're built, not a shared
/// single value.
enum AutomationConfidence {
  /// Applies the automated decision silently, no user interaction.
  auto,

  /// Surfaces the decision and waits for explicit confirmation before
  /// applying it.
  gated,

  /// Never surfaces proactively; the user must initiate the action
  /// themselves via an always-available control.
  manual,
}
