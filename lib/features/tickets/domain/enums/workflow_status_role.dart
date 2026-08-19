// domain/enums/workflow_status_role.dart — WorkflowStatusRole enum (domain layer).

/// The semantic slot a [WorkflowStatus](../entities/workflow_status.dart)
/// fills in `TicketsCubit`'s existing gate/trigger logic — the generalized
/// replacement for literal `TicketStatus.inProgress`/`.inReview`/`.done`
/// comparisons from before this ticket-workflow-configuration change.
/// Exactly one shared-base [WorkflowStatus] must hold each value at all
/// times; [WorkflowConfigCubit](../../presentation/cubit/workflow_config_cubit.dart)
/// enforces this invariant, never the repository — see
/// `aion-arch/changes/configurable-ticket-workflow/design.md` §1.1.
enum WorkflowStatusRole {
  /// Fills the pre-configuration `TicketStatus.inProgress` slot: the
  /// transition that starts coding execution
  /// (`TicketsCubit._interceptTaskExecutionTrigger`) and that the
  /// blocked-dependency gate (`TicketsCubit._interceptBlockedDependencyTrigger`)
  /// checks against.
  executionTrigger,

  /// Fills the pre-configuration `TicketStatus.inReview` slot: the status
  /// a successful coding-execution run auto-writes to when
  /// `AutomationConfidence.auto` (`TicketsCubit._runCodingExecution`'s
  /// PR-confirmed path).
  reviewReady,

  /// Fills the pre-configuration `TicketStatus.done` slot: what the
  /// blocked-dependency gate's blocker-resolution check and
  /// `SddStage.proposed`/`designSync`'s children-completion checks
  /// require.
  done,
}
