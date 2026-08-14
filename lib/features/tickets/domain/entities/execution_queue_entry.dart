// domain/entities/execution_queue_entry.dart — ExecutionQueueEntry entity (domain layer).

import 'package:equatable/equatable.dart';

/// One persisted row of `TicketsCubit`'s coding-execution queue —
/// either an in-flight run or a still-queued one — surviving an app
/// restart via `ExecutionQueueRepository`. See
/// `aion-arch/changes/parallel-work/design.md` §5.3.
class ExecutionQueueEntry extends Equatable {
  /// Creates an [ExecutionQueueEntry] for [taskId].
  const ExecutionQueueEntry({
    required this.taskId,
    required this.inFlight,
    this.queuePosition,
  });

  /// The Task/Bug ticket id this entry tracks.
  final String taskId;

  /// Whether this entry was in flight (actively running) at the moment
  /// it was persisted, as opposed to merely queued.
  final bool inFlight;

  /// This entry's FIFO position among still-queued (non-[inFlight])
  /// entries, lowest running next. `null` when [inFlight] is `true` —
  /// an in-flight run has no queue position.
  final int? queuePosition;

  @override
  List<Object?> get props => [taskId, inFlight, queuePosition];
}
