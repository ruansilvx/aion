// data/models/workflow_status_table.dart — Drift table definition for workflow_statuses (data layer).

import 'package:drift/drift.dart';

/// Drift table persisting a project's configured [WorkflowStatus]
/// (../domain/entities/workflow_status.dart) set — the data-driven replacement
/// for the fixed `TicketStatus` enum. Row type is generated as
/// `WorkflowStatusData`. No FK constraints — integrity is enforced at the
/// `WorkflowConfigCubit` layer, matching every other table in this schema. See
/// `AIO-549` §2.1.
@DataClassName('WorkflowStatusData')
class WorkflowStatusesTable extends Table {
  @override
  String get tableName => 'workflow_statuses';

  /// Internal UUID v4 primary key.
  TextColumn get id => text()();

  /// The status name written to `Ticket.status`.
  TextColumn get name => text()();

  /// The user-facing label.
  TextColumn get displayName => text().named('display_name')();

  /// `TicketType.name`, nullable — `null` means a shared-base status;
  /// non-`null` scopes this status as a per-type extension.
  TextColumn get ticketType => text().named('ticket_type').nullable()();

  /// This status's position within its scope's ordering.
  IntColumn get sortOrder => integer().named('sort_order')();

  /// `WorkflowStatusRole.name`, nullable. Always `null` when [ticketType]
  /// is non-`null` — enforced by `WorkflowConfigCubit`, not this table.
  TextColumn get role => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
