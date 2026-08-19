// data/repositories/drift_workflow_status_repository.dart — Drift implementation of WorkflowStatusRepository (data layer).

import 'dart:async';

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';
import 'package:aion/features/tickets/domain/repositories/workflow_status_repository.dart';

/// Drift-backed implementation of [WorkflowStatusRepository]. No business
/// logic here — maps [WorkflowStatusData] rows to [WorkflowStatus]
/// entities and delegates every method straight to [WorkflowStatusDao],
/// matching every other `Drift*Repository` in this codebase.
class DriftWorkflowStatusRepository implements WorkflowStatusRepository {
  /// Creates a [DriftWorkflowStatusRepository] backed by [_db].
  DriftWorkflowStatusRepository(this._db);

  final AppDatabase _db;

  /// Broadcast controller backing [onChanged] — fired after every
  /// successful write below. `sync: true` since listeners (`TicketsCubit`/
  /// `WorkflowConfigCubit`) only ever re-read state asynchronously in
  /// response, never re-enter this repository synchronously.
  final _changeController = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get onChanged => _changeController.stream;

  @override
  Future<List<WorkflowStatus>> getAll() async {
    final rows = await _db.workflowStatusDao.getAll();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> create(WorkflowStatus status) async {
    await _db.workflowStatusDao.insertOne(_toCompanion(status));
    _changeController.add(null);
  }

  @override
  Future<void> update(WorkflowStatus status) async {
    await _db.workflowStatusDao.updateOne(_toCompanion(status));
    _changeController.add(null);
  }

  @override
  Future<void> delete(String id) async {
    await _db.workflowStatusDao.deleteOne(id);
    _changeController.add(null);
  }

  @override
  Future<void> reorder(List<String> idsInSortOrder) async {
    await _db.workflowStatusDao.reorder(idsInSortOrder);
    _changeController.add(null);
  }

  @override
  Future<void> seedDefaultsIfEmpty() {
    return _db.workflowStatusDao.seedDefaultsIfEmpty();
  }

  /// Maps a domain [WorkflowStatus] to its persisted-row companion.
  WorkflowStatusesTableCompanion _toCompanion(WorkflowStatus status) {
    return WorkflowStatusesTableCompanion(
      id: Value(status.id),
      name: Value(status.name),
      displayName: Value(status.displayName),
      ticketType: Value(status.ticketType?.name),
      sortOrder: Value(status.sortOrder),
      role: Value(status.role?.name),
    );
  }

  /// Maps a generated [WorkflowStatusData] row to the [WorkflowStatus]
  /// domain entity.
  WorkflowStatus _toEntity(WorkflowStatusData row) {
    return WorkflowStatus(
      id: row.id,
      name: row.name,
      displayName: row.displayName,
      ticketType: _parseNullableEnum(TicketType.values, row.ticketType),
      sortOrder: row.sortOrder,
      role: _parseNullableEnum(WorkflowStatusRole.values, row.role),
    );
  }

  /// Parses [name] against [values] by `.name`, returning `null` if [name]
  /// is `null` or doesn't match any value.
  T? _parseNullableEnum<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
