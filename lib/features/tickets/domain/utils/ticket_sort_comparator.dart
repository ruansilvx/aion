// domain/utils/ticket_sort_comparator.dart — Shared sort-ordinal lookup + in-memory Comparator<Ticket> builder (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Maps each [TicketSortField] to the `List<Enum>` whose *declaration
/// order* defines that field's ordinal ordering —
/// [TicketPriority.values]/[TicketStatus.values]/[TicketType.values] for
/// [TicketSortField.priority]/[TicketSortField.status]/
/// [TicketSortField.type] respectively. `null` for
/// [TicketSortField.createdAt]/[TicketSortField.updatedAt] (which sort by
/// their own timestamp column directly, not an enum ordinal) and
/// [TicketSortField.relevance] (which sorts by bm25 score, handled
/// separately by the caller).
///
/// A single shared lookup, indexed into by both [ticketSortComparator]
/// below (the in-memory Dart path, used by `TrashCubit`) and
/// `TicketDao`'s `_enumOrdinalCaseSql` (the SQL path, used by
/// `TicketRepository.searchTickets`) — keeping the ordinal mapping in one
/// place means the two orderings can't silently drift apart. See
/// `aion-arch/changes/ticket-sort-control-and-board-as-default-view/design.md`
/// §4.3.
final Map<TicketSortField, List<Enum>?> ticketFieldEnumValues = {
  TicketSortField.relevance: null,
  TicketSortField.priority: TicketPriority.values,
  TicketSortField.status: TicketStatus.values,
  TicketSortField.type: TicketType.values,
  TicketSortField.createdAt: null,
  TicketSortField.updatedAt: null,
};

/// Builds a `Comparator<Ticket>` that orders per [sort]. Used only by
/// `TrashCubit`, which sorts an already-fetched, already-in-memory ticket
/// list (design.md §4.2) — the query-layer path (`TicketDao.searchTickets`)
/// handles List/Board's own ordering at the DB level instead, where the
/// data already lives.
///
/// [TicketSortField.relevance] has no search query to score against in a
/// pure in-memory comparator, so it falls back to `createdAt` descending —
/// the same fallback `TicketsCubit._implicitSort`/`TrashCubit._resolveSort`
/// apply whenever relevance isn't actually meaningful.
Comparator<Ticket> ticketSortComparator(TicketListSort sort) {
  final effective = sort.field == TicketSortField.relevance
      ? const TicketListSort(
          field: TicketSortField.createdAt,
          direction: TicketSortDirection.descending,
        )
      : sort;
  final ascending = effective.direction == TicketSortDirection.ascending;

  return (a, b) {
    final values = ticketFieldEnumValues[effective.field];
    final result = switch (effective.field) {
      TicketSortField.priority ||
      TicketSortField.status ||
      TicketSortField.type => _ordinalOf(
        effective.field,
        a,
        values!,
      ).compareTo(_ordinalOf(effective.field, b, values)),
      TicketSortField.createdAt => a.createdAt.compareTo(b.createdAt),
      TicketSortField.updatedAt => a.updatedAt.compareTo(b.updatedAt),
      TicketSortField.relevance => throw StateError(
        'relevance is resolved to createdAt above',
      ),
    };
    return ascending ? result : -result;
  };
}

/// [ticket]'s ordinal position within [values] for [field] — the index of
/// its [Ticket.priority]/[Ticket.status]/[Ticket.type] value within that
/// enum's own `.values` list.
int _ordinalOf(TicketSortField field, Ticket ticket, List<Enum> values) {
  final value = switch (field) {
    TicketSortField.priority => ticket.priority,
    TicketSortField.status => ticket.status,
    TicketSortField.type => ticket.type,
    _ => throw StateError('unreachable'),
  };
  return values.indexOf(value);
}
