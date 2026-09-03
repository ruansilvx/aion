// core/automation/data/automation_decision_graphs_table.dart — Drift table definition for automation_decision_graphs (data layer).

import 'package:drift/drift.dart';

/// Drift table persisting one row per [AutomationContext]
/// (`../automation_context.dart`) — its currently-configured decision-graph
/// root. Row type is generated as `AutomationDecisionGraphData`. No FK
/// constraints — integrity is enforced at the `DecisionGraphConfigCubit`
/// layer, matching every other table in this schema. See `AIO-181` §2.
@DataClassName('AutomationDecisionGraphData')
class AutomationDecisionGraphsTable extends Table {
  @override
  String get tableName => 'automation_decision_graphs';

  /// `AutomationContext.name` — one graph row per context. Unique by
  /// virtue of being this table's primary key (see [primaryKey] below);
  /// not also marked `.unique()`, since Drift rejects a `UNIQUE`
  /// constraint on a primary-key column as redundant.
  TextColumn get context => text()();

  /// The id of this context's tree's entry-point
  /// `AutomationDecisionNodesTable` row, nullable — `null` means no graph
  /// is configured, so the context always resolves
  /// `DecisionOutcome.proceed`.
  TextColumn get rootNodeId => text().named('root_node_id').nullable()();

  @override
  Set<Column> get primaryKey => {context};
}
