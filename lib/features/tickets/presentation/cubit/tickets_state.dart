import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';

sealed class TicketsState extends Equatable {
  const TicketsState();

  @override
  List<Object?> get props => [];
}

class TicketsInitial extends TicketsState {
  const TicketsInitial();
}

class TicketsLoading extends TicketsState {
  const TicketsLoading();
}

class TicketsLoaded extends TicketsState {
  const TicketsLoaded(this.tickets);

  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

class TicketsError extends TicketsState {
  const TicketsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class TicketCreating extends TicketsState {
  const TicketCreating(this.tickets);

  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

class TicketCreated extends TicketsState {
  const TicketCreated(this.tickets);

  final List<Ticket> tickets;

  @override
  List<Object?> get props => [tickets];
}

class TicketDetailLoaded extends TicketsState {
  const TicketDetailLoaded(this.ticket);

  final Ticket ticket;

  @override
  List<Object?> get props => [ticket];
}
