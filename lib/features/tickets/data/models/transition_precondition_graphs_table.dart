// data/models/transition_precondition_graphs_table.dart — Drift table definition for transition_precondition_graphs (data layer).

import 'package:drift/drift.dart';

/// The `ticket_type` sentinel meaning "applies to every ticket type
/// reaching this stage" — every row before `AIO-2903` implicitly meant
/// this, and every existing row is backfilled to it by that migration.
/// Not a real `TicketType.name` value, so it can never collide with one.
/// Kept as a plain constant (not a domain-layer concept) since only this
/// table and its DAO/repository ever need to know the wildcard has a
/// string representation at all — everywhere else in the app, "applies to
/// every type" is simply a `null` `TicketType?`. See
/// `DriftTransitionPreconditionRepository`'s own dartdoc for the
/// null-in/sentinel-out mapping. Added for `AIO-2903`.
const anyTicketTypeSentinel = 'any';

/// Drift table persisting one row per `(SddStage, TicketType?)`
/// (`../../domain/enums/sdd_stage.dart`, `../../domain/enums/ticket_type.dart`)
/// — its currently-configured transition-precondition graph root. Row type
/// is generated as [TransitionPreconditionGraphData]. No FK constraints —
/// integrity is enforced at the `TransitionPreconditionConfigCubit` layer,
/// matching every other table in this schema (mirrors
/// `core/automation/data/automation_decision_graphs_table.dart`'s exact
/// shape). See `AIO-1936` §2.
///
/// Originally keyed by [sddStage] alone (one graph shared by every ticket
/// type reaching that stage). `AIO-2903` widened the key to
/// `(sddStage, ticketType)` so a type can configure its own override graph
/// — [ticketType] is [anyTicketTypeSentinel] for "shared, every type" (the
/// backfilled meaning of every pre-`AIO-2903` row) or a real `TicketType.name`
/// for a type-specific override. A `NOT NULL` sentinel column, not a
/// nullable one, deliberately: SQLite doesn't enforce `NOT NULL` on a
/// non-rowid primary-key column, and `NULL`s are mutually distinct under
/// `UNIQUE`/`PRIMARY KEY`, so a nullable "wildcard" column can't be relied
/// on to stay singular per stage without extra application-level policing
/// — the sentinel lets the schema's own constraint do that work.
@DataClassName('TransitionPreconditionGraphData')
class TransitionPreconditionGraphsTable extends Table {
  @override
  String get tableName => 'transition_precondition_graphs';

  /// `SddStage.name` — see [primaryKey].
  TextColumn get sddStage => text()();

  /// A `TicketType.name`, or [anyTicketTypeSentinel] for the shared/
  /// type-agnostic graph. Part of [primaryKey] alongside [sddStage] —
  /// unique by virtue of that, not also marked `.unique()`, since Drift
  /// rejects a `UNIQUE` constraint on a primary-key column as redundant.
  /// Added for `AIO-2903`.
  TextColumn get ticketType => text()
      .named('ticket_type')
      .withDefault(const Constant(anyTicketTypeSentinel))();

  /// The id of this `(sddStage, ticketType)` tree's entry-point
  /// `TransitionPreconditionNodesTable` row, nullable — `null` means no
  /// graph is configured, so this combination always advances freely.
  TextColumn get rootNodeId => text().named('root_node_id').nullable()();

  @override
  Set<Column> get primaryKey => {sddStage, ticketType};
}
