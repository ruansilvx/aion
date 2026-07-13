// presentation/cubit/tickets_cubit.dart — TicketsCubit business logic (presentation layer).

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

  /// Fetches all tickets. Emits [TicketsLoading] then [TicketsLoaded] on
  /// success, or [TicketsError] if the repository call throws.
  Future<void> loadTickets() async {
    emit(const TicketsLoading());
    try {
      final tickets = await _repository.getAllTickets();
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
}
