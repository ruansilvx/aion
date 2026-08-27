// presentation/cubit/decision_graph_config_cubit.dart — DecisionGraphConfigCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_graph_repository.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_state.dart';

/// Owns [DecisionNode]/`DecisionGraph` CRUD for the dual-pane
/// `DecisionGraphEditorScreen`, enforcing the invariant `TicketsCubit`
/// never checks — domain/invariant logic lives in Cubits, not
/// repositories, per this project's Cubit-vs-repository split. Backs
/// both `GraphCanvas` and `DecisionOutlineList`.
///
/// One enforced invariant, the strict-tree constraint: a node may be
/// referenced as a child (via a `DecisionBranch.toNode` on some other
/// node's `matchedBranch`/`unmatchedBranch`) from at most one branch
/// across the whole graph, and following every node's branches from the
/// graph's root must never revisit a node (no cycles). [createNode]/
/// [updateNode] reject an edit that would violate either rule, emitting
/// [DecisionGraphConfigError] and leaving the prior [DecisionGraphConfigLoaded]
/// state's tree untouched. See
/// `aion-arch/changes/automation-decision-graphs/design.md` §3.
class DecisionGraphConfigCubit extends Cubit<DecisionGraphConfigState> {
  /// Creates a [DecisionGraphConfigCubit] backed by [_repository].
  DecisionGraphConfigCubit(this._repository)
    : super(const DecisionGraphConfigInitial());

  final DecisionGraphRepository _repository;

  static const _uuid = Uuid();

  /// Loads [context]'s currently-configured graph and every node
  /// reachable from its root, and emits [DecisionGraphConfigLoaded].
  Future<void> load(AutomationContext context) async {
    final graph = await _repository.getGraph(context);
    final nodes = await _repository.getAllNodes(context);
    if (isClosed) return;
    emit(
      DecisionGraphConfigLoaded(
        context: context,
        graph: graph,
        nodesById: {for (final node in nodes) node.id: node},
      ),
    );
  }

  /// Creates a fresh [DecisionNode] (a new UUID v4 id) for [conditionId]/
  /// [conditionParams], with [matchedBranch]/[unmatchedBranch] both
  /// defaulting to `DecisionBranch.terminal(DecisionOutcome.proceed)` —
  /// the safest starting shape, equivalent to no condition at all until
  /// edited further. Rejects if attaching either branch (when the caller
  /// passes a `DecisionBranch.toNode` pointing at an existing node) would
  /// violate the strict-tree invariant. Returns the new node's id, or
  /// `null` if the write was rejected — a freshly created node isn't
  /// reachable from the graph's root yet (`DecisionGraphRepository
  /// .getAllNodes` only returns nodes reachable by walking from the
  /// root), so a caller attaching it as the new root or as an existing
  /// node's branch target needs this id directly rather than trying to
  /// find it in the reloaded [DecisionGraphConfigLoaded.nodesById].
  Future<String?> createNode({
    required String conditionId,
    required Map<String, dynamic> conditionParams,
    DecisionBranch matchedBranch = const DecisionBranch.terminal(
      DecisionOutcome.proceed,
    ),
    DecisionBranch unmatchedBranch = const DecisionBranch.terminal(
      DecisionOutcome.proceed,
    ),
  }) async {
    final loaded = _requireLoaded();
    if (loaded == null) return null;

    final node = DecisionNode(
      id: _uuid.v4(),
      conditionId: conditionId,
      conditionParams: conditionParams,
      matchedBranch: matchedBranch,
      unmatchedBranch: unmatchedBranch,
    );
    final candidate = {...loaded.nodesById, node.id: node};
    final violation = _validateTree(loaded.graph, candidate);
    if (violation != null) {
      _emitInvariantError(loaded, violation);
      return null;
    }

    await _repository.upsertNode(node);
    await load(loaded.context);
    return node.id;
  }

  /// Replaces [node]'s row (matched by [DecisionNode.id], which must
  /// already exist in the loaded graph — see [createNode] for adding a
  /// new one). Rejects if the resulting tree would violate the
  /// strict-tree invariant.
  Future<void> updateNode(DecisionNode node) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;

    if (!loaded.nodesById.containsKey(node.id)) {
      _emitInvariantError(loaded, DecisionGraphConfigErrorReason.nodeNotFound);
      return;
    }

    final candidate = {...loaded.nodesById, node.id: node};
    final violation = _validateTree(loaded.graph, candidate);
    if (violation != null) {
      _emitInvariantError(loaded, violation);
      return;
    }

    await _repository.upsertNode(node);
    await load(loaded.context);
  }

  /// Deletes the node with id [id], clearing the graph root first if [id]
  /// was the root. Never rejected — deleting a node can only ever shrink
  /// the tree, so it can't violate the strict-tree invariant. Deleting a
  /// node still referenced by another node's branch leaves that branch
  /// dangling; `evaluateDecisionGraph` treats a dangling reference
  /// defensively as `DecisionOutcome.proceed`, and the editor UI is
  /// responsible for repointing or cascading the delete before the user
  /// leaves the screen.
  Future<void> deleteNode(String id) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;
    if (!loaded.nodesById.containsKey(id)) return;

    await _repository.deleteNode(id);
    if (loaded.graph.rootNodeId == id) {
      await _repository.setRoot(loaded.context, null);
    }
    await load(loaded.context);
  }

  /// Sets the loaded graph's root to [nodeId] (`null` clears it, meaning
  /// "no graph configured, always proceed"). Rejects if [nodeId] doesn't
  /// resolve to a node already in the loaded tree.
  Future<void> setRoot(String? nodeId) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;

    if (nodeId != null && !loaded.nodesById.containsKey(nodeId)) {
      _emitInvariantError(loaded, DecisionGraphConfigErrorReason.nodeNotFound);
      return;
    }

    await _repository.setRoot(loaded.context, nodeId);
    await load(loaded.context);
  }

  /// Returns [state] as a [DecisionGraphConfigLoaded] — from [state]
  /// itself, or from a [DecisionGraphConfigError]'s carried [previous] —
  /// or `null` if [load] hasn't resolved yet. Every mutating method
  /// starts by calling this; a `null` result means the write is silently
  /// ignored, mirroring `WorkflowConfigCubit._requireLoaded`'s exact
  /// shape.
  DecisionGraphConfigLoaded? _requireLoaded() => switch (state) {
    DecisionGraphConfigLoaded loaded => loaded,
    DecisionGraphConfigError(:final previous) => previous,
    DecisionGraphConfigInitial() => null,
  };

  /// Emits a [DecisionGraphConfigError] carrying [reason], preserving
  /// [loaded] as the state's [DecisionGraphConfigError.previous].
  void _emitInvariantError(
    DecisionGraphConfigLoaded loaded,
    DecisionGraphConfigErrorReason reason,
  ) {
    emit(DecisionGraphConfigError(reason: reason, previous: loaded));
  }

  /// Validates the strict-tree invariant against the hypothetical full
  /// node set [nodesById] (the currently-loaded set plus one create/
  /// update edit already merged in) for [graph]: every node id is
  /// referenced as a `DecisionBranch.toNode` target from at most one
  /// branch anywhere in [nodesById], every such target actually exists in
  /// [nodesById], and walking from [graph]'s root never revisits a node.
  /// Returns the classified rejection reason, or `null` if the tree is
  /// valid.
  DecisionGraphConfigErrorReason? _validateTree(
    DecisionGraph graph,
    Map<String, DecisionNode> nodesById,
  ) {
    final childReferenceCount = <String, int>{};
    for (final node in nodesById.values) {
      for (final branch in [node.matchedBranch, node.unmatchedBranch]) {
        if (branch is! ToNodeBranch) continue;
        if (!nodesById.containsKey(branch.nodeId)) {
          return DecisionGraphConfigErrorReason.danglingBranchTarget;
        }
        final count = (childReferenceCount[branch.nodeId] ?? 0) + 1;
        childReferenceCount[branch.nodeId] = count;
        if (count > 1) {
          return DecisionGraphConfigErrorReason.duplicateChildReference;
        }
      }
    }

    final rootId = graph.rootNodeId;
    if (rootId != null && nodesById.containsKey(rootId)) {
      final visited = <String>{};
      final stack = [rootId];
      while (stack.isNotEmpty) {
        final id = stack.removeLast();
        if (!visited.add(id)) {
          return DecisionGraphConfigErrorReason.cycleDetected;
        }
        final node = nodesById[id];
        if (node == null) continue;
        for (final branch in [node.matchedBranch, node.unmatchedBranch]) {
          if (branch is ToNodeBranch) stack.add(branch.nodeId);
        }
      }
    }

    return null;
  }
}
