// domain/repositories/ticket_repository.dart — TicketRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Read/write access to [Ticket] persistence. Implemented by the data layer
/// ([DriftTicketRepository]); UI and domain code depend only on this
/// interface, never on a concrete data source.
abstract interface class TicketRepository {
  /// Returns all live (non-trashed) tickets, most recently created first.
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

  /// Moves [id] and every ticket in its structural subtree into trash
  /// (sets `deletedAt`, deletes nothing). Never blocked by children —
  /// they're cascaded into trash alongside [id] instead. Throws
  /// [StateError] if [id] does not exist.
  Future<void> trashTicket(String id);

  /// Moves every ticket in [ids] — and each one's full structural
  /// subtree — into trash in one call. Returns the total number of
  /// tickets actually moved (== [ids] plus every cascaded descendant,
  /// deduplicated), so the caller can report an accurate count even when
  /// it's larger than `ids.length`. Ids that don't exist are silently
  /// skipped.
  Future<int> trashTickets(List<String> ids);

  /// Returns the total number of tickets that would move to trash if
  /// every id in [ids] were trashed right now — existing ids plus every
  /// structural descendant (live *or already trashed*), deduplicated.
  /// Query only, performs no writes. Mirrors [trashTickets]'s own cascade
  /// computation exactly, so a cascade preview shown before a trash
  /// action always matches what the action will actually touch —
  /// including a descendant that's already in trash (e.g. a child
  /// trashed individually earlier, whose still-live parent is being
  /// trashed now).
  Future<int> previewTrashCount(List<String> ids);

  /// Restores [id] out of trash, along with any currently-trashed
  /// ancestors (so it's never left with a hidden parent) and any
  /// currently-trashed descendants (its own subtree, trashed alongside
  /// it originally). Throws [StateError] if [id] does not exist.
  Future<void> restoreTicket(String id);

  /// Permanently deletes [id] and its full structural subtree —
  /// cascading to comments and `ticket_links` exactly as the old
  /// `deleteTicket` did. Irreversible. Throws [StateError] if [id] does
  /// not exist.
  Future<void> permanentlyDeleteTicket(String id);

  /// Permanently deletes every currently trashed ticket (and their
  /// comments/`ticket_links`). Irreversible. Used by the trash screen's
  /// "Empty trash" action. No-ops if trash is empty.
  Future<void> emptyTrash();

  /// Permanently deletes every currently trashed ticket whose
  /// `deletedAt` is older than [age] (cascading to comments and
  /// `ticket_links`, same as [emptyTrash]). Returns the number of
  /// tickets purged. No-op (returns 0) if none are eligible.
  ///
  /// Safe to filter per-ticket, with no cascade/subtree walk: trashing
  /// always stamps a whole affected subtree with one `DateTime.now()`
  /// at once (see [trashTickets]), and there is no UI path that
  /// re-trashes a single already-trashed descendant independently — so
  /// every member of a given trashed subtree always shares the same
  /// `deletedAt`. A root and its descendants therefore always age out
  /// together.
  Future<int> purgeTrashOlderThan(Duration age);

  /// Returns every currently trashed ticket, most recently trashed
  /// first.
  Future<List<Ticket>> getTrashedTickets();

  /// Returns tickets matching every non-null filter (ANDed): [status],
  /// [type], [priority] restrict to an exact match on that field; [query]
  /// full-text-matches against title/description. All parameters
  /// omitted/null is equivalent to [getAllTickets]. Ordered by relevance
  /// when [query] is set, otherwise by creation date descending. Excludes
  /// trashed tickets, same as [getAllTickets].
  Future<List<Ticket>> searchTickets({
    String? query,
    TicketStatus? status,
    TicketType? type,
    TicketPriority? priority,
  });
}
