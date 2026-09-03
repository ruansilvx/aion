// data/models/transition_precondition_graphs_table.dart — Drift table definition for transition_precondition_graphs (data layer).

import 'package:drift/drift.dart';

/// Drift table persisting one row per `SddStage`
/// (`../../domain/enums/sdd_stage.dart`) — its currently-configured
/// transition-precondition graph root. Row type is generated as
/// [TransitionPreconditionGraphData]. No FK constraints — integrity is
/// enforced at the `TransitionPreconditionConfigCubit` layer, matching
/// every other table in this schema (mirrors
/// `core/automation/data/automation_decision_graphs_table.dart`'s exact
/// shape). See
/// `AIO-1936` §2.
@DataClassName('TransitionPreconditionGraphData')
class TransitionPreconditionGraphsTable extends Table {
  @override
  String get tableName => 'transition_precondition_graphs';

  /// `SddStage.name` — one graph row per stage. Unique by virtue of being
  /// this table's primary key (see [primaryKey] below); not also marked
  /// `.unique()`, since Drift rejects a `UNIQUE` constraint on a
  /// primary-key column as redundant.
  TextColumn get sddStage => text()();

  /// The id of this stage's tree's entry-point
  /// `TransitionPreconditionNodesTable` row, nullable — `null` means no
  /// graph is configured, so the stage always advances freely.
  TextColumn get rootNodeId => text().named('root_node_id').nullable()();

  @override
  Set<Column> get primaryKey => {sddStage};
}
