// presentation/cubit/ticket_repair_state.dart — TicketRepairState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';

/// The state emitted by [TicketRepairCubit].
sealed class TicketRepairState extends Equatable {
  const TicketRepairState();

  @override
  List<Object?> get props => [];
}

/// No repair action in flight. Initial state.
class TicketRepairIdle extends TicketRepairState {
  /// Creates a [TicketRepairIdle] state.
  const TicketRepairIdle();
}

/// A reformat or restore action is running. `TicketNeedsRepairBanner`
/// shows the acting button's in-progress look and disables the other one.
class TicketRepairInProgress extends TicketRepairState {
  /// Creates a [TicketRepairInProgress] state.
  const TicketRepairInProgress();
}

/// The action completed successfully. Carries the resulting
/// [TicketSyncStatus] so the UI can confirm the banner should disappear
/// (design.md §3.4's success-confirmation, auto-collapse sequence).
class TicketRepairCompleted extends TicketRepairState {
  /// Creates a [TicketRepairCompleted] state carrying [resultStatus].
  const TicketRepairCompleted(this.resultStatus);

  /// The ticket's [TicketSyncStatus] after the action — always
  /// [TicketSyncStatus.synced] in practice.
  final TicketSyncStatus resultStatus;

  @override
  List<Object?> get props => [resultStatus];
}

/// The action could not fix the file (e.g. `reformat` returned `false`,
/// or an unexpected I/O error). Carries a message for the failure toast
/// described in design.md §3.4.
class TicketRepairFailed extends TicketRepairState {
  /// Creates a [TicketRepairFailed] state carrying [message].
  const TicketRepairFailed(this.message);

  /// Human-readable failure explanation.
  final String message;

  @override
  List<Object?> get props => [message];
}
