// data/repositories/drift_execution_queue_repository.dart — Drift implementation of ExecutionQueueRepository (data layer).

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/domain/entities/execution_queue_entry.dart';
import 'package:aion/features/tickets/domain/repositories/execution_queue_repository.dart';

/// Drift-backed implementation of [ExecutionQueueRepository]. No business
/// logic here — maps [ExecutionQueueEntryData] rows to
/// [ExecutionQueueEntry] entities and delegates every method straight to
/// [ExecutionQueueDao], matching every other `Drift*Repository` in this
/// codebase.
class DriftExecutionQueueRepository implements ExecutionQueueRepository {
  /// Creates a [DriftExecutionQueueRepository] backed by [_db].
  DriftExecutionQueueRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<ExecutionQueueEntry>> getSnapshot() async {
    final rows = await _db.executionQueueDao.getSnapshot();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> replaceSnapshot(List<ExecutionQueueEntry> entries) {
    return _db.executionQueueDao.replaceSnapshot([
      for (final entry in entries)
        (
          taskId: entry.taskId,
          inFlight: entry.inFlight,
          queuePosition: entry.queuePosition,
        ),
    ]);
  }

  /// Maps a raw [ExecutionQueueEntryData] row to its domain
  /// [ExecutionQueueEntry] entity.
  ExecutionQueueEntry _toEntity(ExecutionQueueEntryData row) =>
      ExecutionQueueEntry(
        taskId: row.taskId,
        inFlight: row.inFlight,
        queuePosition: row.queuePosition,
      );
}
