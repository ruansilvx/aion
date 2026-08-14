// domain/utils/sibling_cluster.dart — clusterSiblingsAdjacently pure function (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// Returns [tickets] with same-`parentId` siblings regrouped adjacently,
/// each group pulled to the position of its earliest-sorted member — the
/// primary sort [tickets] arrived in is otherwise preserved exactly. A
/// ticket with a `null` `parentId` is never grouped with anything (only
/// same-parent siblings cluster). Stable: within a group, members keep
/// their original relative order; between groups (and lone tickets), the
/// first-occurrence order of each group's earliest member is preserved.
///
/// Used by `TicketsBoardView`'s `BoardColumn` under
/// `ExecutionSchedulingMode.hybrid` so the sibling serialization that mode
/// enforces is visible on the Board, not just inferred from behavior. See
/// `aion-arch/changes/parallel-work/design.md` §9.
List<Ticket> clusterSiblingsAdjacently(List<Ticket> tickets) {
  final result = <Ticket>[];
  final consumed = <int>{};
  for (var i = 0; i < tickets.length; i++) {
    if (consumed.contains(i)) continue;
    final ticket = tickets[i];
    result.add(ticket);
    consumed.add(i);
    final parentId = ticket.parentId;
    if (parentId == null) continue;
    for (var j = i + 1; j < tickets.length; j++) {
      if (consumed.contains(j)) continue;
      if (tickets[j].parentId == parentId) {
        result.add(tickets[j]);
        consumed.add(j);
      }
    }
  }
  return result;
}
