// core/automation/data/drift_decision_graph_repository.dart — Drift implementation of DecisionGraphRepository (data layer).

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/data/automation_decision_dao.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_graph_repository.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';
import 'package:aion/core/database/app_database.dart';

/// Drift-backed implementation of [DecisionGraphRepository]. No business logic
/// here — maps [AutomationDecisionGraphData]/ [AutomationDecisionNodeData]
/// rows to [DecisionGraph]/[DecisionNode] entities and delegates every method
/// straight to [AutomationDecisionDao], matching every other
/// `Drift*Repository` in this codebase. Added for `AIO-181`.
class DriftDecisionGraphRepository implements DecisionGraphRepository {
  /// Creates a [DriftDecisionGraphRepository] backed by [_db].
  DriftDecisionGraphRepository(this._db);

  final AppDatabase _db;

  /// Broadcast controller backing [onChanged] — fired after every
  /// successful write below. `sync: true` since listeners (`TicketsCubit`/
  /// `DecisionGraphConfigCubit`) only ever re-read state asynchronously in
  /// response, never re-enter this repository synchronously.
  final _changeController = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get onChanged => _changeController.stream;

  @override
  Future<DecisionGraph> getGraph(AutomationContext context) async {
    final row = await _db.automationDecisionDao.getGraph(context);
    if (row == null) {
      return DecisionGraph(context: context, rootNodeId: null);
    }
    return DecisionGraph(context: context, rootNodeId: row.rootNodeId);
  }

  @override
  Future<DecisionNode?> getNode(String id) async {
    final row = await _db.automationDecisionDao.getNode(id);
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<List<DecisionNode>> getAllNodes(AutomationContext context) async {
    final graph = await getGraph(context);
    final rootId = graph.rootNodeId;
    if (rootId == null) return [];

    final rows = await _db.automationDecisionDao.getAllNodes();
    final byId = {for (final row in rows) row.id: row};

    final result = <DecisionNode>[];
    final toVisit = <String>[rootId];
    final visited = <String>{};
    while (toVisit.isNotEmpty) {
      final id = toVisit.removeLast();
      if (!visited.add(id)) continue;
      final row = byId[id];
      if (row == null) continue;
      final node = _toEntity(row);
      result.add(node);
      for (final branch in [node.matchedBranch, node.unmatchedBranch]) {
        if (branch is ToNodeBranch) toVisit.add(branch.nodeId);
      }
    }
    return result;
  }

  @override
  Future<void> upsertNode(DecisionNode node) async {
    await _db.automationDecisionDao.upsertNode(_toCompanion(node));
    _changeController.add(null);
  }

  @override
  Future<void> deleteNode(String id) async {
    await _db.automationDecisionDao.deleteNode(id);
    _changeController.add(null);
  }

  @override
  Future<void> setRoot(AutomationContext context, String? nodeId) async {
    await _db.automationDecisionDao.setRoot(context, nodeId);
    _changeController.add(null);
  }

  @override
  Future<void> seedDefaultsIfEmpty() {
    return _db.automationDecisionDao.seedDefaultsIfEmpty();
  }

  /// Maps a domain [DecisionNode] to its persisted-row companion,
  /// decomposing [DecisionNode.matchedBranch]/[DecisionNode.unmatchedBranch]
  /// into the table's `*Kind`/`*NodeId` column pair.
  AutomationDecisionNodesTableCompanion _toCompanion(DecisionNode node) {
    final (matchedKind, matchedNodeId) = _toColumns(node.matchedBranch);
    final (unmatchedKind, unmatchedNodeId) = _toColumns(node.unmatchedBranch);
    return AutomationDecisionNodesTableCompanion(
      id: Value(node.id),
      conditionId: Value(node.conditionId),
      conditionParamsJson: Value(jsonEncode(node.conditionParams)),
      matchedBranchKind: Value(matchedKind),
      matchedBranchNodeId: Value(matchedNodeId),
      unmatchedBranchKind: Value(unmatchedKind),
      unmatchedBranchNodeId: Value(unmatchedNodeId),
    );
  }

  /// Decomposes [branch] into its `(kind, nodeId)` column-pair
  /// representation — `('node', id)` for [ToNodeBranch], or
  /// `(outcome.name, null)` for [TerminalBranch].
  (String, String?) _toColumns(DecisionBranch branch) {
    return switch (branch) {
      ToNodeBranch(:final nodeId) => ('node', nodeId),
      TerminalBranch(:final outcome) => (outcome.name, null),
    };
  }

  /// Maps a generated [AutomationDecisionNodeData] row to the
  /// [DecisionNode] domain entity, reconstructing [DecisionBranch] from
  /// each `*Kind`/`*NodeId` column pair.
  DecisionNode _toEntity(AutomationDecisionNodeData row) {
    return DecisionNode(
      id: row.id,
      conditionId: row.conditionId,
      conditionParams:
          jsonDecode(row.conditionParamsJson) as Map<String, dynamic>,
      matchedBranch: _toBranch(row.matchedBranchKind, row.matchedBranchNodeId),
      unmatchedBranch: _toBranch(
        row.unmatchedBranchKind,
        row.unmatchedBranchNodeId,
      ),
    );
  }

  /// Reconstructs a [DecisionBranch] from a `*Kind`/`*NodeId` column
  /// pair — `'node'` (with [nodeId] set) becomes [DecisionBranch.toNode];
  /// any other [kind] is parsed as a terminal [DecisionOutcome] name,
  /// falling back to [DecisionOutcome.proceed] for a value that somehow
  /// doesn't match any outcome (defensive — should be unreachable given
  /// every write path goes through [_toColumns]).
  DecisionBranch _toBranch(String kind, String? nodeId) {
    if (kind == 'node' && nodeId != null) {
      return DecisionBranch.toNode(nodeId);
    }
    final outcome = DecisionOutcome.values
        .where((o) => o.name == kind)
        .firstOrNull;
    return DecisionBranch.terminal(outcome ?? DecisionOutcome.proceed);
  }
}
