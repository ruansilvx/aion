// presentation/cubit/tickets_cubit.dart — TicketsCubit business logic (presentation layer).

import 'dart:math' show max;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';

/// Loads, lists, and creates tickets via [TicketRepository]. Root-scoped —
/// provided once at the app root, not per-screen.
class TicketsCubit extends Cubit<TicketsState> {
  /// Creates a [TicketsCubit] backed by [_repository].
  TicketsCubit(this._repository) : super(const TicketsInitial());

  final TicketRepository _repository;
  static const _uuid = Uuid();

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
  /// [status] always starts at [TicketStatus.backlog]. Emits
  /// [TicketCreating] (carrying the list as it was before this call) then
  /// [TicketCreated] (carrying the refreshed page) on success, or
  /// [TicketsError] if the repository call throws. The refresh re-applies
  /// the filters [searchTickets] was last called with (rather than
  /// fetching every ticket) and requests at least as many tickets as were
  /// already loaded, so this doesn't silently drop an active search/filter
  /// or collapse an infinite-scrolled list back down to one page.
  Future<void> createTicket({
    required TicketType type,
    required String title,
    String? description,
    TicketPriority priority = TicketPriority.none,
    String? parentId,
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
      final page = await _repository.searchTickets(
        query: _lastQuery,
        status: _lastStatus,
        type: _lastType,
        priority: _lastPriority,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(TicketCreated(page.tickets, hasMore: page.hasMore));
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Moves ticket [id] to [status]. Emits [TicketStatusUpdating] (carrying
  /// the list with [id]'s status optimistically replaced) immediately,
  /// then [TicketStatusUpdated] (carrying the re-fetched page) once the
  /// repository call succeeds, or [TicketsError] if it throws. The
  /// refresh re-applies the filters [searchTickets] was last called with
  /// and requests at least as many tickets as were already loaded, so a
  /// background status update (e.g. a board drag) never collapses an
  /// infinite-scrolled list back down to one page.
  Future<void> updateTicketStatus(String id, TicketStatus status) async {
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
  Future<void> updateTicket(Ticket ticket) async {
    try {
      await _repository.updateTicket(ticket);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Changes [ticket]'s status from the ticket-detail screen. Persists via
  /// the same [TicketRepository.updateTicketStatus] the board's drag/
  /// `MoveToStatusMenu` path calls, then re-fetches and emits
  /// [TicketDetailLoaded] with the refreshed ticket — unlike
  /// [updateTicketStatus], which emits list-shaped optimistic states built
  /// for the board and would fall through `TicketDetailScreen`'s state
  /// switch. Emits [TicketsError] on failure.
  Future<void> changeTicketStatus(Ticket ticket, TicketStatus status) async {
    try {
      await _repository.updateTicketStatus(ticket.id, status);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
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
  /// rejects any attempt to set a non-null parent on an [TicketType.epic]
  /// ticket — epics are always subtree roots (see project.md's watcher
  /// system) — and any candidate parent whose type cannot structurally
  /// parent [ticket]'s type per [TicketTypeHierarchy.canParent], via the
  /// same rejection path. On a valid reparent, persists via
  /// [TicketRepository.updateTicketParent] and emits the refreshed
  /// [TicketDetailLoaded].
  Future<void> updateTicketParent(Ticket ticket, String? newParentId) async {
    if (newParentId != null) {
      if (newParentId == ticket.id) {
        await _emitInvalidParent(ticket.id);
        return;
      }
      if (ticket.type == TicketType.epic) {
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
  /// repository call throws.
  Future<void> getTicketById(String id) async {
    emit(const TicketsLoading());
    try {
      final ticket = await _repository.getTicketById(id);
      if (ticket == null) {
        emit(const TicketsError('', reason: TicketsErrorReason.notFound));
      } else {
        emit(TicketDetailLoaded(ticket));
      }
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
      final page = await _repository.searchTickets(
        query: _lastQuery,
        status: _lastStatus,
        type: _lastType,
        priority: _lastPriority,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(TicketsBatchTrashed(page.tickets, trashedCount, hasMore: page.hasMore));
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }
}
