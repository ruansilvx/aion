// presentation/cubit/tickets_cubit.dart — TicketsCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/exceptions/ticket_has_children_exception.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';

/// Loads, lists, and creates tickets via [TicketRepository]. Root-scoped —
/// provided once at the app root, not per-screen.
class TicketsCubit extends Cubit<TicketsState> {
  /// Creates a [TicketsCubit] backed by [_repository].
  TicketsCubit(this._repository) : super(const TicketsInitial());

  final TicketRepository _repository;
  static const _uuid = Uuid();

  /// Fetches tickets matching every non-null filter (ANDed) — see
  /// [TicketRepository.searchTickets]. Called with no arguments, this is
  /// equivalent to fetching every ticket (most recent first). Emits
  /// [TicketsLoading] first only when nothing is on screen yet
  /// ([TicketsInitial]/[TicketsError]/[TicketDeleted]) — once a ticket
  /// list is already showing, the previous list stays visible until the
  /// new results arrive, so re-searching/re-filtering doesn't flash a
  /// spinner over the existing list on every keystroke. Emits
  /// [TicketsLoaded] on success, [TicketsError] if the repository call
  /// throws.
  Future<void> searchTickets({
    String? query,
    TicketStatus? status,
    TicketType? type,
    TicketPriority? priority,
  }) async {
    final hasVisibleList = switch (state) {
      TicketsLoaded() ||
      TicketCreating() ||
      TicketCreated() ||
      TicketStatusUpdating() ||
      TicketStatusUpdated() => true,
      _ => false,
    };
    if (!hasVisibleList) emit(const TicketsLoading());

    try {
      final tickets = await _repository.searchTickets(
        query: query,
        status: status,
        type: type,
        priority: priority,
      );
      emit(TicketsLoaded(tickets));
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Creates a new ticket of [type] with [title], then reloads the list.
  ///
  /// [status] always starts at [TicketStatus.backlog]. Emits
  /// [TicketCreating] (carrying the list as it was before this call) then
  /// [TicketCreated] (carrying the refreshed list) on success, or
  /// [TicketsError] if the repository call throws.
  Future<void> createTicket({
    required TicketType type,
    required String title,
    String? description,
    TicketPriority priority = TicketPriority.none,
    String? parentId,
  }) async {
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreating(:final tickets) => tickets,
      TicketStatusUpdating(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
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
      final tickets = await _repository.getAllTickets();
      emit(TicketCreated(tickets));
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Moves ticket [id] to [status]. Emits [TicketStatusUpdating] (carrying
  /// the list with [id]'s status optimistically replaced) immediately,
  /// then [TicketStatusUpdated] (carrying the re-fetched list) once the
  /// repository call succeeds, or [TicketsError] if it throws.
  Future<void> updateTicketStatus(String id, TicketStatus status) async {
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdating(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      _ => <Ticket>[],
    };

    final optimistic = [
      for (final t in currentTickets)
        if (t.id == id) t.copyWith(status: status) else t,
    ];
    emit(TicketStatusUpdating(optimistic));

    try {
      await _repository.updateTicketStatus(id, status);
      final tickets = await _repository.getAllTickets();
      emit(TicketStatusUpdated(tickets));
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
  /// all tickets except [ticket] itself and any of its descendants
  /// (reachable by walking `parentId` forward). Setting either as the new
  /// parent would create a cycle. Performs a query only — does not emit a
  /// state, since this feeds a picker overlay rather than driving the
  /// detail screen's own render state.
  Future<List<Ticket>> getValidParentCandidates(Ticket ticket) async {
    final all = await _repository.getAllTickets();
    final descendantIds = _descendantIds(ticket.id, all);
    return all
        .where((t) => t.id != ticket.id && !descendantIds.contains(t.id))
        .toList();
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
  /// system) — via the same rejection path. On a valid reparent, persists
  /// via [TicketRepository.updateTicketParent] and emits the refreshed
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

  /// Deletes the ticket with internal id [id] via
  /// [TicketRepository.deleteTicket]. Emits [TicketDeleting] immediately.
  ///
  /// Recovery on both success and the "blocked by children" failure
  /// branches on the state active *before* this call started
  /// ([previousState]): if it was [TicketDetailLoaded] (the caller is
  /// `TicketDetailScreen`), behavior is unchanged from before this
  /// context-aware branching existed — [TicketDeleted] on success, or a
  /// re-emitted [TicketDetailLoaded] with the unchanged ticket after the
  /// classified error. For any other (list/board-shaped) previous state,
  /// both branches instead re-fetch and emit [TicketsLoaded] with the
  /// refreshed list, so `TicketsListScreen`/`TicketBoardView` never fall
  /// into a blank or stale state when a delete is triggered from a list
  /// row or board card.
  ///
  /// On failure from [TicketHasChildrenException], emits
  /// [TicketsError(reason: TicketsErrorReason.hasChildren)] (carrying the
  /// blocking child count) — solely so a listener (e.g. `AppToast`) can
  /// react — before the state-dependent recovery emission above; the
  /// delete is blocked, not "confirmed but failed." Any other failure
  /// emits a generic [TicketsError] — including "not found," which by
  /// this point would only happen from a concurrent delete elsewhere, not
  /// a normal user path.
  Future<void> deleteTicket(String id) async {
    final previousState = state;
    emit(const TicketDeleting());
    try {
      await _repository.deleteTicket(id);
      if (previousState is TicketDetailLoaded) {
        emit(const TicketDeleted());
      } else {
        emit(TicketsLoaded(await _repository.getAllTickets()));
      }
    } on TicketHasChildrenException catch (e) {
      emit(
        TicketsError(
          '',
          reason: TicketsErrorReason.hasChildren,
          childCount: e.childCount,
        ),
      );
      if (previousState is TicketDetailLoaded) {
        final ticket = await _repository.getTicketById(id);
        if (ticket != null) {
          emit(TicketDetailLoaded(ticket));
        }
      } else {
        emit(TicketsLoaded(await _repository.getAllTickets()));
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }
}
