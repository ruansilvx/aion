// domain/utils/ticket_rollup_calculator.dart — Pure Jira-style estimate/timeSpent rollup calculator (domain layer).

/// One node's minimal shape for rollup computation — deliberately narrower
/// than `Ticket` so this can run directly against raw drift rows during the
/// schema-9 migration backfill (see `AppDatabase._backfillRollups`),
/// without constructing a full `Ticket` for every row.
typedef RollupNode = ({String id, String? parentId, int? estimate, int? timeSpent});

/// One node's computed rollup. [estimateRollup]/[timeSpentRollup] are
/// `null` when that metric has no live contribution anywhere in the
/// subtree — this node's own value and every descendant's effective value
/// are all `null` — never `0`, so an all-unestimated subtree renders as
/// "no estimate" rather than a misleading zero.
///
/// [estimateCount]/[timeSpentCount] are query-only — the count of live
/// tickets (this node plus every descendant) contributing a non-null
/// value for that metric. Never written to drift (only [estimateRollup]/
/// [timeSpentRollup] are persisted); they exist purely to back
/// `TicketsCubit.getRollupCounts`'s on-demand detail-screen count caption.
typedef RollupResult = ({
  int? estimateRollup,
  int? timeSpentRollup,
  int estimateCount,
  int timeSpentCount,
});

/// A single node's effective contribution to its parent's rollup —
/// internal accumulator shape, not part of the public API. For a leaf
/// this is just its own raw value; for an internal node this *is* its
/// just-computed rollup (see [computeRollups]'s doc for why that recursive
/// equivalence is what makes the walk correct).
typedef _EffectiveContribution = ({
  int? estimate,
  int estimateCount,
  int? timeSpent,
  int timeSpentCount,
});

/// Computes a [RollupResult] for every node in [nodes] that has at least
/// one other node in [nodes] pointing at it via `parentId` (i.e. every
/// internal node) — a childless node (leaf) is omitted from the returned
/// map entirely, since a leaf's display falls back to its own raw
/// `estimate`/`timeSpent` with nothing to roll up.
///
/// Pure, deterministic, `O(n)`: builds a `parentId -> children` adjacency
/// map once (same shape as `TicketsCubit._descendantIds`'s existing
/// helper), then computes bottom-up via memoized post-order recursion.
/// Jira-style sum: an internal node's rollup is its own value (contributing
/// `0` to the sum when absent, but not counted as "set") plus, for each
/// direct child, that child's *effective* value — where a childless child
/// contributes its own raw value and a child with children contributes its
/// own just-computed rollup.
///
/// Guards against a malformed cycle (should never occur — cycles are
/// already rejected at write time by `TicketsCubit`/
/// `TicketRepository.trashTicket`'s cascade logic — but a defensive
/// `visiting` set prevents a corrupt migration from hanging) by treating a
/// re-visited in-progress node as contributing nothing (`0`/no count)
/// rather than recursing infinitely.
Map<String, RollupResult> computeRollups(List<RollupNode> nodes) {
  final byId = {for (final n in nodes) n.id: n};
  final childrenByParent = <String, List<RollupNode>>{};
  for (final n in nodes) {
    final parentId = n.parentId;
    if (parentId != null && byId.containsKey(parentId)) {
      childrenByParent.putIfAbsent(parentId, () => []).add(n);
    }
  }

  final memo = <String, _EffectiveContribution>{};
  final visiting = <String>{};

  _EffectiveContribution effective(String id) {
    final cached = memo[id];
    if (cached != null) return cached;
    if (!visiting.add(id)) {
      // Cycle guard: a re-visited in-progress node contributes nothing.
      return (estimate: null, estimateCount: 0, timeSpent: null, timeSpentCount: 0);
    }

    final node = byId[id];
    final children = childrenByParent[id] ?? const [];

    int? estimateSum = node?.estimate;
    var estimateCount = node?.estimate != null ? 1 : 0;
    int? timeSpentSum = node?.timeSpent;
    var timeSpentCount = node?.timeSpent != null ? 1 : 0;

    for (final child in children) {
      final childResult = effective(child.id);
      final childEstimate = childResult.estimate;
      if (childEstimate != null) {
        estimateSum = (estimateSum ?? 0) + childEstimate;
      }
      estimateCount += childResult.estimateCount;
      final childTimeSpent = childResult.timeSpent;
      if (childTimeSpent != null) {
        timeSpentSum = (timeSpentSum ?? 0) + childTimeSpent;
      }
      timeSpentCount += childResult.timeSpentCount;
    }

    final result = (
      estimate: estimateCount == 0 ? null : (estimateSum ?? 0),
      estimateCount: estimateCount,
      timeSpent: timeSpentCount == 0 ? null : (timeSpentSum ?? 0),
      timeSpentCount: timeSpentCount,
    );
    visiting.remove(id);
    memo[id] = result;
    return result;
  }

  final result = <String, RollupResult>{};
  for (final n in nodes) {
    if (!childrenByParent.containsKey(n.id)) continue; // leaf — omitted
    final eff = effective(n.id);
    result[n.id] = (
      estimateRollup: eff.estimate,
      timeSpentRollup: eff.timeSpent,
      estimateCount: eff.estimateCount,
      timeSpentCount: eff.timeSpentCount,
    );
  }
  return result;
}
