// presentation/cubit/tickets_cubit.dart — TicketsCubit business logic (presentation layer).

import 'dart:math' show max;

import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_complexity.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';

/// Loads, lists, and creates tickets via [TicketRepository]. Root-scoped —
/// provided once at the app root, not per-screen.
class TicketsCubit extends Cubit<TicketsState> {
  /// Creates a [TicketsCubit] backed by [_repository]. [_embeddingProvider],
  /// [_gitProjector], [_projectRootPath], [_agentClient], and
  /// [_commentRepository] are optional — when any is `null` (the
  /// default, and every existing call site/test), the embedding-regen,
  /// git-projection, and stage-chat-spawning side effects documented on
  /// [createTicket]/[updateTicket]/[updateTicketStatus]/
  /// [changeTicketStatus]/[trashTicket]/[trashTickets]/[advanceSddStage]
  /// simply no-op, rather than requiring every one of ~40 existing
  /// construction sites to be updated for a feature most of them don't
  /// exercise. Real usage (`app_router.dart`) supplies [_agentClient]/
  /// [_commentRepository] so [advanceSddStage] always spawns its chat.
  /// [_automationSettingsRepository] follows the same optional-dependency
  /// pattern — `null` leaves a finished coding-execution run's status
  /// untouched (never auto-flips to `inReview`) until a caller supplies
  /// one; real usage (`app_router.dart`) always does.
  /// [_modelRoutingRepository] follows the same optional-dependency
  /// pattern too — `null` makes every stage-chat/coding-execution model
  /// resolution fall back to [AgentModel.sonnet] (see [_resolveModel]),
  /// today's pre-per-phase-routing default; real usage
  /// (`app_router.dart`) always supplies one.
  // The public param names below (embeddingProvider/gitProjector/
  // projectRootPath/agentClient/commentRepository/
  // automationSettingsRepository/modelRoutingRepository) intentionally
  // differ from their private backing fields; a private identifier can't
  // be used as an external named-parameter label from another library, so
  // `this._foo` shorthand isn't usable here.
  TicketsCubit(
    this._repository, {
    EmbeddingProvider? embeddingProvider,
    TicketGitProjector? gitProjector,
    String? projectRootPath,
    TicketLinkRepository? linkRepository,
    AgentModelClient? agentClient,
    CommentRepository? commentRepository,
    AutomationSettingsRepository? automationSettingsRepository,
    ModelRoutingRepository? modelRoutingRepository,
  }) : super(const TicketsInitial()) {
    _embeddingProvider = embeddingProvider;
    _gitProjector = gitProjector;
    _projectRootPath = projectRootPath;
    _linkRepository = linkRepository;
    _agentClient = agentClient;
    _commentRepository = commentRepository;
    _automationSettingsRepository = automationSettingsRepository;
    _modelRoutingRepository = modelRoutingRepository;
  }

  final TicketRepository _repository;
  late final EmbeddingProvider? _embeddingProvider;
  late final TicketGitProjector? _gitProjector;
  late final String? _projectRootPath;
  late final TicketLinkRepository? _linkRepository;
  late final AgentModelClient? _agentClient;
  late final CommentRepository? _commentRepository;
  late final AutomationSettingsRepository? _automationSettingsRepository;
  late final ModelRoutingRepository? _modelRoutingRepository;
  static const _uuid = Uuid();

  /// The Task id of the coding-execution run currently in flight, or
  /// `null` if none is running. In-memory only — does not survive an app
  /// restart (see proposal.md's Out of scope).
  String? _inFlightExecutionTaskId;

  /// Task ids waiting behind [_inFlightExecutionTaskId], FIFO — index 0
  /// runs next.
  final List<String> _executionQueue = [];

  /// Whether an `AgentOverageDetectedEvent` has fired during any
  /// coding-execution run this session — once `true`, every subsequent
  /// completion is treated as [AutomationConfidence.gated] regardless of
  /// the configured confidence, per proposal.md's reactive-only budget
  /// handling.
  bool _overageDetectedThisSession = false;

  /// Tickets fetched per page, for both [searchTickets] and
  /// [loadMoreTickets].
  static const _pageSize = 50;

  /// The query/filters the most recent [searchTickets] call used —
  /// remembered so [loadMoreTickets] and the mutation-refresh methods
  /// below don't need the screen to pass them again.
  String? _lastQuery;
  TicketStatus? _lastStatus;
  TicketType? _lastType;
  TicketPriority? _lastPriority;

  /// Bumped on every call that replaces the list wholesale ([searchTickets],
  /// [createTicket], [updateTicketStatus], [trashTicket], [trashTickets]).
  /// A [loadMoreTickets] call in flight discards its result if this
  /// changes before it resolves — guards against a stale in-flight
  /// load-more silently appending onto a list that's since been replaced
  /// by a filter change or another mutation.
  int _searchGeneration = 0;

  /// Pulls the current tickets and [TicketsState]-carried `hasMore` out of
  /// [s], for every state [loadMoreTickets] can sensibly extend. Returns
  /// `null` for [TicketsLoadingMore] (a load-more is already in flight —
  /// this is what makes [loadMoreTickets] a no-op while one is pending,
  /// with no separate debounce timer needed) and for every non-list state.
  ({List<Ticket> tickets, bool hasMore})? _listSnapshot(TicketsState s) =>
      switch (s) {
        TicketsLoaded(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        TicketCreated(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        TicketStatusUpdated(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        TicketsBatchTrashed(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        TicketsLoadMoreFailed(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        _ => null,
      };

  /// Fetches the first page of tickets matching every non-null filter
  /// (ANDed) — see [TicketRepository.searchTickets]. Called with no
  /// arguments, this is equivalent to fetching every ticket (most recent
  /// first). Remembers [query]/[status]/[type]/[priority] internally for
  /// [loadMoreTickets] and the mutation-refresh methods below, and bumps
  /// the internal generation counter so a [loadMoreTickets] call already
  /// in flight from a previous filter state is discarded (not appended
  /// onto the new list) when it resolves. Emits [TicketsLoading] first
  /// only when nothing is on screen yet ([TicketsInitial]/
  /// [TicketsError]/[TicketTrashed]) — once a ticket list is already
  /// showing, the previous list stays visible until the new results
  /// arrive, so re-searching/re-filtering doesn't flash a spinner over
  /// the existing list on every keystroke. Emits [TicketsLoaded] on
  /// success, [TicketsError] if the repository call throws.
  Future<void> searchTickets({
    String? query,
    TicketStatus? status,
    TicketType? type,
    TicketPriority? priority,
  }) async {
    final generation = ++_searchGeneration;
    _lastQuery = query;
    _lastStatus = status;
    _lastType = type;
    _lastPriority = priority;

    final hasVisibleList = switch (state) {
      TicketsLoaded() ||
      TicketCreating() ||
      TicketCreated() ||
      TicketStatusUpdating() ||
      TicketStatusUpdated() ||
      TicketsBatchTrashed() ||
      TicketsLoadingMore() ||
      TicketsLoadMoreFailed() => true,
      _ => false,
    };
    if (!hasVisibleList) emit(const TicketsLoading());

    try {
      final page = await _repository.searchTickets(
        query: query,
        status: status,
        type: type,
        priority: priority,
        limit: _pageSize,
      );
      if (generation != _searchGeneration) return;
      emit(TicketsLoaded(page.tickets, hasMore: page.hasMore));
    } catch (e) {
      if (generation != _searchGeneration) return;
      emit(TicketsError(e.toString()));
    }
  }

  /// Fetches the next page for whatever query/filters [searchTickets] was
  /// last called with, appending to the currently loaded list. No-ops if
  /// the cubit isn't in a settled list-shaped state with more results
  /// available (covers: nothing loaded yet, a load-more already in
  /// flight, or the last page already reached the end) — this doubles as
  /// the concurrency guard against a fast/bouncy scroll firing the
  /// trigger multiple times before the first request resolves. Emits
  /// [TicketsLoadingMore] (carrying the tickets loaded so far)
  /// immediately, then [TicketsLoaded] (carrying the combined list) on
  /// success, or [TicketsLoadMoreFailed] (carrying the tickets loaded so
  /// far, unchanged) if the repository call throws — the existing rows
  /// are never discarded by a failed load-more.
  Future<void> loadMoreTickets() async {
    final snapshot = _listSnapshot(state);
    if (snapshot == null || !snapshot.hasMore) return;

    final currentTickets = snapshot.tickets;
    final generation = _searchGeneration;
    emit(TicketsLoadingMore(currentTickets));

    try {
      final page = await _repository.searchTickets(
        query: _lastQuery,
        status: _lastStatus,
        type: _lastType,
        priority: _lastPriority,
        limit: _pageSize,
        offset: currentTickets.length,
      );
      if (generation != _searchGeneration) return;
      emit(
        TicketsLoaded([
          ...currentTickets,
          ...page.tickets,
        ], hasMore: page.hasMore),
      );
    } catch (e) {
      if (generation != _searchGeneration) return;
      emit(TicketsLoadMoreFailed(currentTickets, hasMore: snapshot.hasMore));
    }
  }

  /// Creates a new ticket of [type] with [title], then reloads the list.
  ///
  /// [status] always starts at [TicketStatus.backlog]. [complexity]
  /// defaults to `null` (unset), matching [Ticket.complexity]'s own
  /// default. Emits
  /// [TicketCreating] (carrying the list as it was before this call) then
  /// [TicketCreated] (carrying the refreshed page) on success, or
  /// [TicketsError] if the repository call throws. The refresh re-applies
  /// the filters [searchTickets] was last called with (rather than
  /// fetching every ticket) and requests at least as many tickets as were
  /// already loaded, so this doesn't silently drop an active search/filter
  /// or collapse an infinite-scrolled list back down to one page.
  ///
  /// @returns the persisted ticket (with its generated `ticketId`) on
  /// success. Existing callers (`CreateTicketScreen`) are unaffected by
  /// this return value and may continue to ignore it — added so
  /// `PageTicketProviderImpl.createPage` can hand the created ticket back
  /// through `PageTicketProvider` without a second query. Rethrows the
  /// original exception after emitting [TicketsError] on failure, so a
  /// caller that does await this (e.g. `PageTicketProviderImpl`) sees the
  /// failure rather than a value of the wrong type.
  Future<Ticket> createTicket({
    required TicketType type,
    required String title,
    String? description,
    TicketPriority priority = TicketPriority.none,
    String? parentId,
    TicketComplexity? complexity,
  }) async {
    _searchGeneration++;
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreating(:final tickets) => tickets,
      TicketStatusUpdating(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };

    emit(TicketCreating(currentTickets));
    try {
      final now = DateTime.now();
      final ticket = Ticket(
        id: _uuid.v4(),
        ticketId: '',
        complexity: complexity,
        type: type,
        title: title,
        description: description,
        status: TicketStatus.backlog,
        priority: priority,
        parentId: parentId,
        createdAt: now,
        updatedAt: now,
      );

      await _repository.createTicket(ticket);
      final persisted = await _repository.getTicketById(ticket.id);
      if (persisted != null) {
        // Always regenerate on create (no prior title/description to
        // compare against), fire-and-forget.
        unawaited(_triggerEmbeddingRegen(persisted));
        unawaited(_triggerGitProjection(persisted, 'created'));
      }
      final page = await _repository.searchTickets(
        query: _lastQuery,
        status: _lastStatus,
        type: _lastType,
        priority: _lastPriority,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(TicketCreated(page.tickets, hasMore: page.hasMore));
      return persisted ?? ticket;
    } catch (e) {
      emit(TicketsError(e.toString()));
      rethrow;
    }
  }

  /// Moves ticket [id] to [status]. Emits [TicketStatusUpdating] (carrying
  /// the list with [id]'s status optimistically replaced) immediately,
  /// then [TicketStatusUpdated] (carrying the re-fetched page) once the
  /// repository call succeeds, or [TicketsError] if it throws. The
  /// refresh re-applies the filters [searchTickets] was last called with
  /// and requests at least as many tickets as were already loaded, so a
  /// background status update (e.g. a board drag) never collapses an
  /// infinite-scrolled list back down to one page. When [id] is a Task
  /// moving to [TicketStatus.inProgress], first runs
  /// [_interceptTaskExecutionTrigger] — a rejected trigger skips the
  /// write entirely (emitting the classified error + a re-emitted
  /// detail state instead of the usual list-shaped states); an allowed
  /// one proceeds as normal, then [_triggerOrQueueCodingExecution] starts
  /// (or queues) the coding-execution run once the write succeeds.
  Future<void> updateTicketStatus(String id, TicketStatus status) async {
    // Only fetch the ticket up front when the status is the one
    // _interceptTaskExecutionTrigger can actually reject (inProgress) —
    // every other transition returns true immediately, so skip the extra
    // round trip other status changes (e.g. a plain board drag) don't
    // need.
    if (status == TicketStatus.inProgress) {
      final target = await _repository.getTicketById(id);
      if (target != null &&
          !(await _interceptTaskExecutionTrigger(target, status))) {
        return;
      }
    }

    _searchGeneration++;
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdating(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };

    final optimistic = [
      for (final t in currentTickets)
        if (t.id == id) t.copyWith(status: status) else t,
    ];
    emit(TicketStatusUpdating(optimistic));

    try {
      await _repository.updateTicketStatus(id, status);
      final updated = await _repository.getTicketById(id);
      if (updated != null) {
        unawaited(_triggerGitProjection(updated, 'status-changed'));
        if (updated.type == TicketType.task &&
            status == TicketStatus.inProgress) {
          unawaited(_triggerOrQueueCodingExecution(updated));
        }
      }
      final page = await _repository.searchTickets(
        query: _lastQuery,
        status: _lastStatus,
        type: _lastType,
        priority: _lastPriority,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(TicketStatusUpdated(page.tickets, hasMore: page.hasMore));
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Persists every editable field of [ticket] via
  /// [TicketRepository.updateTicket], then re-fetches and emits
  /// [TicketDetailLoaded] with the refreshed ticket. Emits [TicketsError]
  /// on failure. Unlike [updateTicketStatus], this does not emit an
  /// optimistic intermediate state — the calling `InlineEditableField`/
  /// `SelectionMenu` already renders the new value locally before the
  /// repository round trip completes, so no separate "Updating" state is
  /// needed here.
  ///
  /// @returns the refreshed ticket on success. Existing callers
  /// (`TicketDetailScreen`) are unaffected by this return value and may
  /// continue to ignore it — added so `PageTicketProviderImpl.updatePage`
  /// can hand the updated ticket back through `PageTicketProvider`
  /// without a second query. Rethrows the original exception after
  /// emitting [TicketsError] on failure, so a caller that does await
  /// this (e.g. `PageTicketProviderImpl`) sees the failure rather than a
  /// value of the wrong type.
  Future<Ticket> updateTicket(Ticket ticket) async {
    try {
      final previous = await _repository.getTicketById(ticket.id);
      await _repository.updateTicket(ticket);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
        // Only regenerate when title/description actually changed — not
        // on every field edit (e.g. a priority-only change shouldn't
        // trigger this). Git projection is deliberately not triggered
        // here — design.md's trigger events are create/status-change/
        // trash/restore, not every content edit (would be a commit
        // storm).
        if (previous == null ||
            previous.title != refreshed.title ||
            previous.description != refreshed.description) {
          unawaited(_triggerEmbeddingRegen(refreshed));
        }
      }
      return refreshed ?? ticket;
    } catch (e) {
      emit(TicketsError(e.toString()));
      rethrow;
    }
  }

  /// Changes [ticket]'s status from the ticket-detail screen. Persists via
  /// the same [TicketRepository.updateTicketStatus] the board's drag/
  /// `MoveToStatusMenu` path calls, then re-fetches and emits
  /// [TicketDetailLoaded] with the refreshed ticket — unlike
  /// [updateTicketStatus], which emits list-shaped optimistic states built
  /// for the board and would fall through `TicketDetailScreen`'s state
  /// switch. Emits [TicketsError] on failure. When [ticket] is a Task
  /// moving to [TicketStatus.inProgress], first runs
  /// [_interceptTaskExecutionTrigger] — a rejected trigger skips the
  /// write entirely; an allowed one proceeds as normal, then
  /// [_triggerOrQueueCodingExecution] starts (or queues) the
  /// coding-execution run once the write succeeds.
  Future<void> changeTicketStatus(Ticket ticket, TicketStatus status) async {
    if (!(await _interceptTaskExecutionTrigger(ticket, status))) return;
    try {
      await _repository.updateTicketStatus(ticket.id, status);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
        unawaited(_triggerGitProjection(refreshed, 'status-changed'));
        if (refreshed.type == TicketType.task &&
            status == TicketStatus.inProgress) {
          unawaited(_triggerOrQueueCodingExecution(refreshed));
        }
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Returns every ticket that [ticket] could validly be reparented under:
  /// all tickets except [ticket] itself, any of its descendants
  /// (reachable by walking `parentId` forward, since either would create a
  /// cycle), and any candidate whose type cannot structurally parent
  /// [ticket]'s type per [TicketTypeHierarchy.canParent]. Performs a query
  /// only — does not emit a state, since this feeds a picker overlay
  /// rather than driving the detail screen's own render state.
  Future<List<Ticket>> getValidParentCandidates(Ticket ticket) async {
    final all = await _repository.getAllTickets();
    final descendantIds = _descendantIds(ticket.id, all);
    return all
        .where(
          (t) =>
              t.id != ticket.id &&
              !descendantIds.contains(t.id) &&
              t.type.canParent(ticket.type),
        )
        .toList();
  }

  /// Returns every ticket in the workspace, for pickers that need the
  /// full candidate set with no self/descendant exclusion (e.g. the
  /// create-ticket parent field, where the ticket being created doesn't
  /// exist yet). Performs a query only — does not emit a state.
  Future<List<Ticket>> getAllTickets() => _repository.getAllTickets();

  /// Returns every ticket whose type may structurally parent [childType]
  /// per [TicketTypeHierarchy.canParent], for the create-ticket parent
  /// field — where the ticket being created doesn't exist yet, so there is
  /// no id to derive self/descendant exclusions from. Performs a query
  /// only — does not emit a state.
  Future<List<Ticket>> getValidParentCandidatesForType(
    TicketType childType,
  ) async {
    final all = await _repository.getAllTickets();
    return all.where((t) => t.type.canParent(childType)).toList();
  }

  /// Reassigns [ticket]'s parent to [newParentId] (`null` clears it).
  /// Rejects self-parenting and cycles locally — without calling the
  /// repository — by re-deriving the same descendant set
  /// [getValidParentCandidates] would, then emits
  /// [TicketsError] with [TicketsErrorReason.invalidParent] followed
  /// immediately by a re-emitted [TicketDetailLoaded] (same pattern as
  /// [deleteTicket]'s `hasChildren` handling), so the detail screen shows
  /// a toast rather than collapsing to the generic error view. Also
  /// rejects any attempt to set a non-null parent on a ticket whose type
  /// is always a subtree root ([TicketType.epic], [TicketType.signal], or
  /// [TicketType.release] — see [TicketTypeHierarchy.isAlwaysRoot]) — and
  /// any candidate parent whose type cannot structurally parent [ticket]'s
  /// type per [TicketTypeHierarchy.canParent], via the same rejection
  /// path. On a valid reparent, persists via
  /// [TicketRepository.updateTicketParent] and emits the refreshed
  /// [TicketDetailLoaded].
  Future<void> updateTicketParent(Ticket ticket, String? newParentId) async {
    if (newParentId != null) {
      if (newParentId == ticket.id) {
        await _emitInvalidParent(ticket.id);
        return;
      }
      if (ticket.type.isAlwaysRoot) {
        await _emitInvalidParent(ticket.id);
        return;
      }
      final all = await _repository.getAllTickets();
      final descendantIds = _descendantIds(ticket.id, all);
      if (descendantIds.contains(newParentId)) {
        await _emitInvalidParent(ticket.id);
        return;
      }
      final candidateParent = await _repository.getTicketById(newParentId);
      if (candidateParent == null ||
          !candidateParent.type.canParent(ticket.type)) {
        await _emitInvalidParent(ticket.id);
        return;
      }
    }

    try {
      await _repository.updateTicketParent(ticket.id, newParentId);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Emits the rejected-reparent error for ticket [ticketId], then
  /// re-emits its unchanged [TicketDetailLoaded] so the detail screen
  /// shows a toast instead of collapsing to the generic error view.
  Future<void> _emitInvalidParent(String ticketId) async {
    emit(const TicketsError('', reason: TicketsErrorReason.invalidParent));
    final ticket = await _repository.getTicketById(ticketId);
    if (ticket != null) {
      emit(TicketDetailLoaded(ticket));
    }
  }

  /// Advances [ticket]'s [Ticket.sddStage] to the next stage, after
  /// checking that stage's precondition. Rejects (emits
  /// [TicketsError] with [TicketsErrorReason.sddStagePreconditionNotMet],
  /// then re-emits [TicketDetailLoaded], mirroring [_emitInvalidParent])
  /// if `ticket.type` is not [TicketType.epic]/[TicketType.story], the
  /// ticket has already reached [SddStage.archived], or the precondition
  /// for the current → next transition isn't met yet:
  ///
  /// - `null` → [SddStage.exploring]: no precondition, any epic/story may
  ///   start.
  /// - [SddStage.exploring] → [SddStage.proposed]: the ticket's most
  ///   recently created `chat` child has at least one [CommentAuthorType.ai]
  ///   comment (i.e. isn't mid-run).
  /// - [SddStage.proposed] → [SddStage.verifying]: every direct child at
  ///   the next rank down (Tasks for a story, Stories for an epic) has
  ///   reached a terminal state ([TicketStatus.done] for a Task,
  ///   [SddStage.archived] for a Story) — and at least one such child
  ///   exists.
  /// - [SddStage.verifying] → [SddStage.archived]: same chat-reply check
  ///   as exploring → proposed, against the most recent `chat` child.
  ///
  /// On success: persists the new stage via
  /// [TicketRepository.updateTicketSddStage], re-emits
  /// [TicketDetailLoaded] (so the tracker/current-stage line update
  /// immediately, independent of how long the spawned chat's model call
  /// below takes), then spawns the next stage's chat (see
  /// [_spawnStageChat]) unless the new stage is [SddStage.archived]
  /// (nothing to spawn after Archival).
  ///
  /// @returns the spawned chat ticket's id once it and its first AI reply
  /// have been persisted, so a caller (`TicketDetailScreen`'s Advance
  /// button handlers) can navigate straight to it; `null` when nothing
  /// was spawned (the new stage is [SddStage.archived]) or nothing to
  /// advance (a rejection already emitted [TicketsError]).
  Future<String?> advanceSddStage(Ticket ticket) async {
    if (ticket.type != TicketType.epic && ticket.type != TicketType.story) {
      await _emitSddStagePreconditionNotMet(ticket.id);
      return null;
    }

    final nextStage = await _nextSddStage(ticket);
    if (nextStage == null) {
      await _emitSddStagePreconditionNotMet(ticket.id);
      return null;
    }
    if (!(await _sddStageAdvanceCheck(ticket)).canAdvance) {
      await _emitSddStagePreconditionNotMet(ticket.id);
      return null;
    }

    try {
      await _repository.updateTicketSddStage(ticket.id, nextStage);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed == null) return null;
      emit(TicketDetailLoaded(refreshed));
      if (nextStage == SddStage.archived) return null;
      return await _spawnStageChat(refreshed, nextStage);
    } catch (e) {
      emit(TicketsError(e.toString()));
      return null;
    }
  }

  /// Promotes [signal] into an epic: if [existingEpicId] is given, links
  /// [signal] to that epic via [TicketLinkRepository.createLink] (as
  /// [TicketLinkType.relatesTo]); otherwise creates a new
  /// [TicketType.epic] ticket copying `signal.title`/`description`, then
  /// links the two the same way. Does not delete or change [signal]'s
  /// own type or status — promotion is a link, not a conversion,
  /// consistent with `release`'s existing cross-cutting-link precedent.
  /// Emits [TicketsError] (raw message, no classified reason — this
  /// guard is defensive, since the UI only ever calls this for a
  /// `signal` ticket) if `signal.type` isn't [TicketType.signal]. No-ops
  /// (does not touch the repository) if constructed without a
  /// [TicketLinkRepository] (see the constructor's dartdoc).
  Future<void> promoteSignalToEpic(
    Ticket signal, {
    String? existingEpicId,
  }) async {
    if (signal.type != TicketType.signal) {
      emit(TicketsError('Only signal tickets can be promoted to an epic.'));
      final ticket = await _repository.getTicketById(signal.id);
      if (ticket != null) {
        emit(TicketDetailLoaded(ticket));
      }
      return;
    }

    final linkRepo = _linkRepository;
    if (linkRepo == null) return;

    try {
      String epicId;
      if (existingEpicId != null) {
        epicId = existingEpicId;
      } else {
        final now = DateTime.now();
        final epic = Ticket(
          id: _uuid.v4(),
          ticketId: '',
          type: TicketType.epic,
          title: signal.title,
          description: signal.description,
          status: TicketStatus.backlog,
          createdAt: now,
          updatedAt: now,
        );
        await _repository.createTicket(epic);
        epicId = epic.id;
      }
      await linkRepo.createLink(
        sourceTicketId: signal.id,
        targetTicketId: epicId,
        linkType: TicketLinkType.relatesTo,
      );
      final refreshed = await _repository.getTicketById(signal.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Re-runs [SddStage.designSync]'s validation in place, after the
  /// human has edited the linked design Page to address a `DESIGN GATE:
  /// PENDING` verdict. Re-assembles fresh context (the Page's *current*
  /// content — unlike a plain user chat reply, which wouldn't
  /// automatically pick up an edit made outside the chat) and posts
  /// another turn to the existing [designSyncChat], via the same
  /// [ChatCubit.runChatTurn] helper [_spawnStageChat] uses. No-ops
  /// (returns without posting) if [designSyncChat] isn't a `chat`
  /// ticket, its parent isn't at [SddStage.designSync], or the cubit was
  /// constructed without an [AgentModelClient]/[CommentRepository] (see
  /// the constructor's dartdoc). Added for
  /// `aion-arch/changes/sdd-design-gate`.
  Future<void> retryDesignSync(Ticket designSyncChat) async {
    if (designSyncChat.type != TicketType.chat) return;
    final client = _agentClient;
    final commentRepo = _commentRepository;
    if (client == null || commentRepo == null) return;
    final parentId = designSyncChat.parentId;
    if (parentId == null) return;
    final parent = await _repository.getTicketById(parentId);
    if (parent == null || parent.sddStage != SddStage.designSync) return;

    final context = await _assembleStageContext(parent, SddStage.designSync);
    await commentRepo.addComment(
      TicketComment(
        id: '',
        ticketId: designSyncChat.id,
        content: context,
        authorType: CommentAuthorType.system,
        createdAt: DateTime.now(),
      ),
    );
    await ChatCubit.runChatTurn(
      client: client,
      commentRepo: commentRepo,
      chatTicketId: designSyncChat.id,
      prompt: context,
      model: await _resolveModel(SddStage.designSync.modelPhase),
    );
  }

  /// Emits the rejected-stage-advance error for ticket [ticketId], then
  /// re-emits its unchanged [TicketDetailLoaded] so the detail screen
  /// shows a toast instead of collapsing to the generic error view.
  /// Mirrors [_emitInvalidParent].
  Future<void> _emitSddStagePreconditionNotMet(String ticketId) async {
    emit(
      const TicketsError(
        '',
        reason: TicketsErrorReason.sddStagePreconditionNotMet,
      ),
    );
    final ticket = await _repository.getTicketById(ticketId);
    if (ticket != null) {
      emit(TicketDetailLoaded(ticket));
    }
  }

  /// The next [SddStage] after [ticket]'s current one, or `null` if
  /// already [SddStage.archived] (nothing further to advance to). Async
  /// because the `proposed → ?` branch must inspect [ticket]'s child
  /// Tasks (via [TicketRepository.getTicketsByParent]) to decide between
  /// [SddStage.designBrief] and [SddStage.verifying] for a `story` —
  /// see [_storyNeedsDesignReview]. An `epic` always skips straight to
  /// [SddStage.verifying], since [SddStage.designBrief]/
  /// [SddStage.designSync] only ever apply to `story` tickets. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  Future<SddStage?> _nextSddStage(Ticket ticket) async {
    switch (ticket.sddStage) {
      case null:
        return SddStage.exploring;
      case SddStage.exploring:
        return SddStage.proposed;
      case SddStage.proposed:
        if (ticket.type != TicketType.story) return SddStage.verifying;
        final tasks = await _repository.getTicketsByParent(
          ticket.id,
          types: const [TicketType.task],
        );
        return _storyNeedsDesignReview(tasks)
            ? SddStage.designBrief
            : SddStage.verifying;
      case SddStage.designBrief:
        return SddStage.designSync;
      case SddStage.designSync:
        return SddStage.verifying;
      case SddStage.verifying:
        return SddStage.archived;
      case SddStage.archived:
        return null;
    }
  }

  /// Whether any of [tasks] indicates UI work, using the same keyword
  /// heuristic `/propose`'s own design-gate block already applies to a
  /// change's touched files — here applied to each Task's title +
  /// description instead of a file path. Case-insensitive substring
  /// match against: "widget", "screen", "component", "ui". Computed
  /// fresh every time, not persisted — mirrors how the existing
  /// `proposed` precondition already re-fetches children on every check
  /// rather than caching. Added for `aion-arch/changes/sdd-design-gate`.
  bool _storyNeedsDesignReview(List<Ticket> tasks) {
    const keywords = ['widget', 'screen', 'component', 'ui'];
    return tasks.any((t) {
      final text = '${t.title} ${t.description ?? ''}'.toLowerCase();
      return keywords.any(text.contains);
    });
  }

  /// Whether [advanceSddStage] would currently succeed for [ticket],
  /// alongside — when it wouldn't — why, as an [SddStageBlockReason] for
  /// the "Not ready" hint row (`_SddStageSection`, see
  /// `aion-arch/changes/sdd-ticket-execution/design.md` §2.2). Shared by
  /// [advanceSddStage]'s own check and [getTicketById]'s
  /// [TicketDetailLoaded.canAdvanceSddStage]/
  /// [TicketDetailLoaded.sddStageBlockReason] computation, so the two
  /// can't disagree. `canAdvance` is `false` with `blockReason: null` for
  /// any type other than [TicketType.epic]/[TicketType.story], or once
  /// [SddStage.archived] is reached (nothing left to advance to, not a
  /// "blocked" state).
  Future<({bool canAdvance, SddStageBlockReason? blockReason})>
  _sddStageAdvanceCheck(Ticket ticket) async {
    if (ticket.type != TicketType.epic && ticket.type != TicketType.story) {
      return (canAdvance: false, blockReason: null);
    }
    if (await _nextSddStage(ticket) == null) {
      return (canAdvance: false, blockReason: null);
    }

    switch (ticket.sddStage) {
      case null:
        return (canAdvance: true, blockReason: null);
      case SddStage.exploring:
      case SddStage.verifying:
        final ready = await _mostRecentChatHasTerminalReply(ticket.id);
        return (
          canAdvance: ready,
          blockReason: ready ? null : SddStageBlockReason.awaitingChatReply,
        );
      case SddStage.proposed:
        // Story branch: `designBrief`/`designSync` are supposed to run
        // *before* code, so a Story needing design review only requires
        // its Tasks to exist (not be done) to reach `designBrief` — see
        // proposal.md's "Grounding correction." The skip-design branch
        // (straight to `verifying`) is unaffected: it never had a
        // pre-code stage to protect, so "Tasks done" still gates it, same
        // as the epic branch (checking child Stories archived).
        final nextRank = ticket.type == TicketType.story
            ? TicketType.task
            : TicketType.story;
        final children = await _repository.getTicketsByParent(
          ticket.id,
          types: [nextRank],
        );
        final needsDesign =
            ticket.type == TicketType.story &&
            _storyNeedsDesignReview(children);
        final ready =
            children.isNotEmpty &&
            (needsDesign ||
                children.every(
                  (c) => nextRank == TicketType.task
                      ? c.status == TicketStatus.done
                      : c.sddStage == SddStage.archived,
                ));
        return (
          canAdvance: ready,
          blockReason: ready ? null : SddStageBlockReason.awaitingChildren,
        );
      case SddStage.designBrief:
        final page = await _linkedDesignPage(ticket.id);
        final ready =
            page != null && (page.description?.trim().isNotEmpty ?? false);
        return (
          canAdvance: ready,
          blockReason: ready
              ? null
              : SddStageBlockReason.awaitingDesignPaste,
        );
      case SddStage.designSync:
        // Also requires every child Task done — restoring the check to
        // the transition it always should have gated, one stage later
        // than where it was misplaced (see proposal.md's "Grounding
        // correction").
        final approved = await _designSyncApproved(ticket.id);
        final tasks = await _repository.getTicketsByParent(
          ticket.id,
          types: const [TicketType.task],
        );
        final ready =
            approved &&
            tasks.isNotEmpty &&
            tasks.every((t) => t.status == TicketStatus.done);
        return (
          canAdvance: ready,
          blockReason: ready
              ? null
              : SddStageBlockReason.awaitingDesignApproval,
        );
      case SddStage.archived:
        return (canAdvance: false, blockReason: null);
    }
  }

  /// The `page`-type ticket linked to [storyId] whose title matches the
  /// deterministic `"Design — <title>"` naming [_spawnStageChat] gives
  /// it — identified by naming convention rather than a dedicated schema
  /// field, since no other relationship in the codebase needs one.
  /// Returns `null` if constructed without a [TicketLinkRepository]
  /// (see the constructor's dartdoc), or if no such link exists yet.
  /// Added for `aion-arch/changes/sdd-design-gate`.
  Future<Ticket?> _linkedDesignPage(String storyId) async {
    final linkRepo = _linkRepository;
    if (linkRepo == null) return null;
    final links = await linkRepo.getLinksForTicket(storyId);
    for (final link in links) {
      final otherId = link.sourceTicketId == storyId
          ? link.targetTicketId
          : link.sourceTicketId;
      final other = await _repository.getTicketById(otherId);
      if (other != null &&
          other.type == TicketType.page &&
          other.title.startsWith('Design — ')) {
        return other;
      }
    }
    return null;
  }

  /// Whether [storyId]'s `"Design Sync — "`-prefixed chat's most recent
  /// comment is an [CommentAuthorType.ai] reply whose content contains
  /// the literal line `DESIGN GATE: APPROVED` — mirrors `/design-sync`'s
  /// own final-summary line format. Unlike
  /// [_mostRecentChatHasTerminalReply] (any AI reply unlocks
  /// advancement), this checks the reply's *content*, since a `DESIGN
  /// GATE: PENDING` verdict must not unblock advancement — see
  /// [retryDesignSync] for how a fresh verdict gets produced after a
  /// `PENDING` result. Added for `aion-arch/changes/sdd-design-gate`.
  Future<bool> _designSyncApproved(String storyId) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return false;
    final chats = await _repository.getTicketsByParent(
      storyId,
      types: const [TicketType.chat],
    );
    final designSyncChats =
        chats.where((c) => c.title.startsWith('Design Sync — ')).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (designSyncChats.isEmpty) return false;
    final comments = await commentRepo.getCommentsForTicket(
      designSyncChats.first.id,
    );
    if (comments.isEmpty) return false;
    final mostRecent = comments.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    return mostRecent.authorType == CommentAuthorType.ai &&
        mostRecent.content.contains('DESIGN GATE: APPROVED');
  }

  /// Whether a Task's coding-execution run may start, built directly on
  /// the now-correctly-gated [_storyNeedsDesignReview]/
  /// [_designSyncApproved] pair — not on [SddStage] position, sidestepping
  /// [_sddStageAdvanceCheck]'s fixed bug entirely rather than depending on
  /// it being exactly right. `canStart` is always `true` when [task] has
  /// no governing Story (see [_governingStory]) or that Story's Tasks
  /// don't indicate UI work.
  Future<({bool canStart, CodingExecutionBlockReason? reason})>
  _codingExecutionGateCheck(Ticket task) async {
    final story = await _governingStory(task);
    if (story == null) return (canStart: true, reason: null);
    final siblingTasks = await _repository.getTicketsByParent(
      story.id,
      types: const [TicketType.task],
    );
    if (!_storyNeedsDesignReview(siblingTasks)) {
      return (canStart: true, reason: null);
    }
    final approved = await _designSyncApproved(story.id);
    return (
      canStart: approved,
      reason: approved
          ? null
          : CodingExecutionBlockReason.storyDesignGatePending,
    );
  }

  /// Walks [task]'s `parentId` up to find the nearest `story` ancestor —
  /// `null` if [task] is parentless or its nearest structural ancestor is
  /// an `epic` (a Task parented directly by an Epic, ad hoc — no Story to
  /// gate on, so it's never blocked). A Task's parent is always a Story or
  /// an Epic or nothing at all (task-under-task is disallowed by
  /// `TicketTypeHierarchy.canParent`), so this never walks more than one
  /// level up in practice, but is written as a walk for defensiveness.
  Future<Ticket?> _governingStory(Ticket task) async {
    var current = task;
    while (current.parentId != null) {
      final parent = await _repository.getTicketById(current.parentId!);
      if (parent == null) return null;
      if (parent.type == TicketType.story) return parent;
      if (parent.type == TicketType.epic) return null;
      current = parent;
    }
    return null;
  }

  /// Checked by [changeTicketStatus]/[updateTicketStatus] before their
  /// repository write, for the one status transition that can be
  /// rejected: a Task moving to [TicketStatus.inProgress] while
  /// [_codingExecutionGateCheck] disallows it. Every other type/status
  /// combination always returns `true` (not a trigger — proceed as
  /// normal). On rejection, emits [TicketsErrorReason.codingExecutionBlocked]
  /// then a re-emitted unchanged [TicketDetailLoaded], mirroring
  /// [_emitInvalidParent]/[_emitSddStagePreconditionNotMet], and returns
  /// `false` so the caller skips the write entirely.
  Future<bool> _interceptTaskExecutionTrigger(
    Ticket task,
    TicketStatus status,
  ) async {
    if (task.type != TicketType.task || status != TicketStatus.inProgress) {
      return true;
    }
    final check = await _codingExecutionGateCheck(task);
    if (!check.canStart) {
      emit(
        const TicketsError(
          '',
          reason: TicketsErrorReason.codingExecutionBlocked,
        ),
      );
      emit(TicketDetailLoaded(task));
      return false;
    }
    return true;
  }

  /// Starts [task]'s coding-execution run immediately if no other run is
  /// in flight, or appends it to [_executionQueue] (FIFO) otherwise.
  /// Called by [changeTicketStatus]/[updateTicketStatus] after a Task's
  /// status write to [TicketStatus.inProgress] succeeds.
  Future<void> _triggerOrQueueCodingExecution(Ticket task) async {
    if (_inFlightExecutionTaskId != null) {
      _executionQueue.add(task.id);
      return;
    }
    _inFlightExecutionTaskId = task.id;
    unawaited(_runCodingExecution(task));
  }

  /// Runs [task]'s coding-execution turn: spawns a visible `chat` child
  /// ticket (`"Coding Execution — <task.title>"`), posts the assembled
  /// context (see [_assembleExecutionContext]) as a
  /// [CommentAuthorType.system] comment, then calls
  /// [ChatCubit.runChatTurn] with `toolsEnabled: true` and
  /// [_projectRootPath] as the working directory — the same accumulate/
  /// persist path every other stage chat uses, but with real tool access.
  /// On completion, if the run reported a confirmed PR (see
  /// [_executionSucceededWithPr]) and [_automationSettingsRepository] is
  /// configured, flips [task] straight to [TicketStatus.inReview] when
  /// [AutomationContext.codingExecution]'s confidence is
  /// [AutomationConfidence.auto] (forced to
  /// [AutomationConfidence.gated] for the rest of the session once
  /// [_overageDetectedThisSession] is `true`) — `gated`/`manual` leave the
  /// status as-is, for [getTicketById]'s `executionAwaitingReview`
  /// computation (or a manual status change) to surface instead.
  /// Re-emits [TicketDetailLoaded] if the detail screen was showing
  /// [task] *when the run started* — captured up front rather than
  /// re-read from `state` afterward, since an overage toast emitted
  /// mid-run would otherwise clobber `state` and make a live re-check
  /// wrongly skip the refresh. Then dequeues the next run (see
  /// [_dequeueNext]), no-opping gracefully if constructed without an
  /// [AgentModelClient]/[CommentRepository] (see the constructor's
  /// dartdoc).
  Future<void> _runCodingExecution(Ticket task) async {
    final client = _agentClient;
    final commentRepo = _commentRepository;
    final automationRepo = _automationSettingsRepository;
    if (client == null || commentRepo == null) {
      _inFlightExecutionTaskId = null;
      unawaited(_dequeueNext());
      return;
    }

    // Captured before the run starts, not re-read from `state` afterward:
    // `onOverageDetected` below can emit a one-shot `TicketsError` toast
    // mid-run, which would otherwise clobber `state` and make a live
    // re-check wrongly conclude the detail screen isn't showing [task]
    // anymore, silently skipping the refresh.
    final wasShowingTaskDetail =
        state is TicketDetailLoaded &&
        (state as TicketDetailLoaded).ticket.id == task.id;

    final now = DateTime.now();
    final chatTicket = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.chat,
      title: 'Coding Execution — ${task.title}',
      status: TicketStatus.backlog,
      parentId: task.id,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createTicket(chatTicket);
    final persistedChat = await _repository.getTicketById(chatTicket.id);
    if (persistedChat == null) {
      _inFlightExecutionTaskId = null;
      unawaited(_dequeueNext());
      return;
    }

    final context = _assembleExecutionContext(task);
    await commentRepo.addComment(
      TicketComment(
        id: '',
        ticketId: persistedChat.id,
        content: context,
        authorType: CommentAuthorType.system,
        createdAt: DateTime.now(),
      ),
    );

    await ChatCubit.runChatTurn(
      client: client,
      commentRepo: commentRepo,
      chatTicketId: persistedChat.id,
      prompt: context,
      model: await _resolveModel(ModelPhase.execution),
      toolsEnabled: true,
      workingDirectory: _projectRootPath,
      onOverageDetected: () {
        if (!_overageDetectedThisSession) {
          _overageDetectedThisSession = true;
          emit(
            const TicketsError(
              '',
              reason: TicketsErrorReason.executionBudgetOverageDetected,
            ),
          );
        }
      },
    );

    final prConfirmed = await _executionSucceededWithPr(task.id);
    if (prConfirmed && automationRepo != null) {
      final confidence = await _effectiveCodingExecutionConfidence(
        automationRepo,
      );
      if (confidence == AutomationConfidence.auto) {
        await _repository.updateTicketStatus(task.id, TicketStatus.inReview);
      }
      // `gated`/`manual`: leave status as-is; getTicketById's re-check
      // surfaces the "ready for review" banner or leaves it to a manual
      // status change.
    }

    // Cleared before the refresh below (not after) so getTicketById's own
    // `isExecuting` computation correctly sees this run as finished,
    // rather than reporting the just-completed run as still in flight.
    _inFlightExecutionTaskId = null;

    if (wasShowingTaskDetail) {
      await getTicketById(task.id);
    }

    unawaited(_dequeueNext());
  }

  /// [automationRepo]'s persisted [AutomationContext.codingExecution]
  /// confidence, forced to [AutomationConfidence.gated] once
  /// [_overageDetectedThisSession] is `true` regardless of what's
  /// persisted — shared by [_runCodingExecution]'s completion-flip
  /// decision and [getTicketById]'s `executionAwaitingReview`
  /// computation so the two can't disagree about whether an
  /// overage-affected run counts as gated (post-`/verify` correction:
  /// [getTicketById] originally read the repository directly, so the
  /// "ready for review" banner never appeared after an overage forced
  /// `gated` — [_runCodingExecution] correctly skipped the auto-flip, but
  /// nothing surfaced the resulting awaiting-review state instead).
  Future<AutomationConfidence> _effectiveCodingExecutionConfidence(
    AutomationSettingsRepository automationRepo,
  ) async {
    return _overageDetectedThisSession
        ? AutomationConfidence.gated
        : await automationRepo.getConfidence(AutomationContext.codingExecution);
  }

  /// Pops the next queued Task id (if any) off [_executionQueue] and
  /// starts its run via [_runCodingExecution], skipping ids that no
  /// longer resolve to a ticket (defensive — not expected in practice).
  Future<void> _dequeueNext() async {
    if (_executionQueue.isEmpty) return;
    final nextId = _executionQueue.removeAt(0);
    final next = await _repository.getTicketById(nextId);
    if (next == null) {
      unawaited(_dequeueNext());
      return;
    }
    _inFlightExecutionTaskId = next.id;
    unawaited(_runCodingExecution(next));
  }

  /// Assembles the plain-text context a spawned coding-execution chat
  /// opens with: [task]'s title/description, plus an instruction to open
  /// a PR as the last step of the run using the available git/bash tools,
  /// ending the final reply with exactly one line — `EXECUTION: PR_OPENED`
  /// followed by the PR url on success, or `EXECUTION: NO_PR` if it
  /// couldn't — mirroring [_assembleStageContext]'s existing
  /// `designSync`/`"DESIGN GATE: APPROVED"` convention for a parseable
  /// completion signal.
  String _assembleExecutionContext(Ticket task) {
    final buffer = StringBuffer()..writeln('# ${task.title}');
    final description = task.description;
    if (description != null && description.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(description);
    }
    buffer
      ..writeln()
      ..writeln(
        'Implement this Task using the available file, git, and bash '
        'tools. As the last step, open a pull request for your changes. '
        'End your reply with exactly one line: "EXECUTION: PR_OPENED '
        '<url>" if the PR was opened successfully, or "EXECUTION: NO_PR" '
        'if it could not be.',
      );
    return buffer.toString().trim();
  }

  /// Whether [taskId]'s most recently created `"Coding Execution — "`-
  /// prefixed `chat` child's most recent comment is a
  /// [CommentAuthorType.ai] reply whose content contains the literal
  /// `EXECUTION: PR_OPENED` line — mirrors [_designSyncApproved]'s own
  /// lookup shape exactly (that one takes the *Story's* id and finds its
  /// `"Design Sync — "`-prefixed chat; this takes the *Task's* id and
  /// finds its `"Coding Execution — "`-prefixed chat), so both
  /// [_runCodingExecution] and [getTicketById] can call it identically
  /// without needing to know the spawned chat's own id.
  Future<bool> _executionSucceededWithPr(String taskId) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return false;
    final chats = await _repository.getTicketsByParent(
      taskId,
      types: const [TicketType.chat],
    );
    final executionChats =
        chats.where((c) => c.title.startsWith('Coding Execution — ')).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (executionChats.isEmpty) return false;
    final comments = await commentRepo.getCommentsForTicket(
      executionChats.first.id,
    );
    if (comments.isEmpty) return false;
    final mostRecent = comments.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    return mostRecent.authorType == CommentAuthorType.ai &&
        mostRecent.content.contains('EXECUTION: PR_OPENED');
  }

  /// Whether [parentId]'s most recently created `chat` child ticket
  /// already has at least one [CommentAuthorType.ai] comment — the proxy
  /// this change uses for "that stage's chat has completed," since a
  /// [ChatCubit] reply's in-progress `streamingText` is never persisted
  /// mid-stream (see `chat_cubit.dart`). Returns `false` if constructed
  /// without a [CommentRepository] (see the constructor's dartdoc), or if
  /// no `chat` child exists yet.
  Future<bool> _mostRecentChatHasTerminalReply(String parentId) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return false;

    final chats = await _repository.getTicketsByParent(
      parentId,
      types: const [TicketType.chat],
    );
    if (chats.isEmpty) return false;

    final mostRecent = chats.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final comments = await commentRepo.getCommentsForTicket(mostRecent.id);
    return comments.any((c) => c.authorType == CommentAuthorType.ai);
  }

  /// Creates a `chat`-type child ticket for [stage] under [parent],
  /// posts an auto-assembled [CommentAuthorType.system] context comment
  /// Resolves [phase] to its currently configured [AgentModel], via
  /// [_modelRoutingRepository]. Falls back to [AgentModel.sonnet] — the
  /// hardcoded default every call site used before per-phase routing
  /// existed — when the cubit was constructed without a
  /// [ModelRoutingRepository] (see the constructor's dartdoc). Added for
  /// `aion-arch/changes/per-phase-tier-based-model-routing`.
  Future<AgentModel> _resolveModel(ModelPhase phase) async {
    final repo = _modelRoutingRepository;
    if (repo == null) return AgentModel.sonnet;
    return repo.getModelForPhase(phase);
  }

  /// (see [_assembleStageContext]), then calls the configured
  /// [AgentModelClient] and persists the streamed reply via
  /// [ChatCubit.runChatTurn] — the same accumulate-then-persist logic
  /// [ChatCubit.sendMessage] uses, so the spawn path and the user-message
  /// path can't drift apart. Returns the spawned chat ticket's id, or
  /// `null` if constructed without an [AgentModelClient]/
  /// [CommentRepository] (see the constructor's dartdoc) — real usage
  /// (`app_router.dart`) always supplies both. The model is resolved via
  /// [_resolveModel] using [stage]'s [SddStageModelPhase.modelPhase] (see
  /// `aion-arch/changes/per-phase-tier-based-model-routing`), replacing
  /// the previous hardcoded [AgentModel.sonnet] default. For
  /// [SddStage.designBrief] specifically, also creates a `page`-type
  /// design ticket (`"Design — <parent.title>"`) and links it to
  /// [parent] via [TicketLinkRepository.createLink] before the chat
  /// itself is created — see [_linkedDesignPage]. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  Future<String?> _spawnStageChat(Ticket parent, SddStage stage) async {
    final client = _agentClient;
    final commentRepo = _commentRepository;
    if (client == null || commentRepo == null) return null;

    final now = DateTime.now();

    if (stage == SddStage.designBrief) {
      // Guarded on _linkRepository, not just the link-creation call —
      // without it, _linkedDesignPage could never discover the page
      // (it walks links, not title text), leaving `designBrief` stuck
      // at `awaitingDesignPaste` forever. Skip creating the orphan
      // rather than leave one behind.
      final linkRepo = _linkRepository;
      if (linkRepo != null) {
        final page = Ticket(
          id: _uuid.v4(),
          ticketId: '',
          type: TicketType.page,
          title: 'Design — ${parent.title}',
          status: TicketStatus.backlog,
          createdAt: now,
          updatedAt: now,
        );
        await _repository.createTicket(page);
        await linkRepo.createLink(
          sourceTicketId: page.id,
          targetTicketId: parent.id,
          linkType: TicketLinkType.relatesTo,
        );
      }
    }

    final chatTicket = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.chat,
      title: '${_stagePresentName(stage)} — ${parent.title}',
      status: TicketStatus.backlog,
      parentId: parent.id,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createTicket(chatTicket);
    final persistedChat = await _repository.getTicketById(chatTicket.id);
    if (persistedChat == null) return null;

    final context = await _assembleStageContext(parent, stage);
    await commentRepo.addComment(
      TicketComment(
        id: '',
        ticketId: persistedChat.id,
        content: context,
        authorType: CommentAuthorType.system,
        createdAt: DateTime.now(),
      ),
    );

    await ChatCubit.runChatTurn(
      client: client,
      commentRepo: commentRepo,
      chatTicketId: persistedChat.id,
      prompt: context,
      model: await _resolveModel(stage.modelPhase),
    );
    return persistedChat.id;
  }

  /// Assembles the plain-text context a spawned stage chat opens with:
  /// [parent]'s title/description, and — for [SddStage.verifying]/
  /// [SddStage.archived] — its direct children's titles and statuses, or
  /// — for [SddStage.designBrief]/[SddStage.designSync] — the existing
  /// design-token file contents (see [_readTokenFilesForContext]) and,
  /// for [SddStage.designSync] specifically, the linked design Page's
  /// pasted content (see [_linkedDesignPage]). No embeddings, no
  /// repo-map-lite involvement (see proposal.md's Out of scope).
  Future<String> _assembleStageContext(Ticket parent, SddStage stage) async {
    final buffer = StringBuffer()
      ..writeln('# ${parent.title}');
    final description = parent.description;
    if (description != null && description.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(description);
    }

    if (stage == SddStage.verifying || stage == SddStage.archived) {
      final nextRank = parent.type == TicketType.story
          ? TicketType.task
          : TicketType.story;
      final children = await _repository.getTicketsByParent(
        parent.id,
        types: [nextRank],
      );
      if (children.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(nextRank == TicketType.task ? '## Tasks' : '## Stories');
        for (final child in children) {
          final statusLabel = nextRank == TicketType.task
              ? child.status.name
              : (child.sddStage?.name ?? 'not started');
          buffer.writeln('- ${child.title} ($statusLabel)');
        }
      }
    } else if (stage == SddStage.designBrief) {
      buffer
        ..writeln()
        ..writeln('## Existing design system')
        ..writeln(await _readTokenFilesForContext());
      buffer
        ..writeln()
        ..writeln(
          'Produce a ready-to-paste Claude Design prompt for this Story, '
          'covering: Context, Existing design system (the tokens above), '
          'Feature to design, Components to specify, Export requirements '
          '(Flutter Color/TextStyle/EdgeInsets values, both Arctic and '
          'Obsidian themes, no Material widgets), and a Mockup request.',
        );
    } else if (stage == SddStage.designSync) {
      final page = await _linkedDesignPage(parent.id);
      buffer
        ..writeln()
        ..writeln('## Pasted design export')
        ..writeln(page?.description ?? '(none pasted yet)')
        ..writeln()
        ..writeln('## Existing design system')
        ..writeln(await _readTokenFilesForContext())
        ..writeln()
        ..writeln(
          'Check the pasted design export above for: (1) any Material '
          'widget reference (Card, ElevatedButton, Scaffold, ThemeData, '
          'etc. — Aion is Non-Material, see project.md), (2) whether every '
          'referenced color matches one of the existing tokens above or is '
          'a clearly new, semantically named one. List any issues found. '
          'End your reply with exactly one line: "DESIGN GATE: APPROVED" '
          'if there are no issues, or "DESIGN GATE: PENDING" if there are.',
        );
    }

    return buffer.toString().trim();
  }

  /// Reads `aion_colors.dart`/`aion_text.dart`/`aion_radius.dart`'s
  /// contents off disk for inclusion as plain-text context — the same
  /// static-injection approach `/design-brief`/`/design-sync`'s own
  /// `SKILL.md` `cat`s these files for, ported to Dart
  /// `File.readAsString`. No tool access involved; this is [TicketsCubit]
  /// reading files for context assembly, the same category of
  /// desktop-only capability [_gitProjector]/[_projectRootPath] already
  /// gates. Returns an empty string (not an error) if [_projectRootPath]
  /// is unset or a file is missing — mobile/web has neither a filesystem
  /// root nor UI Story design-gate stages triggering in practice
  /// (Task/Story execution is desktop-only already), so this degrades
  /// gracefully rather than throwing. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  Future<String> _readTokenFilesForContext() async {
    final root = _projectRootPath;
    if (root == null) return '';
    const relativePaths = [
      'lib/design_system/tokens/aion_colors.dart',
      'lib/design_system/tokens/aion_text.dart',
      'lib/design_system/tokens/aion_radius.dart',
    ];
    final buffer = StringBuffer();
    for (final relativePath in relativePaths) {
      final file = File(p.join(root, relativePath));
      if (await file.exists()) {
        buffer
          ..writeln('### $relativePath')
          ..writeln(await file.readAsString());
      }
    }
    return buffer.toString();
  }

  /// Display name for [stage], used in a spawned chat ticket's title —
  /// present-progressive for every stage except [SddStage.designBrief]/
  /// [SddStage.designSync], which read naturally as their plain node
  /// name instead (design.md §1.3).
  String _stagePresentName(SddStage stage) => switch (stage) {
    SddStage.exploring => 'Exploring',
    SddStage.proposed => 'Proposed',
    SddStage.designBrief => 'Design Brief',
    SddStage.designSync => 'Design Sync',
    SddStage.verifying => 'Verifying',
    SddStage.archived => 'Archived',
  };

  /// Fires an async embedding-regen call for [ticket] and writes the
  /// result back via [TicketRepository.updateEmbedding] once it
  /// resolves. Never awaited by callers — ticket save must never block
  /// on this. No-ops if no [_embeddingProvider] was provided (see the
  /// constructor's dartdoc).
  Future<void> _triggerEmbeddingRegen(Ticket ticket) async {
    final provider = _embeddingProvider;
    if (provider == null) return;
    final bytes = await provider.embed(
      '${ticket.title}\n\n${ticket.description ?? ''}',
    );
    await _repository.updateEmbedding(ticket.id, bytes);
  }

  /// Projects [ticket] to its Markdown file and commits it, labelled
  /// [eventLabel]. No-ops if no [_gitProjector]/[_projectRootPath] was
  /// provided (see the constructor's dartdoc) — desktop-only in
  /// practice, since `WorkspaceShell` only supplies these on desktop.
  ///
  /// **Known gap**: the "restored from trash" trigger event from
  /// design.md is not wired anywhere — that action lives in
  /// `TrashCubit`, which has no access to a projector/root path today,
  /// and wiring it wasn't in this task's scope (`tasks.md` T25 only
  /// names `tickets_cubit.dart`). Flagged rather than silently expanded.
  Future<void> _triggerGitProjection(Ticket ticket, String eventLabel) async {
    final projector = _gitProjector;
    final rootPath = _projectRootPath;
    if (projector == null || rootPath == null) return;
    await projector.project(ticket, rootPath, eventLabel);
  }

  /// Builds the full descendant-id set of [rootId] by walking `parentId`
  /// forward through [all]. Shared by [getValidParentCandidates] and
  /// [updateTicketParent] so both apply the identical cycle definition.
  Set<String> _descendantIds(String rootId, List<Ticket> all) {
    final childrenByParent = <String, List<Ticket>>{};
    for (final t in all) {
      final p = t.parentId;
      if (p != null) {
        childrenByParent.putIfAbsent(p, () => []).add(t);
      }
    }
    final result = <String>{};
    void walk(String id) {
      for (final child in childrenByParent[id] ?? const []) {
        if (result.add(child.id)) walk(child.id);
      }
    }

    walk(rootId);
    return result;
  }

  /// Fetches the ticket with internal id [id]. Emits [TicketsLoading] then
  /// [TicketDetailLoaded] on success, or [TicketsError] if not found or the
  /// repository call throws. For an `epic`/`story` ticket, also fetches
  /// its direct children and evaluates [advanceSddStage]'s precondition
  /// for the ticket's current stage, populating
  /// [TicketDetailLoaded.canAdvanceSddStage] and, when that's `false`,
  /// [TicketDetailLoaded.sddStageBlockReason]. For a `story` ticket
  /// specifically, also computes [TicketDetailLoaded.needsDesignReview]
  /// via [_storyNeedsDesignReview] against its current child Tasks
  /// (`null` if none exist yet), and — when that's `true` —
  /// [TicketDetailLoaded.linkedDesignPage] via [_linkedDesignPage].
  /// Added for `aion-arch/changes/sdd-design-gate`. For a `task` ticket,
  /// also computes [TicketDetailLoaded.isExecuting],
  /// [TicketDetailLoaded.executionQueuePosition], and
  /// [TicketDetailLoaded.executionAwaitingReview] from the in-memory
  /// coding-execution queue state. Added for
  /// `aion-arch/changes/task-to-coding-execution-trigger`.
  Future<void> getTicketById(String id) async {
    emit(const TicketsLoading());
    try {
      final ticket = await _repository.getTicketById(id);
      if (ticket == null) {
        emit(const TicketsError('', reason: TicketsErrorReason.notFound));
        return;
      }
      final check = await _sddStageAdvanceCheck(ticket);

      bool? needsDesignReview;
      Ticket? linkedDesignPage;
      if (ticket.type == TicketType.story) {
        final tasks = await _repository.getTicketsByParent(
          ticket.id,
          types: const [TicketType.task],
        );
        needsDesignReview = tasks.isEmpty
            ? null
            : _storyNeedsDesignReview(tasks);
        if (needsDesignReview == true) {
          linkedDesignPage = await _linkedDesignPage(ticket.id);
        }
      }

      var isExecuting = false;
      int? executionQueuePosition;
      var executionAwaitingReview = false;
      if (ticket.type == TicketType.task) {
        isExecuting = _inFlightExecutionTaskId == ticket.id;
        final queueIndex = _executionQueue.indexOf(ticket.id);
        // 1-based: the first entry in the FIFO queue is "next in line"
        // (position 1) once the in-flight run finishes — nothing *in the
        // queue* is ahead of it. The in-flight run itself never reaches
        // this branch (isExecuting is checked separately above).
        executionQueuePosition = queueIndex >= 0 ? queueIndex + 1 : null;
        if (!isExecuting &&
            executionQueuePosition == null &&
            ticket.status == TicketStatus.inProgress) {
          final prConfirmed = await _executionSucceededWithPr(ticket.id);
          final automationRepo = _automationSettingsRepository;
          final confidence = automationRepo == null
              ? null
              : await _effectiveCodingExecutionConfidence(automationRepo);
          executionAwaitingReview =
              prConfirmed && confidence == AutomationConfidence.gated;
        }
      }

      emit(
        TicketDetailLoaded(
          ticket,
          canAdvanceSddStage: check.canAdvance,
          sddStageBlockReason: check.blockReason,
          needsDesignReview: needsDesignReview,
          linkedDesignPage: linkedDesignPage,
          isExecuting: isExecuting,
          executionQueuePosition: executionQueuePosition,
          executionAwaitingReview: executionAwaitingReview,
        ),
      );
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Returns the total number of tickets that would move to trash if
  /// every id in [ids] were trashed right now, via
  /// [TicketRepository.previewTrashCount] — the exact same cascade
  /// computation [trashTicket]/[trashTickets] themselves use (including
  /// descendants that are already trashed, e.g. a child trashed
  /// individually earlier whose still-live parent is being trashed now),
  /// so the confirm dialog's preview always matches the actual outcome.
  /// Query only, no state emitted. Used by both the single-ticket
  /// (`TicketOverflowMenu`) and bulk (`TicketSelectionBar`) delete flows.
  Future<int> previewTrashCount(List<String> ids) {
    return _repository.previewTrashCount(ids);
  }

  /// Moves ticket [id] to trash via [TicketRepository.trashTicket].
  /// Context-aware on the state active before the call: if it was
  /// [TicketDetailLoaded] (the caller is `TicketDetailScreen`), emits
  /// [TicketTrashed] on success; any other (list/board-shaped) previous
  /// state re-fetches (re-applying the filters [searchTickets] was last
  /// called with, requesting at least as many tickets as were already
  /// loaded) and emits [TicketsLoaded] instead, so
  /// `TicketsListScreen`/`TicketBoardView` never fall into a blank state.
  /// Trash never fails except on a genuine unexpected repository error,
  /// which emits [TicketsError].
  Future<void> trashTicket(String id) async {
    _searchGeneration++;
    final previousState = state;
    final currentTickets = switch (previousState) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsBatchTrashed(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };
    emit(const TicketTrashing());
    try {
      await _repository.trashTicket(id);
      final trashed = await _repository.getTicketById(id);
      if (trashed != null) {
        unawaited(_triggerGitProjection(trashed, 'trashed'));
      }
      if (previousState is TicketDetailLoaded) {
        emit(const TicketTrashed());
      } else {
        final page = await _repository.searchTickets(
          query: _lastQuery,
          status: _lastStatus,
          type: _lastType,
          priority: _lastPriority,
          limit: max(_pageSize, currentTickets.length),
        );
        emit(TicketsLoaded(page.tickets, hasMore: page.hasMore));
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Moves every ticket in [ids] to trash via
  /// [TicketRepository.trashTickets]. Always triggered from
  /// `TicketsListScreen`'s selection mode (list or board rendering) — no
  /// detail-screen caller to special-case, unlike [trashTicket]. Emits
  /// [TicketsBatchTrashing] then [TicketsBatchTrashed] (refreshed page +
  /// actual trashed count) on success, or [TicketsError] on an
  /// unexpected failure. The refresh re-applies the filters
  /// [searchTickets] was last called with and requests at least as many
  /// tickets as were already loaded.
  Future<void> trashTickets(List<String> ids) async {
    _searchGeneration++;
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsBatchTrashed(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };
    emit(const TicketsBatchTrashing());
    try {
      final trashedCount = await _repository.trashTickets(ids);
      // Projects only the explicitly-requested ids, not their cascaded
      // descendants (also trashed by trashTickets, but not individually
      // enumerable from its return value) — a documented scope
      // simplification, not an oversight.
      for (final id in ids) {
        final trashed = await _repository.getTicketById(id);
        if (trashed != null) {
          unawaited(_triggerGitProjection(trashed, 'trashed'));
        }
      }
      final page = await _repository.searchTickets(
        query: _lastQuery,
        status: _lastStatus,
        type: _lastType,
        priority: _lastPriority,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(
        TicketsBatchTrashed(page.tickets, trashedCount, hasMore: page.hasMore),
      );
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Loads the Documentation-section relations for the `page`/`resource`
  /// ticket with id [ticketId] — its direct sub-page/resource children (if
  /// it's a `page`) and its `TicketLink`s, grouped into [linkedTickets]
  /// (the other side is a board type: epic/story/task/chat) and
  /// [backlinks] (the other side is itself `page`/`resource`) — then
  /// re-emits [TicketDetailLoaded] with those fields populated. No-ops
  /// (does not emit) if the ticket isn't found, isn't a `page`/`resource`
  /// type, or the cubit has since moved on to a different ticket's detail
  /// state (a stale response from an earlier navigation). Only actually
  /// populates [linkedTickets]/[backlinks] when constructed with a
  /// [TicketLinkRepository] — every other call site is unaffected by this
  /// optional dependency, same rationale as [_embeddingProvider]/
  /// [_gitProjector]/[_projectRootPath].
  Future<void> loadDocumentRelations(String ticketId) async {
    final ticket = await _repository.getTicketById(ticketId);
    if (ticket == null) return;
    if (ticket.type != TicketType.page && ticket.type != TicketType.resource) {
      return;
    }

    final childDocs = ticket.type == TicketType.page
        ? await _repository.getTicketsByParent(
            ticket.id,
            types: const [TicketType.page, TicketType.resource],
          )
        : const <Ticket>[];

    final linkedTickets = <Ticket>[];
    final backlinks = <Ticket>[];
    final linkRepo = _linkRepository;
    if (linkRepo != null) {
      final links = await linkRepo.getLinksForTicket(ticket.id);
      for (final link in links) {
        final otherId = link.sourceTicketId == ticket.id
            ? link.targetTicketId
            : link.sourceTicketId;
        final other = await _repository.getTicketById(otherId);
        if (other == null) continue;
        if (other.type == TicketType.page ||
            other.type == TicketType.resource) {
          backlinks.add(other);
        } else {
          linkedTickets.add(other);
        }
      }
    }

    final current = state;
    if (current is! TicketDetailLoaded || current.ticket.id != ticket.id) {
      return;
    }
    emit(
      TicketDetailLoaded(
        ticket,
        childDocs: childDocs,
        linkedTickets: linkedTickets,
        backlinks: backlinks,
      ),
    );
  }
}
