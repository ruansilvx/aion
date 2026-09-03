// domain/utils/sibling_cluster.dart — clusterSiblingsAdjacently pure function (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// Returns [tickets] with same-cluster siblings regrouped adjacently, each
/// group pulled to the position of its earliest-sorted member — the
/// primary sort [tickets] arrived in is otherwise preserved exactly. A
/// ticket absent from [topmostAncestorId] (or mapped to its own id) is
/// never grouped with anything (only tickets sharing a topmost ancestor
/// cluster). Stable: within a group, members keep their original relative
/// order; between groups (and lone tickets), the first-occurrence order of
/// each group's earliest member is preserved.
///
/// [topmostAncestorId] maps each ticket's id to its cluster key (its
/// topmost ancestor id, or its own id if it has no parent) — see
/// `TicketsCubit.topmostAncestorIds`. Was: grouped by direct
/// `ticket.parentId` equality; now groups by shared topmost ancestor, so
/// two Tasks under different Stories of the same Epic cluster together,
/// matching Hybrid mode's own generalized conflict signal
/// (`TicketsCubit._nextEligibleForHybrid`) — the Board's visual grouping
/// and the scheduler's actual serialization now agree on the same
/// definition of "sibling." Still pure/synchronous: this function does no
/// I/O itself, the map is precomputed by an async caller.
///
/// Used by `TicketsBoardView`'s `BoardColumn` under
/// `ExecutionSchedulingMode.hybrid` so the sibling serialization that mode
/// enforces is visible on the Board, not just inferred from behavior. See
/// `AIO-1400` §9 (original, `parentId`- only version) and `AIO-722` §2.4 (this
/// ancestor-generalized version).
List<Ticket> clusterSiblingsAdjacently(
  List<Ticket> tickets,
  Map<String, String> topmostAncestorId,
) {
  final result = <Ticket>[];
  final consumed = <int>{};
  for (var i = 0; i < tickets.length; i++) {
    if (consumed.contains(i)) continue;
    final ticket = tickets[i];
    result.add(ticket);
    consumed.add(i);
    final key = topmostAncestorId[ticket.id];
    if (key == null || key == ticket.id) continue; // no parent — no cluster.
    for (var j = i + 1; j < tickets.length; j++) {
      if (consumed.contains(j)) continue;
      if (topmostAncestorId[tickets[j].id] == key) {
        result.add(tickets[j]);
        consumed.add(j);
      }
    }
  }
  return result;
}
