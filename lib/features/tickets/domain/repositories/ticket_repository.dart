// domain/repositories/ticket_repository.dart — TicketRepository interface (domain layer).

import 'dart:typed_data';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/entities/ticket_search_page.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_complexity.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Read/write access to [Ticket] persistence. Implemented by the data layer
/// ([DriftTicketRepository]); UI and domain code depend only on this
/// interface, never on a concrete data source.
abstract interface class TicketRepository {
  /// Returns all live (non-trashed) tickets, most recently created first.
  Future<List<Ticket>> getAllTickets();

  /// Returns the ticket with internal id [id], or `null` if none exists.
  Future<Ticket?> getTicketById(String id);

  /// Persists [ticket]. Implementations generate the human-readable
  /// [Ticket.ticketId] (prefix + sequence) at insert time, so
  /// [ticket.ticketId] on the argument is ignored. For ordinary ticket
  /// creation only — to preserve a caller-supplied `ticketId` instead,
  /// use [importTicket].
  Future<void> createTicket(Ticket ticket);

  /// Persists [ticket] with its own [Ticket.ticketId] preserved verbatim,
  /// unlike [createTicket] which always generates a fresh one. Intended
  /// only for `TicketDbReconstructionService`'s true-import path — a
  /// `tickets/*.md` file whose `ticketId` has no matching existing row
  /// (the genuine second-machine case). Throws if `ticket.ticketId`
  /// already belongs to another row.
  Future<void> importTicket(Ticket ticket);

  /// Updates only the [status] (and `updatedAt`) of the ticket with id
  /// [id]. Does not touch any other field. [status] is a project-defined
  /// status name (see [Ticket.status]) — this method performs no
  /// validation that [status] names a status the project has actually
  /// configured; that's a `TicketsCubit`-layer concern. Throws if [id]
  /// does not exist.
  Future<void> updateTicketStatus(String id, String status);

  /// Writes [status] (and a fresh `updatedAt`) to every ticket in [ids] in
  /// one bulk operation. Unconditional — performs no validation and no
  /// gating (e.g. the Blocked-dependency or coding-execution checks that
  /// guard a single-ticket move to the `executionTrigger`-role status);
  /// that's a `TicketsCubit`-layer concern (see
  /// `TicketsCubit.updateStatusForTickets`), which is responsible for
  /// filtering [ids] down to the writable subset before calling this. Ids
  /// that don't exist are silently skipped.
  Future<void> updateStatusForIds(List<String> ids, String status);

  /// Writes [priority] (and a fresh `updatedAt`) to every ticket in [ids]
  /// in one bulk operation. Unconditional — priority is a plain enum
  /// field with no structural gating, so unlike [updateStatusForIds] there
  /// is no writable-subset filtering for a caller to perform first. Ids
  /// that don't exist are silently skipped.
  Future<void> updatePriorityForIds(List<String> ids, TicketPriority priority);

  /// Updates only the [parentId] (and `updatedAt`) of the ticket with id
  /// [id]. Does not touch any other field, and performs no validation —
  /// callers (see `TicketsCubit.updateTicketParent`) are responsible for
  /// rejecting self-parenting and cycles before calling this. Pass `null`
  /// to clear the parent. Throws if [id] does not exist.
  Future<void> updateTicketParent(String id, String? parentId);

  /// Persists [ticket]'s `title`, `description`, `priority`, `type`,
  /// `estimate`, `timeSpent`, and `complexity`, plus a fresh `updatedAt`.
  /// Does not touch `status` (use [updateTicketStatus]), `sddStage` (use
  /// [updateTicketSddStage]), `parentId`, `embedding`, `id`, or
  /// `ticketId`. Throws if `ticket.id` does not exist.
  ///
  /// `complexitySource`/`estimateSource` are handled separately from every
  /// other field, since `updateTicket` is called for *any* field edit
  /// (title, priority, description, ...) and `ticket.complexity`/
  /// `ticket.estimate` are usually just carried through unchanged on those
  /// calls — stamping unconditionally off non-null-ness would silently
  /// lock an AI-suggested value the caller never actually touched, which
  /// would break the "editing complexity/estimate locks *that* field"
  /// guarantee (see
  /// `aion-arch/changes/ai-assisted-complexity-and-estimate-suggestions/proposal.md`'s
  /// "Locking, independent per field" section). Instead:
  /// - Whenever `ticket.complexity`/`ticket.estimate` is `null`, its
  ///   companion source is unconditionally cleared to `null` too —
  ///   regardless of [complexityEdited]/[estimateEdited] — since a source
  ///   can never outlive its value.
  /// - Otherwise, the companion source is stamped
  ///   `TicketEstimationSource.manual` only when [complexityEdited]/
  ///   [estimateEdited] is `true` (the caller is the Complexity picker's
  ///   `onSelected` or the Estimate field's `onCommit` — a direct edit, or
  ///   an explicit re-confirmation, of that specific field). When `false`
  ///   (the default — every other field's edit path), the source column is
  ///   left completely untouched, preserving whatever it already was
  ///   (`aiSuggested`/`aiSuggestedLowConfidence`/`manual`).
  ///
  /// See [applyEstimationSuggestion] for the AI-suggestion write path this
  /// is deliberately distinct from.
  Future<void> updateTicket(
    Ticket ticket, {
    bool complexityEdited = false,
    bool estimateEdited = false,
  });

  /// Writes an AI-generated complexity/estimate suggestion for the ticket
  /// with id [id]. Each parameter, when non-null, overwrites that field's
  /// value and sets its companion source to
  /// `TicketEstimationSource.aiSuggestedLowConfidence` (if `lowConfidence`)
  /// or `TicketEstimationSource.aiSuggested` otherwise; a `null` parameter
  /// leaves that field (and its source) completely untouched — this is how
  /// a caller writes just one field when the other is locked or the model
  /// produced no value for it. Never touches `updatedAt` — an AI
  /// suggestion is a background side effect, not a user edit, mirroring
  /// [updateEmbedding]/[updateRollup]. Throws if [id] does not exist.
  Future<void> applyEstimationSuggestion(
    String id, {
    ({TicketComplexity value, bool lowConfidence})? complexity,
    ({int value, bool lowConfidence})? estimate,
  });

  /// Updates only the [stage] (and `updatedAt`) of the ticket with id
  /// [id]. Does not touch any other field, and performs no precondition
  /// validation — callers (`TicketsCubit.advanceSddStage`) are
  /// responsible for checking the transition is legal before calling
  /// this. Throws if [id] does not exist.
  Future<void> updateTicketSddStage(String id, SddStage stage);

  /// Updates only the [embedding] of the ticket with id [id]. Independent
  /// of [updateTicket] — embedding regeneration is a background side
  /// effect of a content change, not the content change itself, and must
  /// not perturb `updatedAt` the way a content edit does. Throws if [id]
  /// does not exist.
  Future<void> updateEmbedding(String id, Uint8List embedding);

  /// Updates only the [syncStatus] of the ticket with id [id], independent
  /// of [updateTicket] — sync state changes originate from the
  /// reconciler/watcher, not user edits, and must not perturb `updatedAt`
  /// the way a content edit does. Throws if [id] does not exist.
  Future<void> updateSyncStatus(String id, TicketSyncStatus status);

  /// Updates only [estimateRollup]/[timeSpentRollup] for the ticket with
  /// id [id]. Independent of [updateTicket] — same rationale as
  /// [updateEmbedding]/[updateSyncStatus]: a recomputed derived value is
  /// not a user edit and must not perturb `updatedAt`. Both parameters
  /// are required (even to pass `null`) since a rollup recompute always
  /// resolves both fields together from the same children set — there is
  /// no meaningful "update just one." Throws if [id] does not exist.
  Future<void> updateRollup(
    String id, {
    required int? estimateRollup,
    required int? timeSpentRollup,
  });

  /// Moves [id] and every ticket in its structural subtree into trash
  /// (sets `deletedAt`, deletes nothing). Never blocked by children —
  /// they're cascaded into trash alongside [id] instead. Throws
  /// [StateError] if [id] does not exist.
  Future<void> trashTicket(String id);

  /// Moves every ticket in [ids] — and each one's full structural
  /// subtree — into trash in one call. Returns the total number of
  /// tickets actually moved (== [ids] plus every cascaded descendant,
  /// deduplicated), so the caller can report an accurate count even when
  /// it's larger than `ids.length`. Ids that don't exist are silently
  /// skipped.
  Future<int> trashTickets(List<String> ids);

  /// Returns the total number of tickets that would move to trash if
  /// every id in [ids] were trashed right now — existing ids plus every
  /// structural descendant (live *or already trashed*), deduplicated.
  /// Query only, performs no writes. Mirrors [trashTickets]'s own cascade
  /// computation exactly, so a cascade preview shown before a trash
  /// action always matches what the action will actually touch —
  /// including a descendant that's already in trash (e.g. a child
  /// trashed individually earlier, whose still-live parent is being
  /// trashed now).
  Future<int> previewTrashCount(List<String> ids);

  /// Restores [id] out of trash, along with any currently-trashed
  /// ancestors (so it's never left with a hidden parent) and any
  /// currently-trashed descendants (its own subtree, trashed alongside
  /// it originally). Throws [StateError] if [id] does not exist.
  Future<void> restoreTicket(String id);

  /// Permanently deletes [id] and its full structural subtree —
  /// cascading to comments and `ticket_links` exactly as the old
  /// `deleteTicket` did. Irreversible. Throws [StateError] if [id] does
  /// not exist.
  Future<void> permanentlyDeleteTicket(String id);

  /// Permanently deletes every currently trashed ticket (and their
  /// comments/`ticket_links`). Irreversible. Used by the trash screen's
  /// "Empty trash" action. No-ops if trash is empty.
  Future<void> emptyTrash();

  /// Permanently deletes every currently trashed ticket whose
  /// `deletedAt` is older than [age] (cascading to comments and
  /// `ticket_links`, same as [emptyTrash]). Returns the number of
  /// tickets purged. No-op (returns 0) if none are eligible.
  ///
  /// Safe to filter per-ticket, with no cascade/subtree walk: trashing
  /// always stamps a whole affected subtree with one `DateTime.now()`
  /// at once (see [trashTickets]), and there is no UI path that
  /// re-trashes a single already-trashed descendant independently — so
  /// every member of a given trashed subtree always shares the same
  /// `deletedAt`. A root and its descendants therefore always age out
  /// together.
  Future<int> purgeTrashOlderThan(Duration age);

  /// Returns every currently trashed ticket, most recently trashed
  /// first.
  Future<List<Ticket>> getTrashedTickets();

  /// Returns one page of tickets matching every filter. Within a field,
  /// values in [statuses]/[types]/[priorities] combine as OR (e.g.
  /// `{todo, backlog}` matches either); the three fields combine with
  /// each other, and with [query], as AND. An empty set for a field means
  /// no constraint on that field, not "match nothing" — all three sets
  /// empty and [query] null is equivalent to paginating [getAllTickets].
  /// [query] full-text-matches against title/description. Excludes
  /// trashed tickets, same as [getAllTickets]. Returns at most [limit]
  /// tickets starting after the first [offset] matches, plus whether
  /// further matches exist beyond this page.
  ///
  /// Ordered per `sort.field`/`sort.direction` — [sort] is `required`
  /// (not defaulted), since the caller (`TicketsCubit`) always has a
  /// concrete resolved value to pass, leaving no ambiguous "no sort" case
  /// at this layer to default around. `sort.field ==
  /// TicketSortField.relevance` orders by BM25 match score and requires
  /// [query] to be non-empty — passing it with an empty/null [query]
  /// falls back to `createdAt` descending, since there is no relevance
  /// score to order by; every other field orders independent of whether
  /// [query] is set. See
  /// `aion-arch/changes/ticket-sort-control-and-board-as-default-view`.
  ///
  /// [statusSortOrder] is the caller's currently-configured `WorkflowStatus`
  /// name list, already sorted by `WorkflowStatus.sortOrder` — consulted
  /// only when `sort.field == TicketSortField.status`, since a status is
  /// now project-configured data rather than a fixed enum with its own
  /// declaration order. Ignored for every other sort field.
  Future<TicketSearchPage> searchTickets({
    String? query,
    Set<String> statuses = const {},
    Set<TicketType> types = const {},
    Set<TicketPriority> priorities = const {},
    required TicketListSort sort,
    required int limit,
    int offset = 0,
    List<String> statusSortOrder = const [],
  });

  /// Returns every live (non-trashed) ticket whose `parentId` equals
  /// [parentId] (or, when [parentId] is `null`, every live ticket with no
  /// parent at all) and whose `type` is one of [types]. A dumb,
  /// parameterized query with no business logic — used by the
  /// Documentation section to load one level of the page/resource tree at
  /// a time (root docs when [parentId] is `null`, a page's direct
  /// children when it's set).
  Future<List<Ticket>> getTicketsByParent(
    String? parentId, {
    required List<TicketType> types,
  });

  /// Returns every live (non-trashed) ticket whose `type` is one of
  /// [types], regardless of `parentId` or nesting depth. Unlike
  /// [getTicketsByParent], this is not scoped to one tree level — used by
  /// [TicketDocumentSearchService] to scan every page/resource ticket for
  /// embedding-based search.
  Future<List<Ticket>> getAllTicketsByType(List<TicketType> types);

  /// For each id in [taskIds], sums `inputTokens + outputTokens` (each
  /// treated as `0` when `null`) across every comment in every one of
  /// that task's `"Coding Execution — "`-prefixed `chat` children —
  /// spanning implement/verify turns, retries, and continuation handoffs
  /// alike, since a continuation handoff chat also carries that same
  /// prefix (see `TicketsCubit._executionChatTitle`). One batched grouped
  /// query, not one query per id — the whole point of taking a list.
  /// Returns only the ids whose total is non-zero; an id with no
  /// execution chats yet, or whose execution chats have no comments,
  /// is simply absent from the result map rather than mapped to `0`.
  /// Powers both `TicketTokenPredictor`'s candidate token-history lookups
  /// and `TicketsCubit`'s running-total cache.
  Future<Map<String, int>> getExecutionTokenTotals(List<String> taskIds);

  /// Writes a token-cost prediction for the ticket with id [id]: [low]
  /// and [high] together replace `predictedExecutionTokensLow`/
  /// `predictedExecutionTokensHigh`. Never routed through
  /// [updateTicket]/`copyWith` — a dedicated write, mirroring
  /// [applyEstimationSuggestion]'s own shape, so a plain content edit
  /// can't accidentally clobber a value only `TicketTokenPredictor` should
  /// touch. Never touches `updatedAt` — a prediction is a background side
  /// effect, not a user edit, mirroring [updateEmbedding]/[updateRollup].
  /// Throws if [id] does not exist.
  Future<void> applyTokenPrediction(
    String id, {
    required int low,
    required int high,
  });
}
