// core/automation/automation_context.dart — AutomationContext enum (core layer).

/// The distinct automated decision points that share the
/// [AutomationSettingsRepository] `auto | gated | manual` pattern, each
/// persisted under its own key so choosing a confidence for one never
/// affects another.
enum AutomationContext {
  /// SDD-stage-triggering — see `TicketsCubit.advanceSddStage`.
  sddStage,

  /// Coding-execution completion — see `TicketsCubit._runCodingExecution`.
  codingExecution,
}
