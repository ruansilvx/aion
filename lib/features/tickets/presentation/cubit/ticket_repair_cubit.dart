// presentation/cubit/ticket_repair_cubit.dart — TicketRepairCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/tickets/data/services/ticket_repair_service.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_repair_state.dart';

/// Drives the `TicketNeedsRepairBanner`'s "Reformat" and "Restore last
/// good" actions for one `needsRepair` ticket. Screen-scoped — provided
/// per `TicketDetailScreen` visit, not at the app root, since it's tied
/// to a single [ticketId]/[rootPath] pair.
class TicketRepairCubit extends Cubit<TicketRepairState> {
  /// Creates a [TicketRepairCubit] for the ticket identified by
  /// human-readable [ticketId] under project [rootPath], backed by
  /// [_service].
  TicketRepairCubit(this._service, this.ticketId, this.rootPath)
    : super(const TicketRepairIdle());

  final TicketRepairService _service;

  /// The human-readable ticket id (e.g. `"AIO-42"`) this cubit repairs.
  final String ticketId;

  /// The active project's root directory.
  final String rootPath;

  /// Runs [TicketRepairService.reformat]. Emits [TicketRepairInProgress]
  /// immediately, then [TicketRepairCompleted] on success or
  /// [TicketRepairFailed] if the content couldn't be confidently
  /// reformatted (or an unexpected error occurred).
  Future<void> reformat() async {
    emit(const TicketRepairInProgress());
    try {
      final fixed = await _service.reformat(ticketId, rootPath);
      if (fixed) {
        emit(const TicketRepairCompleted(TicketSyncStatus.synced));
      } else {
        emit(
          const TicketRepairFailed(
            "Couldn't repair automatically — try Restore from last known "
            'good, or edit the file directly.',
          ),
        );
      }
    } catch (e) {
      emit(TicketRepairFailed(e.toString()));
    }
  }

  /// Runs [TicketRepairService.restoreFromLastKnownGood]. Emits
  /// [TicketRepairInProgress] immediately, then [TicketRepairCompleted]
  /// (always [TicketSyncStatus.synced] — this action can't fail to
  /// produce a valid file, since it writes a fresh serialization) or
  /// [TicketRepairFailed] on an unexpected error.
  Future<void> restoreFromLastKnownGood() async {
    emit(const TicketRepairInProgress());
    try {
      await _service.restoreFromLastKnownGood(ticketId, rootPath);
      emit(const TicketRepairCompleted(TicketSyncStatus.synced));
    } catch (e) {
      emit(TicketRepairFailed(e.toString()));
    }
  }
}
