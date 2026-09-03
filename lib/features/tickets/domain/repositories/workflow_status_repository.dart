// domain/repositories/workflow_status_repository.dart — WorkflowStatusRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/workflow_status.dart';

/// Read/write access to [WorkflowStatus] persistence. A dumb persistence
/// layer only — no validation, no invariant enforcement. Every domain
/// invariant (name uniqueness within scope, exactly-one-holder-per-role)
/// lives in `WorkflowConfigCubit`, per this project's Cubit-vs-repository
/// split (validation/invariant logic lives in Cubits, not repositories).
/// Implemented by the data layer ([DriftWorkflowStatusRepository]); UI and
/// domain code depend only on this interface, never on a concrete data
/// source. See `AIO-549`
/// §1.6.
abstract interface class WorkflowStatusRepository {
  /// Returns every persisted [WorkflowStatus] — both the shared-base set
  /// and every per-type extension — ordered by [WorkflowStatus.sortOrder]
  /// ascending. Merging base + a specific [WorkflowStatus.ticketType]'s
  /// extensions into one scoped, sorted view is a pure function over this
  /// result (owned by `WorkflowConfigCubit`/`TicketsCubit`), not a
  /// repository method.
  Future<List<WorkflowStatus>> getAll();

  /// Persists a new [status] row.
  Future<void> create(WorkflowStatus status);

  /// Persists [status]'s current field values over its existing row
  /// (matched by [WorkflowStatus.id]).
  Future<void> update(WorkflowStatus status);

  /// Deletes the status with id [id].
  Future<void> delete(String id);

  /// Persists a new [WorkflowStatus.sortOrder] for every id in
  /// [idsInSortOrder], assigning each its list index. Whole-scope
  /// operation — a caller reorders one scope's rows at a time.
  Future<void> reorder(List<String> idsInSortOrder);

  /// Seeds `defaultWorkflowStatuses` iff the table is currently empty —
  /// called once at app startup for the active project, and by the
  /// schema-15 migration's backfill for every pre-existing project. A
  /// no-op when any row already exists, so it's safe to call
  /// unconditionally.
  Future<void> seedDefaultsIfEmpty();

  /// Fires (with no payload) after every successful [create]/[update]/
  /// [delete]/[reorder] write. This is the "config changed" signal
  /// `TicketsCubit`'s cached `_workflowStatuses` copy and
  /// `WorkflowConfigCubit`'s own state subscribe to, so the two Cubits
  /// stay consistent through the repository layer rather than holding a
  /// direct reference to each other — Aion's Cubits communicate through
  /// shared repositories, never each other directly. See
  /// `AIO-549` §3.
  Stream<void> get onChanged;
}
