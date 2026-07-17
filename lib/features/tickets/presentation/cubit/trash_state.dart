// presentation/cubit/trash_state.dart — TrashState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// The state emitted by [TrashCubit].
sealed class TrashState extends Equatable {
  const TrashState();

  @override
  List<Object?> get props => [];
}

/// A trash fetch is in flight. UI should show [AppSpinner].
class TrashLoading extends TrashState {
  /// Creates a [TrashLoading] state.
  const TrashLoading();
}

/// The trashed-ticket list loaded successfully. Carries only "root"
/// trashed tickets — ones whose `parentId` is `null` or points at a
/// ticket that isn't also trashed. A ticket trashed as part of a parent's
/// cascade (its `parentId` points at another trashed ticket) is a
/// descendant, not a root, and is folded into its root's
/// [descendantCounts] entry instead of getting its own tile — restoring
/// or permanently deleting a root always takes its whole subtree with
/// it, so the subtree never needs independent tiles.
class TrashLoaded extends TrashState {
  /// Creates a [TrashLoaded] state carrying [tickets] (roots only),
  /// [descendantCounts], and [purgeEligibleCount].
  const TrashLoaded(
    this.tickets,
    this.descendantCounts,
    this.purgeEligibleCount,
  );

  /// Every currently trashed root ticket, most recently trashed first.
  final List<Ticket> tickets;

  /// Maps a root ticket's id to how many other trashed tickets are in its
  /// structural subtree. Absent (or `0`) for a root with no trashed
  /// descendants.
  final Map<String, int> descendantCounts;

  /// How many currently trashed tickets (roots and descendants combined)
  /// are older than [TrashCubit.purgeAgeThreshold] — i.e. how many
  /// "Purge old" would remove right now. Drives the purge action's
  /// enabled state and its confirm-dialog count.
  final int purgeEligibleCount;

  @override
  List<Object?> get props => [tickets, descendantCounts, purgeEligibleCount];
}

/// A trash load, restore, permanent-delete, or empty-trash operation
/// failed. Carries a raw, unlocalized description of what went wrong.
class TrashError extends TrashState {
  /// Creates a [TrashError] state carrying [message].
  const TrashError(this.message);

  /// A raw, unlocalized description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
