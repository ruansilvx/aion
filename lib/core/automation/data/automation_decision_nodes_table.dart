// core/automation/data/automation_decision_nodes_table.dart — Drift table definition for automation_decision_nodes (data layer).

import 'package:drift/drift.dart';

/// Drift table persisting one row per `DecisionNode`
/// (`../decision_node.dart`) — a strict-tree condition node belonging to
/// one `AutomationContext`'s decision graph. Row type is generated as
/// `AutomationDecisionNodeData`. `matchedBranchKind`/`unmatchedBranchKind`
/// hold `'node'`/`'proceed'`/`'gated'`/`'decline'`/`'modelJudgment'` —
/// `'node'` means the corresponding `*BranchNodeId` column holds the
/// child node's id; every other value is a terminal `DecisionOutcome`
/// name and leaves that column `null`. No FK constraints on the node-id
/// columns (nor on which `AutomationDecisionGraphsTable` row a node
/// belongs to — that's implicit via graph traversal from the root, not a
/// stored parent pointer) — integrity is enforced at the
/// `DecisionGraphConfigCubit` layer, matching every other table in this
/// schema. See `AIO-181`
/// §2.
@DataClassName('AutomationDecisionNodeData')
class AutomationDecisionNodesTable extends Table {
  @override
  String get tableName => 'automation_decision_nodes';

  /// Internal UUID v4 primary key.
  TextColumn get id => text()();

  /// References a `DecisionConditionSpec.id`
  /// (`../decision_condition_catalog.dart`).
  TextColumn get conditionId => text().named('condition_id')();

  /// JSON-encoded `Map<String, dynamic>` of this condition's parameter
  /// values.
  TextColumn get conditionParamsJson => text().named('condition_params_json')();

  /// `'node'`/`'proceed'`/`'gated'`/`'decline'`/`'modelJudgment'` — see
  /// this table's own dartdoc.
  TextColumn get matchedBranchKind => text().named('matched_branch_kind')();

  /// Set only when [matchedBranchKind] is `'node'` — the child node's id.
  TextColumn get matchedBranchNodeId =>
      text().named('matched_branch_node_id').nullable()();

  /// Same shape as [matchedBranchKind], for the unmatched branch.
  TextColumn get unmatchedBranchKind => text().named('unmatched_branch_kind')();

  /// Same shape as [matchedBranchNodeId], for the unmatched branch.
  TextColumn get unmatchedBranchNodeId =>
      text().named('unmatched_branch_node_id').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
