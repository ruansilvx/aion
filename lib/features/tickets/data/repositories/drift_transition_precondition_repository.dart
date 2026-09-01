// data/repositories/drift_transition_precondition_repository.dart — Drift implementation of TransitionPreconditionRepository (data layer).

import 'dart:async';

import 'package:drift/drift.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/daos/transition_precondition_dao.dart';
import 'package:aion/features/tickets/domain/entities/transition_branch.dart';
import 'package:aion/features/tickets/domain/entities/transition_node.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/transition_outcome.dart';
import 'package:aion/features/tickets/domain/repositories/transition_precondition_repository.dart';

/// Drift-backed implementation of [TransitionPreconditionRepository]. No
/// business logic here — maps [TransitionPreconditionNodeData] rows to
/// [TransitionNode] entities and delegates every method straight to
/// [TransitionPreconditionDao], matching every other `Drift*Repository` in
/// this codebase (mirrors `core/automation/data/drift_decision_graph_repository.dart`'s
/// exact shape). Added for
/// `aion-arch/changes/sddstage-transition-preconditions`.
class DriftTransitionPreconditionRepository
    implements TransitionPreconditionRepository {
  /// Creates a [DriftTransitionPreconditionRepository] backed by [_db].
  DriftTransitionPreconditionRepository(this._db);

  final AppDatabase _db;

  /// Broadcast controller backing [onChanged] — fired after every
  /// successful write below. `sync: true` since listeners (`TicketsCubit`/
  /// `TransitionPreconditionConfigCubit`) only ever re-read state
  /// asynchronously in response, never re-enter this repository
  /// synchronously.
  final _changeController = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get onChanged => _changeController.stream;

  @override
  Future<TransitionGraph> getGraph(SddStage stage) async {
    final row = await _db.transitionPreconditionDao.getGraph(stage);
    if (row == null) {
      return TransitionGraph(stage: stage, rootNodeId: null);
    }
    return TransitionGraph(stage: stage, rootNodeId: row.rootNodeId);
  }

  @override
  Future<TransitionNode?> getNode(String id) async {
    final row = await _db.transitionPreconditionDao.getNode(id);
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<List<TransitionNode>> getAllNodes(SddStage stage) async {
    final graph = await getGraph(stage);
    final rootId = graph.rootNodeId;
    if (rootId == null) return [];

    final rows = await _db.transitionPreconditionDao.getAllNodes();
    final byId = {for (final row in rows) row.id: row};

    final result = <TransitionNode>[];
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
        if (branch is ToTransitionNodeBranch) toVisit.add(branch.nodeId);
      }
    }
    return result;
  }

  @override
  Future<void> upsertNode(TransitionNode node) async {
    await _db.transitionPreconditionDao.upsertNode(_toCompanion(node));
    _changeController.add(null);
  }

  @override
  Future<void> deleteNode(String id) async {
    await _db.transitionPreconditionDao.deleteNode(id);
    _changeController.add(null);
  }

  @override
  Future<void> setRoot(SddStage stage, String? nodeId) async {
    await _db.transitionPreconditionDao.setRoot(stage, nodeId);
    _changeController.add(null);
  }

  @override
  Future<void> seedDefaultsIfEmpty() {
    return _db.transitionPreconditionDao.seedDefaultsIfEmpty();
  }

  @override
  Future<Map<SddStage, int>> getNodeCounts() async {
    final graphRows = await _db.transitionPreconditionDao.getAllGraphs();
    final nodeRows = await _db.transitionPreconditionDao.getAllNodes();
    final rowsById = {for (final row in nodeRows) row.id: row};

    final counts = <SddStage, int>{};
    for (final graphRow in graphRows) {
      final stage = SddStage.values
          .where((s) => s.name == graphRow.sddStage)
          .firstOrNull;
      if (stage == null) continue;

      final rootId = graphRow.rootNodeId;
      if (rootId == null) {
        counts[stage] = 0;
        continue;
      }

      // Walk the reachable set in memory — mirrors getAllNodes's own
      // traversal, but against the single already-fetched `rowsById`
      // rather than a per-stage query.
      final visited = <String>{};
      final toVisit = <String>[rootId];
      while (toVisit.isNotEmpty) {
        final id = toVisit.removeLast();
        if (!visited.add(id)) continue;
        final row = rowsById[id];
        if (row == null) continue;
        final node = _toEntity(row);
        for (final branch in [node.matchedBranch, node.unmatchedBranch]) {
          if (branch is ToTransitionNodeBranch) toVisit.add(branch.nodeId);
        }
      }
      counts[stage] = visited.length;
    }
    return counts;
  }

  /// Maps a domain [TransitionNode] to its persisted-row companion,
  /// decomposing [TransitionNode.matchedBranch]/
  /// [TransitionNode.unmatchedBranch] into the table's `*Kind`/`*NodeId`
  /// column pair.
  TransitionPreconditionNodesTableCompanion _toCompanion(TransitionNode node) {
    final (matchedKind, matchedNodeId) = _toColumns(node.matchedBranch);
    final (unmatchedKind, unmatchedNodeId) = _toColumns(node.unmatchedBranch);
    return TransitionPreconditionNodesTableCompanion(
      id: Value(node.id),
      fieldId: Value(node.fieldId),
      matchedBranchKind: Value(matchedKind),
      matchedBranchNodeId: Value(matchedNodeId),
      unmatchedBranchKind: Value(unmatchedKind),
      unmatchedBranchNodeId: Value(unmatchedNodeId),
    );
  }

  /// Decomposes [branch] into its `(kind, nodeId)` column-pair
  /// representation — `('node', id)` for [ToTransitionNodeBranch], or
  /// `(outcome.name, null)` for [TerminalTransitionBranch].
  (String, String?) _toColumns(TransitionBranch branch) {
    return switch (branch) {
      ToTransitionNodeBranch(:final nodeId) => ('node', nodeId),
      TerminalTransitionBranch(:final outcome) => (outcome.name, null),
    };
  }

  /// Maps a generated [TransitionPreconditionNodeData] row to the
  /// [TransitionNode] domain entity, reconstructing [TransitionBranch]
  /// from each `*Kind`/`*NodeId` column pair.
  TransitionNode _toEntity(TransitionPreconditionNodeData row) {
    return TransitionNode(
      id: row.id,
      fieldId: row.fieldId,
      matchedBranch: _toBranch(row.matchedBranchKind, row.matchedBranchNodeId),
      unmatchedBranch: _toBranch(
        row.unmatchedBranchKind,
        row.unmatchedBranchNodeId,
      ),
    );
  }

  /// Reconstructs a [TransitionBranch] from a `*Kind`/`*NodeId` column
  /// pair — `'node'` (with [nodeId] set) becomes
  /// [TransitionBranch.toNode]; any other [kind] is parsed as a terminal
  /// [TransitionOutcome] name, falling back to [TransitionOutcome.allowed]
  /// for a value that somehow doesn't match any outcome (defensive —
  /// should be unreachable given every write path goes through
  /// [_toColumns]).
  TransitionBranch _toBranch(String kind, String? nodeId) {
    if (kind == 'node' && nodeId != null) {
      return TransitionBranch.toNode(nodeId);
    }
    final outcome = TransitionOutcome.values
        .where((o) => o.name == kind)
        .firstOrNull;
    return TransitionBranch.terminal(outcome ?? TransitionOutcome.allowed);
  }
}
