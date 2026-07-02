import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';

class TicketsCubit extends Cubit<TicketsState> {
  TicketsCubit(this._repository) : super(const TicketsInitial());

  final TicketRepository _repository;
  static const _uuid = Uuid();

  Future<void> loadTickets() async {
    emit(const TicketsLoading());
    try {
      final tickets = await _repository.getAllTickets();
      emit(TicketsLoaded(tickets));
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

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

  Future<void> getTicketById(String id) async {
    emit(const TicketsLoading());
    try {
      final ticket = await _repository.getTicketById(id);
      if (ticket == null) {
        emit(const TicketsError('Ticket not found'));
      } else {
        emit(TicketDetailLoaded(ticket));
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }
}
