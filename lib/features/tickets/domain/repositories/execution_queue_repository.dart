// domain/repositories/execution_queue_repository.dart — ExecutionQueueRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/execution_queue_entry.dart';

/// Persists `TicketsCubit`'s coding-execution in-flight/queued state, so
/// it survives an app restart. See
/// `TicketsCubit.restoreExecutionQueue`/`TicketsCubit
/// ._persistExecutionQueueSnapshot` and
/// `AIO-1400` §5.3.
abstract interface class ExecutionQueueRepository {
  /// Returns every persisted [ExecutionQueueEntry], ordered by
  /// [ExecutionQueueEntry.queuePosition] ascending with in-flight entries
  /// first.
  Future<List<ExecutionQueueEntry>> getSnapshot();

  /// Atomically replaces the entire persisted snapshot with [entries].
  /// An empty [entries] clears every persisted row.
  Future<void> replaceSnapshot(List<ExecutionQueueEntry> entries);
}
