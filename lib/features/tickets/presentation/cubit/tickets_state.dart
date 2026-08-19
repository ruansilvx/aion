// presentation/cubit/tickets_state.dart — TicketsState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/backlink_ref.dart';
import 'package:aion/features/tickets/domain/entities/gap_or_question_ref.dart';
import 'package:aion/features/tickets/domain/entities/linked_ticket_ref.dart';
import 'package:aion/features/tickets/domain/entities/skill_attachment.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/presentation/cubit/pending_tool_proposal.dart';

/// The state emitted by [TicketsCubit].
sealed class TicketsState extends Equatable {
  const TicketsState();

  @override
  List<Object?> get props => [];
}

/// Before [TicketsCubit.loadTickets] or [TicketsCubit.getTicketById] has
/// been called. Nothing to render but an empty shell.
class TicketsInitial extends TicketsState {
  /// Creates a [TicketsInitial] state.
  const TicketsInitial();
}

/// A list or detail fetch is in flight. UI should show [AppSpinner].
class TicketsLoading extends TicketsState {
  /// Creates a [TicketsLoading] state.
  const TicketsLoading();
}

/// The ticket list loaded successfully. Carries the page to render.
class TicketsLoaded extends TicketsState {
  /// Creates a [TicketsLoaded] state carrying [tickets] and [hasMore].
  const TicketsLoaded(
    this.tickets, {
    required this.hasMore,
    this.inFlightExecutionIds = const {},
    this.executionQueuePositions = const {},
    this.inFlightAdvanceIds = const {},
    this.blockedTicketIds = const {},
    this.pendingResumePrompt = const [],
    this.executionTokenTotals = const {},
  });

  /// The tickets loaded so far, most recently created first (or by
  /// relevance, when a text query is active).
  final List<Ticket> tickets;

  /// Whether at least one more page exists beyond [tickets] —
  /// [TicketsCubit.loadMoreTickets] no-ops when this is `false`.
  final bool hasMore;

  /// Task/Bug ids with a coding-execution run currently in flight —
  /// mirrors [TicketsCubit._inFlightExecutionTaskId] as a set so the
  /// Board (`TicketBoardCard`) can look up a specific ticket's status
  /// without calling [TicketsCubit.getTicketById] per card. Recomputed by
  /// [TicketsCubit._refreshInFlightBoardState]. Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  final Set<String> inFlightExecutionIds;

  /// Task/Bug ids waiting on [TicketsCubit._executionQueue], mapped to
  /// their 1-based queue position. Recomputed by
  /// [TicketsCubit._refreshInFlightBoardState]. Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  final Map<String, int> executionQueuePositions;

  /// Epic/Story ids (and their in-flight stage chat's own id) currently
  /// mid-`advanceSddStage` — mirrors
  /// [TicketsCubit._inFlightStageAdvanceIds]. Recomputed by
  /// [TicketsCubit._refreshInFlightBoardState]. Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  final Set<String> inFlightAdvanceIds;

  /// Work-ticket (epic/story/task/bug) ids with an unresolved
  /// `blocks`/`blockedBy` relationship — the ticket that blocks them
  /// exists, is live, and isn't currently at a status holding
  /// `WorkflowStatusRole.done` yet. Recomputed by
  /// [TicketsCubit._computeBlockedTicketIds] from persisted link data
  /// (not in-memory/ephemeral, unlike [inFlightExecutionIds] and its
  /// siblings above). Drives the Board's `_BlockedBadge`. Added for
  /// `aion-arch/changes/board-task-ordering-indication`.
  final Set<String> blockedTicketIds;

  /// Interrupted coding-execution runs found on this launch under
  /// [AutomationConfidence](../../../../core/automation/automation_confidence.dart)
  /// `.gated`, awaiting a Resume/Dismiss decision — drives
  /// `ResumeRunsPrompt`, the one-time-per-launch banner pinned to the top
  /// of the Board view. Recomputed by
  /// [TicketsCubit._refreshInFlightBoardState] from
  /// [TicketsCubit._pendingResumeTickets] (populated by
  /// [TicketsCubit.restoreExecutionQueue], cleared by
  /// [TicketsCubit.resumePendingExecutions]/
  /// [TicketsCubit.dismissPendingResumePrompt]). Added for
  /// `aion-arch/changes/parallel-work`.
  final List<Ticket> pendingResumePrompt;

  /// Task/Bug id → total coding-execution token spend recorded so far
  /// (summed `inputTokens + outputTokens` across every
  /// `"Coding Execution — "`-prefixed child chat's comments), mirroring
  /// [TicketsCubit._executionTokenTotals]. An id absent from this map has
  /// no recorded execution spend yet — `TokenCountLabel`'s Board-card
  /// display precedence (see `_cardTokenLabel`) falls back to the
  /// ticket's own `predictedExecutionTokensLow`/`High` in that case.
  /// Recomputed by [TicketsCubit._refreshInFlightBoardState]. Added for
  /// `aion-arch/changes/token-cost-prediction`.
  final Map<String, int> executionTokenTotals;

  @override
  List<Object?> get props => [
    tickets,
    hasMore,
    inFlightExecutionIds,
    executionQueuePositions,
    inFlightAdvanceIds,
    blockedTicketIds,
    pendingResumePrompt,
    executionTokenTotals,
  ];
}

/// A [TicketsCubit.loadMoreTickets] call is in flight. Carries the tickets
/// loaded so far (unchanged) so the list stays fully visible with a
/// bottom-of-list spinner, rather than blanking out mid-scroll.
class TicketsLoadingMore extends TicketsState {
  /// Creates a [TicketsLoadingMore] state carrying the already-loaded
  /// [tickets].
  const TicketsLoadingMore(this.tickets);

  /// The tickets loaded before this page request started.
  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

/// A [TicketsCubit.loadMoreTickets] call failed. Carries the tickets
/// loaded before the failed attempt (unchanged — a failed load-more never
/// discards what's already on screen) and the [hasMore] value from before
/// the attempt, so the UI can offer a retry rather than silently treating
/// this as the end of the list.
class TicketsLoadMoreFailed extends TicketsState {
  /// Creates a [TicketsLoadMoreFailed] state carrying [tickets] and
  /// [hasMore].
  const TicketsLoadMoreFailed(this.tickets, {required this.hasMore});

  /// The tickets loaded before the failed load-more attempt.
  final List<Ticket> tickets;

  /// Whether another page might still exist — carried over from the state
  /// before the failed attempt, since the failure itself provides no new
  /// information about how many results remain.
  final bool hasMore;

  @override
  List<Object?> get props => [tickets, hasMore];
}

/// Categorizes a [TicketsError] so it can be localized at the widget layer
/// (via `ticketsErrorMessage` in `tickets_board_view.dart`) without
/// [TicketsCubit] needing a [BuildContext]. `null` on [TicketsError.reason]
/// means the error carries only a raw, unlocalized [TicketsError.message]
/// (e.g. a forwarded repository exception) — see [TicketsError].
enum TicketsErrorReason {
  /// The requested ticket does not exist.
  notFound,

  /// Reassigning a ticket's parent was rejected because the chosen parent
  /// is the ticket itself or one of its own descendants (would create a
  /// cycle). The widget layer reads this via `ticketsErrorMessage` /
  /// `AppToast`.
  invalidParent,

  /// [TicketsCubit.advanceSddStage] was rejected because the ticket's
  /// type can't have an SDD stage, or the current stage's precondition
  /// for advancing to the next one isn't met yet. The widget layer reads
  /// this via `ticketsErrorMessage` / `AppToast`.
  sddStagePreconditionNotMet,

  /// A Task ticket was rejected from moving to a status holding
  /// `WorkflowStatusRole.executionTrigger` because its governing Story's
  /// design work is outstanding — see
  /// `TicketsCubit._codingExecutionGateCheck`. The widget layer reads
  /// this via `ticketsErrorMessage` / `AppToast`.
  codingExecutionBlocked,

  /// A coding-execution run reported `AgentOverageDetectedEvent` — every
  /// subsequent trigger for the rest of the session is forced to
  /// `AutomationConfidence.gated` regardless of the configured
  /// confidence. Informational, surfaced once via `AppToast`.
  executionBudgetOverageDetected,

  /// A coding-execution run's agentic verify turn reported
  /// `VERIFICATION: FAILED` and the effective
  /// `AutomationContext.codingExecutionRetry` confidence is
  /// `gated` (or `auto` with its retry cap exhausted, forced to `gated`
  /// visibility) — surfaced once via `AppToast`, alongside the Task
  /// detail screen's failure banner. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`.
  executionVerificationFailed,

  /// A spawned SDD-stage chat's turn (see `TicketsCubit
  /// ._runStageChatTurn`) hard-failed. Informational, surfaced once via
  /// `AppToast`, alongside the Epic/Story detail screen's failure banner
  /// (`TicketDetailLoaded.sddStageFailureReason`). Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  sddStageAdvanceFailed,

  /// A ticket was rejected from moving to a status holding
  /// `WorkflowStatusRole.executionTrigger` because it has an unresolved
  /// `blocks`/`blockedBy` dependency — see
  /// `TicketsCubit._isTicketBlocked`. Applies to every ticket type,
  /// unlike [codingExecutionBlocked]. The widget layer reads this via
  /// `ticketsErrorMessage` / `AppToast`. Added for
  /// `aion-arch/changes/blocked-ticket-transition-gate`.
  blockedByOpenDependency,
}

/// Why a Task ticket's coding-execution run was blocked from starting —
/// resolved to a rejection toast at the widget layer (via
/// [TicketsErrorReason.codingExecutionBlocked] /
/// `ticketsErrorMessage`), not a persistent hint, since the block
/// prevents the status transition itself from happening at all. Computed
/// by `TicketsCubit._codingExecutionGateCheck`.
enum CodingExecutionBlockReason {
  /// The Task's governing Story indicates UI work and that work hasn't
  /// been design-approved yet (`_designSyncApproved` is `false`).
  storyDesignGatePending,
}

/// Why an `epic`/`story` [TicketDetailLoaded.ticket]'s current
/// [SddStage](../../domain/enums/sdd_stage.dart) precondition isn't met
/// yet — resolved to localized hint text at the widget layer (the
/// `_SddStageSection` "Not ready" state, per
/// `aion-arch/changes/sdd-ticket-execution/design.md` §2.2), mirroring
/// how [TicketsErrorReason] is resolved via `ticketsErrorMessage`. `null`
/// on [TicketDetailLoaded.sddStageBlockReason] means either the ticket
/// can already advance ([TicketDetailLoaded.canAdvanceSddStage] is
/// `true`), or there's nothing left to advance to (not an epic/story, or
/// already [SddStage.archived]).
enum SddStageBlockReason {
  /// The current stage's most recently created `chat` child doesn't have
  /// an AI reply yet (or no `chat` child exists yet).
  awaitingChatReply,

  /// Not every direct child at the next rank down (Tasks for a story,
  /// Stories for an epic) has reached a terminal state yet — or none
  /// exist yet.
  awaitingChildren,

  /// [SddStage.designBrief]'s linked design Page ticket doesn't have any
  /// pasted content yet. Added for `aion-arch/changes/sdd-design-gate`.
  awaitingDesignPaste,

  /// [SddStage.designSync]'s chat hasn't produced a `"DESIGN GATE:
  /// APPROVED"` reply yet — either no reply exists, or the most recent
  /// one says `PENDING`. Added for `aion-arch/changes/sdd-design-gate`.
  awaitingDesignApproval,
}

/// A list, detail, or create operation failed. Carries either a classified
/// [reason] — resolved to localized text at the widget layer — or a raw,
/// unlocalized [message] (e.g. a forwarded repository exception) when no
/// more specific reason applies. [reason] takes precedence over [message]
/// for display whenever it's non-null.
class TicketsError extends TicketsState {
  /// Creates a [TicketsError] state. Pass [reason] for a classified,
  /// localizable error; otherwise [message] is shown as-is.
  const TicketsError(this.message, {this.reason});

  /// A raw, unlocalized description of what went wrong. Ignored in favor
  /// of [reason] when [reason] is non-null.
  final String message;

  /// A classified error reason, if this error corresponds to a known,
  /// localizable case. `null` for generic/forwarded exceptions.
  final TicketsErrorReason? reason;

  @override
  List<Object?> get props => [message, reason];
}

/// A [TicketsCubit.createTicket] call is in flight. Carries the
/// previously-loaded list so the list screen stays visible during creation.
class TicketCreating extends TicketsState {
  /// Creates a [TicketCreating] state carrying the in-flight [tickets] list.
  const TicketCreating(this.tickets);

  /// The list as it was before this creation started.
  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

/// A ticket was created successfully. Carries the refreshed page (including
/// the new ticket) so the UI can navigate back and show it immediately.
class TicketCreated extends TicketsState {
  /// Creates a [TicketCreated] state carrying the refreshed [tickets] and
  /// [hasMore].
  const TicketCreated(this.tickets, {required this.hasMore});

  /// The refreshed tickets, including the newly created ticket.
  final List<Ticket> tickets;

  /// Whether at least one more page exists beyond [tickets].
  final bool hasMore;

  @override
  List<Object?> get props => [tickets, hasMore];
}

/// A [TicketsCubit.updateTicketStatus] call is in flight. Carries the
/// ticket list with the in-flight ticket's status already replaced
/// locally (optimistic), so a board drag/move reflects instantly instead
/// of waiting on the repository round trip.
class TicketStatusUpdating extends TicketsState {
  /// Creates a [TicketStatusUpdating] state carrying the optimistically
  /// updated [tickets] list.
  const TicketStatusUpdating(this.tickets);

  /// The list with the moved ticket's status already changed locally.
  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

/// A ticket's status change persisted successfully. Carries the page
/// re-fetched from the repository, which supersedes the optimistic copy
/// carried by the preceding [TicketStatusUpdating] state.
class TicketStatusUpdated extends TicketsState {
  /// Creates a [TicketStatusUpdated] state carrying the refreshed
  /// [tickets] and [hasMore].
  const TicketStatusUpdated(this.tickets, {required this.hasMore});

  /// The tickets, re-fetched after the status change persisted.
  final List<Ticket> tickets;

  /// Whether at least one more page exists beyond [tickets].
  final bool hasMore;

  @override
  List<Object?> get props => [tickets, hasMore];
}

/// A single ticket's detail loaded successfully. Carries that ticket.
class TicketDetailLoaded extends TicketsState {
  /// Creates a [TicketDetailLoaded] state carrying [ticket] and, once
  /// [TicketsCubit.loadDocumentRelations] resolves, its Documentation-
  /// section relations.
  const TicketDetailLoaded(
    this.ticket, {
    this.childDocs = const [],
    this.linkedTickets = const [],
    this.backlinks = const [],
    this.gapsAndOpenQuestions = const [],
    this.canAdvanceSddStage = false,
    this.sddStageBlockReason,
    this.needsDesignReview,
    this.linkedDesignPage,
    this.isExecuting = false,
    this.executionQueuePosition,
    this.executionAwaitingReview = false,
    this.executionFailureReason,
    this.executionCanRetry = false,
    this.executionLiveActivity,
    this.isAdvancingStage = false,
    this.sddStageFailureReason,
    this.sddStageCanRetry = false,
    this.pendingToolProposal,
    this.executionTokenTotal,
    this.pendingSkillAttachment,
  });

  /// The loaded ticket.
  final Ticket ticket;

  /// [ticket]'s direct `page`/`resource` children, populated only when
  /// [ticket] is a `page` (resources never have children). Empty until
  /// [TicketsCubit.loadDocumentRelations] resolves.
  final List<Ticket> childDocs;

  /// Board tickets (epic/story/task/chat) linked to [ticket] via
  /// `TicketLink`, populated only when [ticket] is `page`/`resource`.
  /// Each entry pairs the other-side [Ticket] with the link's type *as it
  /// reads from [ticket]'s own side* and the underlying link row's id —
  /// see [LinkedTicketRef]. Empty until
  /// [TicketsCubit.loadDocumentRelations] resolves.
  final List<LinkedTicketRef> linkedTickets;

  /// Other `page`/`resource` tickets that reference [ticket], either via
  /// an explicit `TicketLink` or an inline `[[wikilink]]` — see
  /// [TicketsCubit.loadDocumentRelations]'s dartdoc for the merge/scoping
  /// rationale and [BacklinkRef.origin]. Was `List<LinkedTicketRef>`
  /// (`TicketLink`-only) before
  /// `aion-arch/changes/inline-wikilink-backlinks`. Empty until
  /// [TicketsCubit.loadDocumentRelations] resolves.
  final List<BacklinkRef> backlinks;

  /// Every `knownGap`/`openQuestion` ticket `relatesTo`-linked to [ticket]
  /// itself or to any descendant of it, recursively rolled up — see
  /// [GapOrQuestionRef]. Populated only for the same gated types
  /// `linkedTickets`/`backlinks` use (`epic`/`story`/`task`/`bug`/
  /// `resource`/`page`). Empty until
  /// [TicketsCubit.loadDocumentRelations] resolves. Added for
  /// `aion-arch/changes/idea-gap-question-ticket-types`.
  final List<GapOrQuestionRef> gapsAndOpenQuestions;

  /// Whether [ticket] (an `epic`/`story`) currently satisfies the
  /// precondition for `TicketsCubit.advanceSddStage` to succeed.
  /// Computed by [TicketsCubit.getTicketById] from [ticket]'s direct
  /// children; always `false` for every other ticket type.
  final bool canAdvanceSddStage;

  /// Why [canAdvanceSddStage] is `false`, for the "Not ready" hint row —
  /// `null` whenever [canAdvanceSddStage] is `true`, or [ticket] has
  /// nothing left to advance to. Computed by
  /// [TicketsCubit.getTicketById] alongside [canAdvanceSddStage].
  final SddStageBlockReason? sddStageBlockReason;

  /// Whether [ticket] (a `story`) needs a `designBrief`/`designSync`
  /// pass, computed by [TicketsCubit.getTicketById] from its current
  /// child Tasks via `_storyNeedsDesignReview`. `null` until child Tasks
  /// exist to evaluate, or for any ticket type other than `story`. Drives
  /// `_SddStageSection`'s variable-length tracker (4 vs. 6 nodes). Added
  /// for `aion-arch/changes/sdd-design-gate`.
  final bool? needsDesignReview;

  /// [ticket]'s linked design Page (a `story`'s `"Design — <title>"`
  /// `page`-type ticket, created by `TicketsCubit._spawnStageChat`'s
  /// `designBrief` branch), computed by [TicketsCubit.getTicketById] via
  /// the same lookup `_linkedDesignPage` uses internally for the
  /// `designBrief`/`designSync` precondition checks. `null` when
  /// [needsDesignReview] isn't `true`, or the design Page hasn't been
  /// created yet. Added for `aion-arch/changes/sdd-design-gate`.
  final Ticket? linkedDesignPage;

  /// Whether [ticket] (a `task`) is the coding-execution run currently
  /// in flight. Task-only, computed by [TicketsCubit.getTicketById] from
  /// `_inFlightExecutionTaskId`. Always `false` for every other ticket
  /// type. Added for `aion-arch/changes/task-to-coding-execution-trigger`.
  final bool isExecuting;

  /// [ticket]'s (a `task`) 1-based position in the coding-execution FIFO
  /// queue, or `null` if it isn't queued. Task-only, computed by
  /// [TicketsCubit.getTicketById]. Added for
  /// `aion-arch/changes/task-to-coding-execution-trigger`.
  final int? executionQueuePosition;

  /// Whether [ticket] (a `task`) has a finished coding-execution run with
  /// a confirmed PR, awaiting human confirmation
  /// (`AutomationConfidence.gated`) before flipping to the status holding
  /// `WorkflowStatusRole.reviewReady`. Task-only, computed by
  /// [TicketsCubit.getTicketById]. Added for
  /// `aion-arch/changes/task-to-coding-execution-trigger`.
  final bool executionAwaitingReview;

  /// Why [ticket] (a `task`) is showing a coding-execution failure state —
  /// an agentic verify-turn failure (with its reported reason), a
  /// hard run error, or a fixed "ended without a clear result" message for
  /// an orphaned/stalled run (e.g. after an app restart mid-run). `null`
  /// when the run hasn't failed. Task-only, computed by
  /// [TicketsCubit.getTicketById] from the most recent execution chat's
  /// most recent comment — unlike [isExecuting]/[executionQueuePosition],
  /// this survives an app restart, since it's derived from the persisted
  /// comment thread rather than in-memory queue state. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`.
  final String? executionFailureReason;

  /// Whether [executionFailureReason] has a retry action available —
  /// always `true` whenever [executionFailureReason] is non-`null`, kept
  /// as a separate field so the widget layer doesn't need to null-check
  /// [executionFailureReason] to decide whether to show the retry button.
  /// Added for `aion-arch/changes/coding-execution-reliability-and-safety`.
  final bool executionCanRetry;

  /// A live "Running `<tool>`..."-style status string for [ticket] (a
  /// `task`) while [isExecuting] is `true`, re-emitted by
  /// [TicketsCubit._runCodingExecution] on every tool call/text chunk of
  /// the in-flight run (only while this Task's detail screen is the one
  /// showing), and cleared once the run finishes. `null` whenever
  /// [isExecuting] is `false`, or no tool call has happened yet. In-memory
  /// only — does not survive an app restart, like [isExecuting] itself.
  /// Added for `aion-arch/changes/coding-execution-reliability-and-safety`.
  final String? executionLiveActivity;

  /// Whether [ticket] (an `epic`/`story`) has an
  /// [TicketsCubit.advanceSddStage] chat spawn currently in flight, or
  /// [ticket] (a `chat`) *is* that in-flight spawn's own chat ticket.
  /// Computed by [TicketsCubit.getTicketById] from
  /// [TicketsCubit._inFlightStageAdvanceIds]. Mirrors [isExecuting]'s
  /// shape exactly, one level up the ticket-type hierarchy. Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  final bool isAdvancingStage;

  /// Why [ticket]'s (an `epic`/`story`) most recent stage-advance
  /// attempt failed, `null` if it hasn't or the current attempt is still
  /// running. Survives an app restart — derived from the persisted
  /// comment thread, like [executionFailureReason]. Computed by
  /// [TicketsCubit.getTicketById] via
  /// [TicketsCubit._computeStageAdvanceFailure]. Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  final String? sddStageFailureReason;

  /// Whether [sddStageFailureReason] has a retry action available —
  /// always `true` whenever [sddStageFailureReason] is non-`null`. Added
  /// for `aion-arch/changes/board-execution-indicators-and-notifications`.
  final bool sddStageCanRetry;

  /// A `branch_ticket`/`close_branch` tool call awaiting user confirmation
  /// on [ticket] (a `chat`), while
  /// `TicketsCubit._awaitProposalConfirmation` holds the underlying model
  /// run paused (`AutomationConfidence.gated`). `null` whenever no such
  /// call is pending. Drives `_ToolProposalBanner`. Added for
  /// `aion-arch/changes/mid-task-chat-branching`; see that change's
  /// design.md §8.
  final PendingToolProposal? pendingToolProposal;

  /// [ticket]'s (a `task`/`bug`) total coding-execution token spend
  /// recorded so far — see `TicketsLoaded.executionTokenTotals`'s dartdoc
  /// for the exact accumulation rule. `null` means no execution turn has
  /// completed yet, in which case `TicketMetadataSection` falls back to
  /// showing [ticket]'s own `predictedExecutionTokensLow`/`High` instead.
  /// Computed by [TicketsCubit.getTicketById] from
  /// [TicketsCubit._executionTokenTotals]. Added for
  /// `aion-arch/changes/token-cost-prediction`.
  final int? executionTokenTotal;

  /// A `SkillAttachment` (confidence `gated`) awaiting user confirmation
  /// on [ticket] — [ticket] just entered the `WorkflowStatus`/[SddStage]
  /// this attachment is configured for. `null` whenever no such
  /// attachment is pending. Drives `_PendingSkillAttachmentBanner`.
  /// Mirrors [pendingToolProposal]'s exact shape. Added for
  /// `aion-arch/changes/workflow-skill-attachments`.
  final SkillAttachment? pendingSkillAttachment;

  @override
  List<Object?> get props => [
    ticket,
    childDocs,
    linkedTickets,
    backlinks,
    gapsAndOpenQuestions,
    canAdvanceSddStage,
    sddStageBlockReason,
    needsDesignReview,
    linkedDesignPage,
    isExecuting,
    executionQueuePosition,
    executionAwaitingReview,
    executionFailureReason,
    executionCanRetry,
    executionLiveActivity,
    isAdvancingStage,
    sddStageFailureReason,
    sddStageCanRetry,
    pendingToolProposal,
    executionTokenTotal,
    pendingSkillAttachment,
  ];

  /// Returns a copy of this state with the given fields replaced; every
  /// omitted field is carried over unchanged. Used wherever a single
  /// field (typically [isAdvancingStage] or [pendingSkillAttachment])
  /// needs to change without discarding the rest of an already-loaded
  /// detail screen's computed state — [TicketsCubit.advanceSddStage],
  /// [TicketsCubit._resolveAndFireAttachment],
  /// [TicketsCubit.confirmPendingSkillAttachment], and
  /// [TicketsCubit.rejectPendingSkillAttachment] all previously
  /// reconstructed a bare `TicketDetailLoaded(ticket)` instead, silently
  /// resetting every other field (`childDocs`, `gapsAndOpenQuestions`,
  /// `canAdvanceSddStage`, `isExecuting`, etc.) to its default the moment
  /// a skill attachment fired or was confirmed/rejected — fixed by
  /// routing those four call sites through this method instead. Every
  /// field but [pendingSkillAttachment] follows the simple
  /// "omit to leave unchanged" convention (a plain nullable parameter,
  /// substituted via `??`) since no current caller needs to explicitly
  /// clear any of them back to `null`. [pendingSkillAttachment] is the
  /// one field callers genuinely need to clear (on confirm/reject), so
  /// it alone takes a [TicketFieldSetter] — mirrors [Ticket.copyWith]'s
  /// own convention for the same omitted-vs-explicitly-null distinction:
  /// pass `() => null` to clear it, or omit the parameter to leave it
  /// unchanged. Added for `aion-arch/changes/workflow-skill-attachments`.
  TicketDetailLoaded copyWith({
    Ticket? ticket,
    List<Ticket>? childDocs,
    List<LinkedTicketRef>? linkedTickets,
    List<BacklinkRef>? backlinks,
    List<GapOrQuestionRef>? gapsAndOpenQuestions,
    bool? canAdvanceSddStage,
    SddStageBlockReason? sddStageBlockReason,
    bool? needsDesignReview,
    Ticket? linkedDesignPage,
    bool? isExecuting,
    int? executionQueuePosition,
    bool? executionAwaitingReview,
    String? executionFailureReason,
    bool? executionCanRetry,
    String? executionLiveActivity,
    bool? isAdvancingStage,
    String? sddStageFailureReason,
    bool? sddStageCanRetry,
    PendingToolProposal? pendingToolProposal,
    int? executionTokenTotal,
    TicketFieldSetter<SkillAttachment?>? pendingSkillAttachment,
  }) {
    return TicketDetailLoaded(
      ticket ?? this.ticket,
      childDocs: childDocs ?? this.childDocs,
      linkedTickets: linkedTickets ?? this.linkedTickets,
      backlinks: backlinks ?? this.backlinks,
      gapsAndOpenQuestions: gapsAndOpenQuestions ?? this.gapsAndOpenQuestions,
      canAdvanceSddStage: canAdvanceSddStage ?? this.canAdvanceSddStage,
      sddStageBlockReason: sddStageBlockReason ?? this.sddStageBlockReason,
      needsDesignReview: needsDesignReview ?? this.needsDesignReview,
      linkedDesignPage: linkedDesignPage ?? this.linkedDesignPage,
      isExecuting: isExecuting ?? this.isExecuting,
      executionQueuePosition:
          executionQueuePosition ?? this.executionQueuePosition,
      executionAwaitingReview:
          executionAwaitingReview ?? this.executionAwaitingReview,
      executionFailureReason:
          executionFailureReason ?? this.executionFailureReason,
      executionCanRetry: executionCanRetry ?? this.executionCanRetry,
      executionLiveActivity:
          executionLiveActivity ?? this.executionLiveActivity,
      isAdvancingStage: isAdvancingStage ?? this.isAdvancingStage,
      sddStageFailureReason:
          sddStageFailureReason ?? this.sddStageFailureReason,
      sddStageCanRetry: sddStageCanRetry ?? this.sddStageCanRetry,
      pendingToolProposal: pendingToolProposal ?? this.pendingToolProposal,
      executionTokenTotal: executionTokenTotal ?? this.executionTokenTotal,
      pendingSkillAttachment: pendingSkillAttachment != null
          ? pendingSkillAttachment()
          : this.pendingSkillAttachment,
    );
  }
}

/// A [TicketsCubit.trashTicket] call is in flight (single ticket,
/// triggered from `TicketOverflowMenu`).
class TicketTrashing extends TicketsState {
  /// Creates a [TicketTrashing] state.
  const TicketTrashing();
}

/// A single ticket was moved to trash successfully. Carries no data —
/// `TicketDetailScreen` responds by navigating back to `/tickets`, where
/// [TicketsCubit.loadTickets]/`searchTickets` re-fetches the now-shorter
/// (trash-excluded) list.
class TicketTrashed extends TicketsState {
  /// Creates a [TicketTrashed] state.
  const TicketTrashed();
}

/// A [TicketsCubit.trashTickets] batch call is in flight (bulk,
/// triggered from `TicketSelectionBar`).
class TicketsBatchTrashing extends TicketsState {
  /// Creates a [TicketsBatchTrashing] state.
  const TicketsBatchTrashing();
}

/// A batch trash call completed. Carries the refreshed page, the total
/// number of tickets actually moved (>= the original selection size, once
/// cascaded descendants are included) so the widget layer can show an
/// accurate summary toast, and [hasMore].
class TicketsBatchTrashed extends TicketsState {
  /// Creates a [TicketsBatchTrashed] state carrying the refreshed
  /// [tickets], the [trashedCount], and [hasMore].
  const TicketsBatchTrashed(
    this.tickets,
    this.trashedCount, {
    required this.hasMore,
  });

  /// The tickets, re-fetched after the batch trash completed.
  final List<Ticket> tickets;

  /// How many tickets were actually moved to trash, including cascaded
  /// descendants.
  final int trashedCount;

  /// Whether at least one more page exists beyond [tickets].
  final bool hasMore;

  @override
  List<Object?> get props => [tickets, trashedCount, hasMore];
}

/// A [TicketsCubit.updateStatusForTickets] batch call is in flight (bulk,
/// triggered from `TicketSelectionBar`'s Status action).
class TicketsBatchStatusUpdating extends TicketsState {
  /// Creates a [TicketsBatchStatusUpdating] state.
  const TicketsBatchStatusUpdating();
}

/// A batch status-change call completed. Carries the refreshed page, how
/// many tickets were actually written ([updatedCount]), and how many were
/// silently skipped ([skippedCount]) because moving to a status holding
/// `WorkflowStatusRole.executionTrigger` would have been rejected by the
/// Blocked-dependency gate or the coding-execution gate (see
/// [TicketsCubit._isTicketBlocked]/[TicketsCubit._codingExecutionGateCheck]).
/// [skippedCount] is always 0 for any target status not holding that role,
/// since neither gate applies. The widget layer surfaces both counts via a
/// summary toast.
class TicketsBatchStatusUpdated extends TicketsState {
  /// Creates a [TicketsBatchStatusUpdated] state carrying the refreshed
  /// [tickets], [updatedCount], [skippedCount], and [hasMore].
  const TicketsBatchStatusUpdated(
    this.tickets,
    this.updatedCount,
    this.skippedCount, {
    required this.hasMore,
  });

  /// The tickets, re-fetched after the batch status change completed.
  final List<Ticket> tickets;

  /// How many tickets were actually written.
  final int updatedCount;

  /// How many tickets were silently skipped by a gate rejection.
  final int skippedCount;

  /// Whether at least one more page exists beyond [tickets].
  final bool hasMore;

  @override
  List<Object?> get props => [tickets, updatedCount, skippedCount, hasMore];
}

/// A [TicketsCubit.updatePriorityForTickets] batch call is in flight (bulk,
/// triggered from `TicketSelectionBar`'s Priority action).
class TicketsBatchPriorityUpdating extends TicketsState {
  /// Creates a [TicketsBatchPriorityUpdating] state.
  const TicketsBatchPriorityUpdating();
}

/// A batch priority-change call completed. Carries the refreshed page and
/// how many tickets were updated ([updatedCount]) — always equal to the
/// original selection size, since priority has no rejection path (unlike
/// [TicketsBatchStatusUpdated.skippedCount]).
class TicketsBatchPriorityUpdated extends TicketsState {
  /// Creates a [TicketsBatchPriorityUpdated] state carrying the refreshed
  /// [tickets], [updatedCount], and [hasMore].
  const TicketsBatchPriorityUpdated(
    this.tickets,
    this.updatedCount, {
    required this.hasMore,
  });

  /// The tickets, re-fetched after the batch priority edit completed.
  final List<Ticket> tickets;

  /// How many tickets were updated — always equal to the original
  /// selection size.
  final int updatedCount;

  /// Whether at least one more page exists beyond [tickets].
  final bool hasMore;

  @override
  List<Object?> get props => [tickets, updatedCount, hasMore];
}
