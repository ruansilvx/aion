// domain/repositories/ticket_repository.dart — TicketRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';

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

  /// Updates only the [status] (and `updatedAt`) of the ticket with id
  /// [id]. Does not touch any other field. Throws if [id] does not exist.
  Future<void> updateTicketStatus(String id, TicketStatus status);

  /// Updates only the [parentId] (and `updatedAt`) of the ticket with id
  /// [id]. Does not touch any other field, and performs no validation —
  /// callers (see `TicketsCubit.updateTicketParent`) are responsible for
  /// rejecting self-parenting and cycles before calling this. Pass `null`
  /// to clear the parent. Throws if [id] does not exist.
  Future<void> updateTicketParent(String id, String? parentId);

  /// Persists [ticket]'s `title`, `description`, `priority`, `type`,
  /// `estimate`, and `timeSpent`, plus a fresh `updatedAt`. Does not touch
  /// `status` (use [updateTicketStatus]), `parentId`, `embedding`, `id`, or
  /// `ticketId`. Throws if `ticket.id` does not exist.
  Future<void> updateTicket(Ticket ticket);

  /// Deletes the ticket with internal id [id], cascading to its comments
  /// and any `ticket_links` rows that reference it in either direction.
  ///
  /// Throws [StateError] if [id] does not exist. Throws
  /// [TicketHasChildrenException] — without deleting anything — if any
  /// other ticket has `parentId == id`; the caller must reparent or delete
  /// those children first. Structural children are never cascade-deleted.
  Future<void> deleteTicket(String id);
}
