// data/repositories/git_projecting_ticket_repository.dart — GitProjectingTicketRepository (data layer).

import 'dart:async';
import 'dart:typed_data';

import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/entities/ticket_search_page.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_complexity.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

/// [TicketRepository] decorator that fires [TicketGitProjector] after every
/// structural/lifecycle write, regardless of which higher-level caller
/// (`TicketsCubit`, `TrashCubit`, `TicketParentTrashService`, or any future
/// one) triggered it. Wraps an inner [TicketRepository] (in practice always
/// `DriftTicketRepository`, but this class depends only on the interface)
/// and delegates every method to it unchanged before/after the projection
/// side effect — never adds validation, never changes persisted data.
///
/// Provided in place of a plain `DriftTicketRepository` wherever a project
/// has a `rootPath` (`app_router.dart`'s existing desktop gate,
/// `TicketGitProjector` itself is already built behind it) — see that
/// file's `RepositoryProvider<TicketRepository>`. Every consumer keeps
/// depending on the [TicketRepository] interface only, so wiring this in
/// requires no change to any existing call site.
///
/// Fixes a real, live-reproduced drift: projection used to be opt-in per
/// write site inside `TicketsCubit` (a private `_triggerGitProjection`
/// helper, manually called from a handful of methods), which meant every
/// other internal write path that constructed and persisted a [Ticket]
/// directly against [TicketRepository] — `promoteIdea`, `createGapOrQuestion`,
/// SDD decomposition/verify-fix materialization, epic-spec creation, and
/// more — silently never reached `tickets/*.md`. Moving the trigger down to
/// this decorator closes every one of those bypasses at once, and any
/// future call site inherits the same guarantee automatically.
///
/// Projects exactly the six events `specs/tickets.md`'s "Git projection"
/// section documents as commit-worthy: [createTicket] (`'created'`),
/// [updateTicketStatus]/[updateStatusForIds] (`'status-changed'`),
/// [updateTicketSddStage] (`'stage-changed'`), [updateTicketParent]
/// (`'reparented'`), [trashTicket] (`'trashed'`), [restoreTicket]
/// (`'restored'`). Every other method — plain content edits via
/// [updateTicket] included — is a pass-through with no projection,
/// deliberately: `specs/tickets.md` already excludes content edits from
/// projection (no commit per keystroke-adjacent save), and this class
/// preserves that boundary rather than widening it. [updateRollup] is
/// likewise excluded — `TicketRollupRecomputer` owns its own batched
/// `TicketGitProjector.projectBatch` call (one commit per cascading
/// ancestor rewrite, not one per ancestor), which this decorator's
/// per-call shape can't replicate without regressing that batching.
class GitProjectingTicketRepository implements TicketRepository {
  /// Creates a [GitProjectingTicketRepository] wrapping [_inner], firing
  /// [_projector] against [_rootPath] after each projected write.
  GitProjectingTicketRepository(this._inner, this._projector, this._rootPath);

  final TicketRepository _inner;
  final TicketGitProjector _projector;
  final String _rootPath;

  /// Delegates to [_inner], then fires a fire-and-forget `'created'`
  /// projection of the persisted ticket (picking up its freshly-generated
  /// `ticketId`).
  @override
  Future<void> createTicket(Ticket ticket) async {
    await _inner.createTicket(ticket);
    unawaited(_project(ticket.id, 'created'));
  }

  /// Delegates to [_inner], then fires a fire-and-forget
  /// `'status-changed'` projection of [id].
  @override
  Future<void> updateTicketStatus(String id, String status) async {
    await _inner.updateTicketStatus(id, status);
    unawaited(_project(id, 'status-changed'));
  }

  /// Delegates to [_inner], then fires one fire-and-forget
  /// `'status-changed'` projection per id in [ids] — not batched into one
  /// commit, matching this method's existing bulk-write shape (see
  /// `TicketsCubit.updateStatusForTickets`'s own pre-existing per-id
  /// projection loop, which this decorator now does instead of the
  /// cubit).
  @override
  Future<void> updateStatusForIds(List<String> ids, String status) async {
    await _inner.updateStatusForIds(ids, status);
    for (final id in ids) {
      unawaited(_project(id, 'status-changed'));
    }
  }

  /// Delegates to [_inner], then fires a fire-and-forget
  /// `'stage-changed'` projection of [id] — closes the gap
  /// `TicketsCubit.advanceSddStage` used to leave open (it called
  /// [TicketRepository.updateTicketSddStage] directly, with no
  /// projection trigger at all, before this decorator existed).
  @override
  Future<void> updateTicketSddStage(String id, SddStage stage) async {
    await _inner.updateTicketSddStage(id, stage);
    unawaited(_project(id, 'stage-changed'));
  }

  /// Delegates to [_inner], then fires a fire-and-forget `'reparented'`
  /// projection of [id] — closes a gap `TicketRollupRecomputer`'s own
  /// batched projection didn't reliably cover: a reparent whose ancestor
  /// rollup numbers happen not to change (e.g. moving a leaf ticket with
  /// no estimate) previously left the moved ticket's own new `parentId`
  /// unprojected indefinitely.
  @override
  Future<void> updateTicketParent(String id, String? parentId) async {
    await _inner.updateTicketParent(id, parentId);
    unawaited(_project(id, 'reparented'));
  }

  /// Delegates to [_inner], then awaits a `'trashed'` projection of [id]
  /// before returning — awaited (unlike the fire-and-forget methods
  /// above), matching `TicketParentTrashService.trash`'s existing
  /// behavior before this decorator took over: the caller is a
  /// lower-frequency, more "final" action, and some callers (tests
  /// included) rely on the commit having landed by the time this
  /// returns. A projection failure here is swallowed rather than
  /// propagated — see [_projectOrSwallow]'s dartdoc for why: the trash
  /// itself, above, already succeeded, and a transient git hiccup must
  /// not report that success as a [TicketsCubit]/[TrashCubit]-visible
  /// failure, which would also skip the rollup recompute
  /// `TicketParentTrashService.trash` fires immediately after this call
  /// returns.
  @override
  Future<void> trashTicket(String id) async {
    await _inner.trashTicket(id);
    await _projectOrSwallow(id, 'trashed');
  }

  /// Delegates to [_inner], then awaits a `'restored'` projection of [id]
  /// before returning — see [trashTicket]'s dartdoc for the awaited
  /// shape and [_projectOrSwallow]'s dartdoc for why a projection
  /// failure here is swallowed rather than propagated.
  @override
  Future<void> restoreTicket(String id) async {
    await _inner.restoreTicket(id);
    await _projectOrSwallow(id, 'restored');
  }

  /// Re-fetches [id] from [_inner] (picking up whatever the write that
  /// preceded this call just persisted — a freshly-generated `ticketId` on
  /// create, a new `status`/`sddStage`/`parentId` otherwise) and projects
  /// it via [_projector]. A `null` result (the ticket vanished between the
  /// write and this read — not expected in practice) is a silent no-op,
  /// matching every projection call site's own null-check before this
  /// decorator centralized them.
  Future<void> _project(String id, String eventLabel) async {
    final ticket = await _inner.getTicketById(id);
    if (ticket == null) return;
    await _projector.project(ticket, _rootPath, eventLabel);
  }

  /// Same as [_project], but never throws — used only by [trashTicket]/
  /// [restoreTicket], the two methods that `await` their own projection
  /// rather than firing it `unawaited`. A git failure (e.g. a missing
  /// `git config user.email`, a stale `index.lock`, a full disk) would
  /// otherwise propagate out of `await _projectOrSwallow(...)` into
  /// [trashTicket]/[restoreTicket]'s caller — `TicketParentTrashService
  /// .trash`/`.restore`, then `TicketsCubit`/`TrashCubit`'s existing
  /// `catch (e) { emit(TicketsError(...)) }` — misreporting the trash/
  /// restore, which already succeeded via [_inner] above, as a failure,
  /// and skipping the rollup recompute those callers fire right after.
  /// The failure itself is not silently invisible: [_projector] and
  /// [GitRepositoryClient] still throw internally at the point it
  /// happens (visible to a debugger or future logging), this method just
  /// declines to let that fail an operation that has, in fact, already
  /// succeeded. The fire-and-forget methods above ([createTicket] et al.)
  /// need no equivalent — an unawaited call's exception never reaches
  /// their own caller regardless.
  Future<void> _projectOrSwallow(String id, String eventLabel) async {
    try {
      await _project(id, eventLabel);
    } catch (_) {
      // See this method's own dartdoc.
    }
  }

  // Every method below is a deliberate pass-through — no projection. See
  // this class's own dartdoc for why: content-edit fields (`updateTicket`,
  // `updatePriorityForIds`, `addTimeSpent`, `applyEstimationSuggestion`)
  // are excluded by the same existing design `specs/tickets.md` already
  // documents; `updateRollup` is owned by `TicketRollupRecomputer`'s own
  // batched projection; the remaining methods write fields never
  // serialized to Markdown, run in the opposite (file → DB) direction, or
  // are out of this fix's scope (permanent deletion never removing the
  // corresponding file is a separate, known gap — see proposal.md).

  @override
  Future<List<Ticket>> getAllTickets() => _inner.getAllTickets();

  @override
  Future<Ticket?> getTicketById(String id) => _inner.getTicketById(id);

  @override
  Future<Ticket?> getTicketByTicketId(String ticketId) =>
      _inner.getTicketByTicketId(ticketId);

  @override
  Future<void> importTicket(Ticket ticket) => _inner.importTicket(ticket);

  @override
  Future<void> updatePriorityForIds(List<String> ids, TicketPriority priority) =>
      _inner.updatePriorityForIds(ids, priority);

  @override
  Future<void> updateTicket(
    Ticket ticket, {
    bool complexityEdited = false,
    bool estimateEdited = false,
  }) => _inner.updateTicket(
    ticket,
    complexityEdited: complexityEdited,
    estimateEdited: estimateEdited,
  );

  @override
  Future<void> addTimeSpent(String id, int minutesDelta) =>
      _inner.addTimeSpent(id, minutesDelta);

  @override
  Future<void> applyEstimationSuggestion(
    String id, {
    ({TicketComplexity value, bool lowConfidence})? complexity,
    ({int value, bool lowConfidence})? estimate,
  }) => _inner.applyEstimationSuggestion(
    id,
    complexity: complexity,
    estimate: estimate,
  );

  @override
  Future<void> updateEmbedding(String id, Uint8List embedding) =>
      _inner.updateEmbedding(id, embedding);

  @override
  Future<void> updateSyncStatus(String id, TicketSyncStatus status) =>
      _inner.updateSyncStatus(id, status);

  @override
  Future<void> updateRollup(
    String id, {
    required int? estimateRollup,
    required int? timeSpentRollup,
  }) => _inner.updateRollup(
    id,
    estimateRollup: estimateRollup,
    timeSpentRollup: timeSpentRollup,
  );

  @override
  Future<int> trashTickets(List<String> ids) => _inner.trashTickets(ids);

  @override
  Future<int> previewTrashCount(List<String> ids) =>
      _inner.previewTrashCount(ids);

  @override
  Future<void> permanentlyDeleteTicket(String id) =>
      _inner.permanentlyDeleteTicket(id);

  @override
  Future<int> permanentlyDeleteTickets(List<String> ids) =>
      _inner.permanentlyDeleteTickets(ids);

  @override
  Future<void> emptyTrash() => _inner.emptyTrash();

  @override
  Future<int> purgeTrashOlderThan(Duration age) =>
      _inner.purgeTrashOlderThan(age);

  @override
  Future<List<Ticket>> getTrashedTickets() => _inner.getTrashedTickets();

  @override
  Future<TicketSearchPage> searchTickets({
    String? query,
    Set<String> statuses = const {},
    Set<TicketType> types = const {},
    Set<TicketPriority> priorities = const {},
    required TicketListSort sort,
    required int limit,
    int offset = 0,
    List<String> statusSortOrder = const [],
  }) => _inner.searchTickets(
    query: query,
    statuses: statuses,
    types: types,
    priorities: priorities,
    sort: sort,
    limit: limit,
    offset: offset,
    statusSortOrder: statusSortOrder,
  );

  @override
  Future<List<Ticket>> getTicketsByParent(
    String? parentId, {
    required List<TicketType> types,
  }) => _inner.getTicketsByParent(parentId, types: types);

  @override
  Future<List<Ticket>> getAllTicketsByType(List<TicketType> types) =>
      _inner.getAllTicketsByType(types);

  @override
  Future<Map<String, int>> getExecutionTokenTotals(List<String> taskIds) =>
      _inner.getExecutionTokenTotals(taskIds);

  @override
  Future<void> applyTokenPrediction(
    String id, {
    required int low,
    required int high,
  }) => _inner.applyTokenPrediction(id, low: low, high: high);
}
