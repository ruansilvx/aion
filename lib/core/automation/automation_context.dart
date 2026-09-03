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

  /// Coding-execution verify-gate retry — whether a failed agentic verify turn
  /// feeds back for an automatic corrective turn, asks first, or waits for a
  /// manual retry. Added for `AIO-506`; see
  /// `TicketsCubit._runCodingExecution`.
  codingExecutionRetry,

  /// Mid-task/issue chat branching — whether the model's `branch_ticket`/
  /// `close_branch` tool calls run immediately, wait for user confirmation, or
  /// are declined outright. Governs both tools symmetrically (one setting, not
  /// two). Added for `AIO-1118`; see
  /// `TicketsCubit._handleBranchToolCall`/`_handleCloseBranchToolCall`.
  chatBranching,

  /// Restart recovery for interrupted coding-execution runs — whether a
  /// Task/Bug left `inProgress` by an app restart resumes silently
  /// ([AutomationConfidence.auto]), asks first ([AutomationConfidence.gated]),
  /// or is left for the existing orphaned/stalled failure-banner retry path
  /// ([AutomationConfidence.manual]). Added for `AIO-1400`; see
  /// `TicketsCubit.restoreExecutionQueue`.
  codingExecutionResume,

  /// Model-initiated ticket creation via the `create_ticket` tool call —
  /// whether a new top-level `story`/`task`/`bug` is created immediately, asks
  /// for confirmation first, or is declined outright. Added for `AIO-2108`;
  /// see `TicketsCubit._handleCreateTicketToolCall`.
  ticketCreation,

  /// Model-initiated ticket linking via the `add_link` tool call (including
  /// duplicate-flagging, expressed as `linkType: duplicates`) — whether the
  /// link is created immediately, asks for confirmation first, or is declined
  /// outright. Added for `AIO-2108`; see
  /// `TicketsCubit._handleAddLinkToolCall`.
  ticketLinking,

  /// Auto-linking a fresh `knownGap`/`openQuestion` or a `bug` reaching a
  /// `done`-role status to the most similar existing `TicketType.spec` ticket
  /// — whether the link is created immediately, asks for confirmation first,
  /// or is declined outright (a manual "Link to spec" action remains available
  /// regardless). Added for `AIO-1998`; see
  /// `TicketsCubit._maybeAutoLinkToSpec`.
  specAutoLink,

  /// SDD-stage verify-gate retry — whether, once every fix Task/Bug a
  /// `VERIFY GATE: PENDING` verdict spawned has reached `done`, a fresh
  /// verification turn fires automatically, asks first, or waits for the
  /// existing manual "Retry validation" action. Distinct from [sddStage]
  /// (which governs advancing *once already eligible*, not re-attempting an
  /// unmet gate). Added for `AIO-1905`; see
  /// `TicketsCubit._maybeRetryPendingVerify`.
  verifyGateRetry,
}
