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

  /// Coding-execution verify-gate retry — whether a `flutter analyze`
  /// failure feeds back for an automatic corrective turn, asks first, or
  /// waits for a manual retry. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`; see
  /// `TicketsCubit._runCodingExecution`.
  codingExecutionRetry,
}
