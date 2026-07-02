// domain/repositories/ticket_repository.dart — TicketRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// Read/write access to [Ticket] persistence. Implemented by the data layer
/// ([DriftTicketRepository]); UI and domain code depend only on this
/// interface, never on a concrete data source.
abstract interface class TicketRepository {
  /// Returns all tickets, most recently created first.
  Future<List<Ticket>> getAllTickets();

  /// Returns the ticket with internal id [id], or `null` if none exists.
  Future<Ticket?> getTicketById(String id);

  /// Persists [ticket]. Implementations generate the human-readable
  /// [Ticket.ticketId] (prefix + sequence) at insert time, so
  /// [ticket.ticketId] on the argument is ignored.
  Future<void> createTicket(Ticket ticket);
}
