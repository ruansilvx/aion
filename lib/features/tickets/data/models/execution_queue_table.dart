// data/models/execution_queue_table.dart — Drift table definition for execution_queue (data layer).

import 'package:drift/drift.dart';

/// Drift table persisting `TicketsCubit`'s in-flight/queued coding-execution
/// runs, so they survive an app restart — see
/// `TicketsCubit.restoreExecutionQueue` and `AIO-1400` §5.3/§7. Row type is
/// generated as `ExecutionQueueEntryData`. No FK constraints — integrity is
/// enforced at the repository layer, matching every other table in this
/// schema.
@DataClassName('ExecutionQueueEntryData')
class ExecutionQueueTable extends Table {
  @override
  String get tableName => 'execution_queue';

  /// Internal UUID v4 primary key.
  TextColumn get id => text()();

  /// The Task/Bug ticket id this row tracks.
  TextColumn get taskId => text().named('task_id')();

  /// Whether this row was in flight (actively running) at the moment it
  /// was persisted, as opposed to merely queued.
  BoolColumn get inFlight => boolean().named('in_flight')();

  /// This row's 1-based FIFO position among still-queued (non-
  /// [inFlight]) rows — the front of the queue is `1`, not `0`. `null`
  /// when [inFlight] is `true`.
  IntColumn get queuePosition => integer().named('queue_position').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
