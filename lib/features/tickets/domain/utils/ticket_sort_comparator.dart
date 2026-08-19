// domain/utils/ticket_sort_comparator.dart — Shared sort-ordinal lookup + in-memory Comparator<Ticket> builder (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Maps each [TicketSortField] to the `List<Enum>` whose *declaration
/// order* defines that field's ordinal ordering —
/// [TicketPriority.values]/[TicketType.values] for
/// [TicketSortField.priority]/[TicketSortField.type] respectively. `null`
/// for [TicketSortField.createdAt]/[TicketSortField.updatedAt] (which sort
/// by their own timestamp column directly, not an enum ordinal) and
/// [TicketSortField.relevance] (handled separately by the caller).
///
/// [TicketSortField.status] is deliberately absent from this map — since
/// `aion-arch/changes/configurable-ticket-workflow`, a ticket's status is
/// a project-configured [WorkflowStatus](../entities/workflow_status.dart)
/// name, not a fixed enum, so its ordinal comes from the project's live
/// `WorkflowStatus.sortOrder` list (a `statusOrder` parameter both
/// [ticketSortComparator] and `TicketDao`'s SQL builder now take), not
/// this compile-time lookup.
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
/// [statusOrder] is the caller's currently-configured `WorkflowStatus` name
/// list, already sorted by `WorkflowStatus.sortOrder` — required only when
/// [sort.field] is [TicketSortField.status]; a ticket whose status isn't
/// found in [statusOrder] (e.g. a status the project has since deleted)
/// sorts after every recognized status, mirroring the SQL path's `ELSE`
/// clause.
///
/// [TicketSortField.relevance] has no search query to score against in a
/// pure in-memory comparator, so it falls back to `createdAt` descending —
/// the same fallback `TicketsCubit._implicitSort`/`TrashCubit._resolveSort`
/// apply whenever relevance isn't actually meaningful.
Comparator<Ticket> ticketSortComparator(
  TicketListSort sort, {
  List<String> statusOrder = const [],
}) {
  final effective = sort.field == TicketSortField.relevance
      ? const TicketListSort(
          field: TicketSortField.createdAt,
          direction: TicketSortDirection.descending,
        )
      : sort;
  final ascending = effective.direction == TicketSortDirection.ascending;

  return (a, b) {
    final result = switch (effective.field) {
      TicketSortField.status => _statusOrdinalOf(
        a,
        statusOrder,
      ).compareTo(_statusOrdinalOf(b, statusOrder)),
      TicketSortField.priority ||
      TicketSortField.type => _ordinalOf(
        effective.field,
        a,
        ticketFieldEnumValues[effective.field]!,
      ).compareTo(
        _ordinalOf(effective.field, b, ticketFieldEnumValues[effective.field]!),
      ),
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
/// its [Ticket.priority]/[Ticket.type] value within that enum's own
/// `.values` list.
int _ordinalOf(TicketSortField field, Ticket ticket, List<Enum> values) {
  final value = switch (field) {
    TicketSortField.priority => ticket.priority,
    TicketSortField.type => ticket.type,
    _ => throw StateError('unreachable'),
  };
  return values.indexOf(value);
}

/// [ticket.status]'s ordinal position within [statusOrder] — `statusOrder
/// .length` (sorts last) if not found, mirroring the SQL path's `ELSE`
/// clause.
int _statusOrdinalOf(Ticket ticket, List<String> statusOrder) {
  final index = statusOrder.indexOf(ticket.status);
  return index == -1 ? statusOrder.length : index;
}
