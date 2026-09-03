// presentation/cubit/ticket_rollup_counts.dart — TicketRollupCounts read model (presentation layer).

import 'package:meta/meta.dart';

/// Detail-screen-only read model — constructed on demand by
/// `TicketsCubit.getRollupCounts` for the one ticket `TicketDetailScreen` is
/// showing. Never persisted, and never constructed for a
/// `TicketListTile`/`TicketBoardCard` row — those read
/// `Ticket.estimateRollup`/`.timeSpentRollup` directly instead, with no count.
/// See `AIO-873` §0.3.
@immutable
class TicketRollupCounts {
  /// Number of live tickets (self + descendants) contributing a non-null
  /// `estimate` value.
  final int estimateCount;

  /// Number of live tickets (self + descendants) contributing a non-null
  /// `timeSpent` value.
  final int timeSpentCount;

  /// Creates a [TicketRollupCounts]. Both counts are required.
  const TicketRollupCounts({
    required this.estimateCount,
    required this.timeSpentCount,
  });
}
