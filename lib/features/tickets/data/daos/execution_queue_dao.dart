// data/daos/execution_queue_dao.dart — ExecutionQueueDao Drift accessor (data layer).

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/execution_queue_table.dart';

part 'execution_queue_dao.g.dart';

/// Drift accessor for [ExecutionQueueTable]. See `AIO-1400` §7.
@DriftAccessor(tables: [ExecutionQueueTable])
class ExecutionQueueDao extends DatabaseAccessor<AppDatabase>
    with _$ExecutionQueueDaoMixin {
  /// Creates an [ExecutionQueueDao] bound to [db].
  ExecutionQueueDao(super.db);

  static const _uuid = Uuid();

  /// Returns every persisted row, ordered by [ExecutionQueueEntryData
  /// .queuePosition] ascending with `null` (in-flight rows) sorted
  /// first — the shape `TicketsCubit.restoreExecutionQueue` needs to
  /// rebuild its in-memory in-flight set and FIFO queue in the same
  /// relative order they were persisted in.
  Future<List<ExecutionQueueEntryData>> getSnapshot() {
    return (select(executionQueueTable)..orderBy([
          (t) => OrderingTerm(
            expression: t.queuePosition,
            mode: OrderingMode.asc,
            nulls: NullsOrder.first,
          ),
        ]))
        .get();
  }

  /// Atomically replaces the entire persisted snapshot: deletes every
  /// existing row, then batch-inserts one fresh row per [entries] member.
  /// Wrapped in a single transaction so a caller never observes a
  /// partially-cleared table. An empty [entries] simply clears the table.
  Future<void> replaceSnapshot(
    List<
      ({String taskId, bool inFlight, int? queuePosition})
    >
    entries,
  ) {
    return transaction<void>(() async {
      await delete(executionQueueTable).go();
      if (entries.isEmpty) return;
      await batch((b) {
        b.insertAll(executionQueueTable, [
          for (final entry in entries)
            ExecutionQueueTableCompanion.insert(
              id: _uuid.v4(),
              taskId: entry.taskId,
              inFlight: entry.inFlight,
              queuePosition: Value(entry.queuePosition),
            ),
        ]);
      });
    });
  }
}
