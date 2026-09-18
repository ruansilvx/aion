// presentation/cubit/tickets_repo_sync_status.dart — TicketsRepoSyncStatus sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

/// The value held by `TicketsCubit.ticketsRepoSyncStatus` as its periodic
/// tickets-repo push check runs. Deliberately kept separate from
/// `TicketsState` — same rationale as `CodebaseAnalysisStatus`: a
/// transient, app-wide concern unrelated to the ticket list's own
/// filter/sort/pagination state. `WorkspaceNavShell`'s `_SyncStatusIndicator`
/// reads this directly. Added for `AIO-2945`.
sealed class TicketsRepoSyncStatus extends Equatable {
  const TicketsRepoSyncStatus();

  @override
  List<Object?> get props => [];
}

/// The tickets-repo is fully pushed — no local commits ahead of origin,
/// or no push is configured/possible at all. The initial and steady-state
/// value.
class TicketsRepoSyncIdle extends TicketsRepoSyncStatus {
  /// Creates a [TicketsRepoSyncIdle] state.
  const TicketsRepoSyncIdle();
}

/// The tickets-repo has [count] local commits not yet pushed to origin,
/// detected by the periodic check but not yet acted on.
class TicketsRepoSyncAhead extends TicketsRepoSyncStatus {
  /// Creates a [TicketsRepoSyncAhead] state carrying [count].
  const TicketsRepoSyncAhead(this.count);

  /// How many local commits are ahead of the upstream.
  final int count;

  @override
  List<Object?> get props => [count];
}

/// A background push of the tickets-repo is currently in flight.
class TicketsRepoSyncPushing extends TicketsRepoSyncStatus {
  /// Creates a [TicketsRepoSyncPushing] state.
  const TicketsRepoSyncPushing();
}

/// The most recent background push attempt failed with [message]. Cleared
/// back to [TicketsRepoSyncIdle]/[TicketsRepoSyncAhead] on the next
/// periodic tick's own outcome — no separate manual-retry action.
class TicketsRepoSyncFailed extends TicketsRepoSyncStatus {
  /// Creates a [TicketsRepoSyncFailed] state carrying [message].
  const TicketsRepoSyncFailed(this.message);

  /// A human-readable description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
