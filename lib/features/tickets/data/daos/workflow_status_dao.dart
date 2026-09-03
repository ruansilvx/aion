// data/daos/workflow_status_dao.dart — WorkflowStatusDao Drift accessor (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/data/models/workflow_status_table.dart';
import 'package:aion/features/tickets/domain/entities/default_workflow_statuses.dart';

part 'workflow_status_dao.g.dart';

/// Drift accessor for [WorkflowStatusesTable]. See `AIO-549` §2.3.
@DriftAccessor(tables: [WorkflowStatusesTable])
class WorkflowStatusDao extends DatabaseAccessor<AppDatabase>
    with _$WorkflowStatusDaoMixin {
  /// Creates a [WorkflowStatusDao] bound to [db].
  WorkflowStatusDao(super.db);

  /// Returns every persisted row, ordered by [WorkflowStatusData
  /// .sortOrder] ascending.
  Future<List<WorkflowStatusData>> getAll() {
    return (select(workflowStatusesTable)..orderBy([
          (t) => OrderingTerm(
            expression: t.sortOrder,
            mode: OrderingMode.asc,
          ),
        ]))
        .get();
  }

  /// Inserts a single new row.
  Future<void> insertOne(WorkflowStatusesTableCompanion companion) {
    return into(workflowStatusesTable).insert(companion);
  }

  /// Updates a single existing row (matched by its primary key).
  Future<void> updateOne(WorkflowStatusesTableCompanion companion) {
    return update(workflowStatusesTable).replace(companion);
  }

  /// Deletes the row with id [id].
  Future<void> deleteOne(String id) {
    return (delete(
      workflowStatusesTable,
    )..where((t) => t.id.equals(id))).go();
  }

  /// Atomically writes a fresh [WorkflowStatusData.sortOrder] (each id's
  /// list index) for every id in [idsInSortOrder]. Wrapped in a single
  /// transaction, mirroring [ExecutionQueueDao.replaceSnapshot]'s
  /// transaction pattern, so a caller never observes a partially-reordered
  /// scope.
  Future<void> reorder(List<String> idsInSortOrder) {
    return transaction<void>(() async {
      for (var i = 0; i < idsInSortOrder.length; i++) {
        await (update(
          workflowStatusesTable,
        )..where((t) => t.id.equals(idsInSortOrder[i]))).write(
          WorkflowStatusesTableCompanion(sortOrder: Value(i)),
        );
      }
    });
  }

  /// Seeds [defaultWorkflowStatuses] iff the table is currently empty —
  /// checked first so this is safe (idempotent, no duplication) to call
  /// unconditionally from both `onCreate` and every `onUpgrade` branch.
  Future<void> seedDefaultsIfEmpty() async {
    final existing = await select(workflowStatusesTable).get();
    if (existing.isNotEmpty) return;

    await batch((b) {
      b.insertAll(workflowStatusesTable, [
        for (final status in defaultWorkflowStatuses)
          WorkflowStatusesTableCompanion.insert(
            id: status.id,
            name: status.name,
            displayName: status.displayName,
            ticketType: const Value(null),
            sortOrder: status.sortOrder,
            role: Value(status.role?.name),
          ),
      ]);
    });
  }
}
