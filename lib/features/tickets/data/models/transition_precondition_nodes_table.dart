// data/models/transition_precondition_nodes_table.dart — Drift table definition for transition_precondition_nodes (data layer).

import 'package:drift/drift.dart';

/// Drift table persisting one row per `TransitionNode`
/// (`../../domain/entities/transition_node.dart`) — a strict-tree field-
/// check node belonging to one `SddStage`'s transition-precondition graph.
/// Row type is generated as [TransitionPreconditionNodeData].
/// `matchedBranchKind`/`unmatchedBranchKind` hold `'node'`/`'allowed'`/
/// `'blocked'` — `'node'` means the corresponding `*BranchNodeId` column
/// holds the child node's id; every other value is a terminal
/// `TransitionOutcome` name and leaves that column `null`. No FK
/// constraints on the node-id columns (nor on which
/// `TransitionPreconditionGraphsTable` row a node belongs to — that's
/// implicit via graph traversal from the root, not a stored parent
/// pointer) — integrity is enforced at the `TransitionPreconditionConfigCubit`
/// layer, matching every other table in this schema (mirrors
/// `core/automation/data/automation_decision_nodes_table.dart`'s exact
/// shape, minus its `condition_params_json` column — no field here takes a
/// parameter). See
/// `AIO-1936` §2.
@DataClassName('TransitionPreconditionNodeData')
class TransitionPreconditionNodesTable extends Table {
  @override
  String get tableName => 'transition_precondition_nodes';

  /// Internal UUID v4 primary key.
  TextColumn get id => text()();

  /// References a `TransitionFieldSpec.id`
  /// (`../../domain/entities/transition_field_spec.dart`).
  TextColumn get fieldId => text().named('field_id')();

  /// `'node'`/`'allowed'`/`'blocked'` — see this table's own dartdoc.
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
