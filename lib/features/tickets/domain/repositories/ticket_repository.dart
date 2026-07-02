import 'package:aion/features/tickets/domain/entities/ticket.dart';

abstract interface class TicketRepository {
  Future<List<Ticket>> getAllTickets();
  Future<Ticket?> getTicketById(String id);
  Future<void> createTicket(Ticket ticket);
}
