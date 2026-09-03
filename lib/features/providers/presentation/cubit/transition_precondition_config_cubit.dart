// presentation/cubit/transition_precondition_config_cubit.dart — TransitionPreconditionConfigCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/features/providers/presentation/cubit/transition_precondition_config_state.dart';
import 'package:aion/features/tickets/domain/entities/transition_branch.dart';
import 'package:aion/features/tickets/domain/entities/transition_node.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/transition_outcome.dart';
import 'package:aion/features/tickets/domain/repositories/transition_precondition_repository.dart';

/// Owns [TransitionNode]/[TransitionGraph] CRUD for the dual-pane
/// `SddStagePreconditionEditorScreen`, enforcing the invariant `TicketsCubit`
/// never checks — domain/invariant logic lives in Cubits, not repositories,
/// per this project's Cubit-vs-repository split. Backs both
/// `PreconditionGraphCanvas`/`GraphCanvas<TransitionNode>` and
/// `TransitionOutlineList`. Mirrors `DecisionGraphConfigCubit`'s exact shape —
/// see `AIO-1936` §5 — with rejection messages built directly as plain strings
/// rather than a classified reason enum, since this cubit has no
/// `BuildContext`-resolvable widget-layer error-message function of its own (a
/// deliberate simplification: see `TransitionPreconditionConfigError`'s own
/// dartdoc).
///
/// One enforced invariant, the strict-tree constraint: a node may be
/// referenced as a child (via a `TransitionBranch.toNode` on some other node's
/// `matchedBranch`/`unmatchedBranch`) from at most one branch across the whole
/// graph, and following every node's branches from the graph's root must never
/// revisit a node (no cycles). [createNode]/ [updateNode] reject an edit that
/// would violate either rule, emitting [TransitionPreconditionConfigError] and
/// leaving the prior [TransitionPreconditionConfigLoaded] state's tree
/// untouched. Added for `AIO-1936`.
class TransitionPreconditionConfigCubit
    extends Cubit<TransitionPreconditionConfigState> {
  /// Creates a [TransitionPreconditionConfigCubit] backed by
  /// [_repository].
  TransitionPreconditionConfigCubit(this._repository)
    : super(const TransitionPreconditionConfigInitial());

  final TransitionPreconditionRepository _repository;

  static const _uuid = Uuid();

  /// Loads [stage]'s currently-configured graph and every node reachable
  /// from its root, and emits [TransitionPreconditionConfigLoaded].
  Future<void> load(SddStage stage) async {
    final graph = await _repository.getGraph(stage);
    final nodes = await _repository.getAllNodes(stage);
    if (isClosed) return;
    emit(
      TransitionPreconditionConfigLoaded(
        stage: stage,
        graph: graph,
        nodesById: {for (final node in nodes) node.id: node},
      ),
    );
  }

  /// Creates a fresh [TransitionNode] (a new UUID v4 id) for [fieldId],
  /// with [matchedBranch]/[unmatchedBranch] both defaulting to
  /// `TransitionBranch.terminal(TransitionOutcome.blocked)` — the safest
  /// starting shape for a gate (an unedited new node blocks rather than
  /// silently allowing). Rejects if attaching either branch (when the
  /// caller passes a `TransitionBranch.toNode` pointing at an existing
  /// node) would violate the strict-tree invariant. Returns the new
  /// node's id, or `null` if the write was rejected.
  ///
  /// A freshly created node isn't reachable from the graph's root yet
  /// (`TransitionPreconditionRepository.getAllNodes` only returns nodes
  /// reachable by walking from the root), so the post-write [load] this
  /// method calls would normally drop it straight back out of
  /// [TransitionPreconditionConfigLoaded.nodesById] — mirrors
  /// `DecisionGraphConfigCubit.createNode`'s own fix for exactly this
  /// case: re-merges the new orphan node into the reloaded state whenever
  /// the reload didn't already pick it up, so a follow-up [updateNode]/
  /// [setRoot] call (the form's "continue to field check" chaining flow)
  /// doesn't reject with [nodeNotFound].
  Future<String?> createNode({
    required String fieldId,
    TransitionBranch matchedBranch = const TransitionBranch.terminal(
      TransitionOutcome.blocked,
    ),
    TransitionBranch unmatchedBranch = const TransitionBranch.terminal(
      TransitionOutcome.blocked,
    ),
  }) async {
    final loaded = _requireLoaded();
    if (loaded == null) return null;

    final node = TransitionNode(
      id: _uuid.v4(),
      fieldId: fieldId,
      matchedBranch: matchedBranch,
      unmatchedBranch: unmatchedBranch,
    );
    final candidate = {...loaded.nodesById, node.id: node};
    final violation = _validateTree(candidate);
    if (violation != null) {
      _emitInvariantError(loaded, violation);
      return null;
    }

    await _repository.upsertNode(node);
    await load(loaded.stage);
    if (isClosed) return node.id;
    final reloaded = _requireLoaded();
    if (reloaded != null && !reloaded.nodesById.containsKey(node.id)) {
      emit(
        TransitionPreconditionConfigLoaded(
          stage: reloaded.stage,
          graph: reloaded.graph,
          nodesById: {...reloaded.nodesById, node.id: node},
        ),
      );
    }
    return node.id;
  }

  /// Replaces [node]'s row (matched by [TransitionNode.id], which must
  /// already exist in the loaded graph — see [createNode] for adding a
  /// new one). Rejects if the resulting tree would violate the
  /// strict-tree invariant.
  Future<void> updateNode(TransitionNode node) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;

    if (!loaded.nodesById.containsKey(node.id)) {
      _emitInvariantError(loaded, _nodeNotFoundMessage);
      return;
    }

    final candidate = {...loaded.nodesById, node.id: node};
    final violation = _validateTree(candidate);
    if (violation != null) {
      _emitInvariantError(loaded, violation);
      return;
    }

    await _repository.upsertNode(node);
    await load(loaded.stage);
  }

  /// Deletes the node with id [id] and every node transitively reachable
  /// from it via a matched/unmatched [ToTransitionNodeBranch] (its
  /// descendants), clearing the graph root first if [id] was the root.
  /// Never rejected — deleting a node can only ever shrink the tree, so
  /// it can't violate the strict-tree invariant.
  Future<void> deleteNode(String id) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;
    if (!loaded.nodesById.containsKey(id)) return;

    for (final nodeId in descendantIdsOf(id, loaded.nodesById)) {
      await _repository.deleteNode(nodeId);
    }
    if (loaded.graph.rootNodeId == id) {
      await _repository.setRoot(loaded.stage, null);
    }
    await load(loaded.stage);
  }

  /// Sets the loaded graph's root to [nodeId] (`null` clears it, meaning
  /// "no precondition configured, stage always advances freely").
  /// Rejects if [nodeId] doesn't resolve to a node already in the loaded
  /// tree.
  Future<void> setRoot(String? nodeId) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;

    if (nodeId != null && !loaded.nodesById.containsKey(nodeId)) {
      _emitInvariantError(loaded, _nodeNotFoundMessage);
      return;
    }

    await _repository.setRoot(loaded.stage, nodeId);
    await load(loaded.stage);
  }

  /// Returns [state] as a [TransitionPreconditionConfigLoaded] — from
  /// [state] itself, or from a [TransitionPreconditionConfigError]'s
  /// carried [previous] — or `null` if [load] hasn't resolved yet. Every
  /// mutating method starts by calling this; a `null` result means the
  /// write is silently ignored, mirroring
  /// `DecisionGraphConfigCubit._requireLoaded`'s exact shape.
  TransitionPreconditionConfigLoaded? _requireLoaded() => switch (state) {
    TransitionPreconditionConfigLoaded loaded => loaded,
    TransitionPreconditionConfigError(:final previous) => previous,
    TransitionPreconditionConfigInitial() => null,
  };

  static const _nodeNotFoundMessage =
      'This field check no longer exists in the loaded tree.';
  static const _danglingBranchTargetMessage =
      'A branch points at a field check that no longer exists.';
  static const _duplicateChildReferenceMessage =
      'A field check can only be reached from one branch at a time.';
  static const _cycleDetectedMessage =
      'That change would create a loop in the tree.';

  /// Emits a [TransitionPreconditionConfigError] carrying [message],
  /// preserving [loaded] as the state's
  /// [TransitionPreconditionConfigError.previous].
  void _emitInvariantError(
    TransitionPreconditionConfigLoaded loaded,
    String message,
  ) {
    emit(TransitionPreconditionConfigError(message: message, previous: loaded));
  }

  /// Validates the strict-tree invariant against the hypothetical full
  /// node set [nodesById] (the currently-loaded set plus one create/
  /// update edit already merged in): every node id is referenced as a
  /// `TransitionBranch.toNode` target from at most one branch anywhere in
  /// [nodesById], every such target actually exists in [nodesById], and
  /// no cycle exists anywhere in [nodesById]. Returns the rejection
  /// message, or `null` if the tree is valid. Mirrors
  /// `DecisionGraphConfigCubit._validateTree`'s exact algorithm.
  String? _validateTree(Map<String, TransitionNode> nodesById) {
    final childReferenceCount = <String, int>{};
    for (final node in nodesById.values) {
      for (final branch in [node.matchedBranch, node.unmatchedBranch]) {
        if (branch is! ToTransitionNodeBranch) continue;
        if (!nodesById.containsKey(branch.nodeId)) {
          return _danglingBranchTargetMessage;
        }
        final count = (childReferenceCount[branch.nodeId] ?? 0) + 1;
        childReferenceCount[branch.nodeId] = count;
        if (count > 1) {
          return _duplicateChildReferenceMessage;
        }
      }
    }

    if (_detectCycle(nodesById)) {
      return _cycleDetectedMessage;
    }

    return null;
  }

  /// Whether [nodesById] contains a cycle anywhere in its
  /// `TransitionBranch.toNode` edges — an iterative depth-first search
  /// from every node (not just `TransitionGraph.rootNodeId`), marking
  /// each node on the current path (`onPath`) versus fully explored
  /// (`visited`), the standard three-color cycle check. Mirrors
  /// `DecisionGraphConfigCubit._detectCycle`'s exact algorithm.
  bool _detectCycle(Map<String, TransitionNode> nodesById) {
    final visited = <String>{};

    for (final startId in nodesById.keys) {
      if (visited.contains(startId)) continue;

      final onPath = <String>{startId};
      final stack = <String>[startId];
      final nextBranchIndex = <String, int>{};

      while (stack.isNotEmpty) {
        final currentId = stack.last;
        final node = nodesById[currentId];
        final branches = node == null
            ? const <TransitionBranch>[]
            : [node.matchedBranch, node.unmatchedBranch];
        final index = nextBranchIndex[currentId] ?? 0;

        if (index >= branches.length) {
          stack.removeLast();
          onPath.remove(currentId);
          visited.add(currentId);
          continue;
        }
        nextBranchIndex[currentId] = index + 1;

        final branch = branches[index];
        if (branch is! ToTransitionNodeBranch) continue;
        if (onPath.contains(branch.nodeId)) return true;
        if (visited.contains(branch.nodeId)) continue;
        stack.add(branch.nodeId);
        onPath.add(branch.nodeId);
      }
    }

    return false;
  }
}

/// [id] itself plus every node transitively reachable from it via a
/// matched/unmatched [ToTransitionNodeBranch] edge (its descendants),
/// looked up in [nodesById] — the full set of ids
/// [TransitionPreconditionConfigCubit.deleteNode] removes for [id].
/// Shared with the editor UI (`TransitionNodeForm`'s delete-confirm
/// dialog) so the descendant count it displays always matches what the
/// cascading delete actually removes. A [ToTransitionNodeBranch] target
/// missing from [nodesById] (a dangling reference) is simply not walked
/// further, the same defensive treatment `evaluate_transition_graph.dart`
/// gives it at evaluation time. Mirrors `descendantIdsOf`
/// (`decision_graph_config_cubit.dart`)'s exact algorithm.
Set<String> descendantIdsOf(String id, Map<String, TransitionNode> nodesById) {
  final result = <String>{};
  final stack = [id];
  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    if (!result.add(current)) continue;
    final node = nodesById[current];
    if (node == null) continue;
    for (final branch in [node.matchedBranch, node.unmatchedBranch]) {
      if (branch is ToTransitionNodeBranch) stack.add(branch.nodeId);
    }
  }
  return result;
}
