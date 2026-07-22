// presentation/cubit/tickets_state.dart — TicketsState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';

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
  const TicketsLoaded(this.tickets, {required this.hasMore});

  /// The tickets loaded so far, most recently created first (or by
  /// relevance, when a text query is active).
  final List<Ticket> tickets;

  /// Whether at least one more page exists beyond [tickets] —
  /// [TicketsCubit.loadMoreTickets] no-ops when this is `false`.
  final bool hasMore;

  @override
  List<Object?> get props => [tickets, hasMore];
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
    this.canAdvanceSddStage = false,
    this.sddStageBlockReason,
    this.needsDesignReview,
    this.linkedDesignPage,
  });

  /// The loaded ticket.
  final Ticket ticket;

  /// [ticket]'s direct `page`/`resource` children, populated only when
  /// [ticket] is a `page` (resources never have children). Empty until
  /// [TicketsCubit.loadDocumentRelations] resolves.
  final List<Ticket> childDocs;

  /// Board tickets (epic/story/task/chat) linked to [ticket] via
  /// `TicketLink`, populated only when [ticket] is `page`/`resource`.
  /// Empty until [TicketsCubit.loadDocumentRelations] resolves.
  final List<Ticket> linkedTickets;

  /// Other `page`/`resource` tickets linked to [ticket] via `TicketLink`
  /// (see [TicketsCubit.loadDocumentRelations]'s dartdoc for the scoping
  /// rationale). Empty until [TicketsCubit.loadDocumentRelations]
  /// resolves.
  final List<Ticket> backlinks;

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

  @override
  List<Object?> get props => [
    ticket,
    childDocs,
    linkedTickets,
    backlinks,
    canAdvanceSddStage,
    sddStageBlockReason,
    needsDesignReview,
    linkedDesignPage,
  ];
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
