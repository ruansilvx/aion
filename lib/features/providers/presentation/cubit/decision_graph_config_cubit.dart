// presentation/cubit/decision_graph_config_cubit.dart — DecisionGraphConfigCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/automation/automation_context.dart';
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
/// referenced as a child (via a `DecisionBranch.toNode` on some other node's
/// `matchedBranch`/`unmatchedBranch`) from at most one branch across the whole
/// graph, and following every node's branches from the graph's root must never
/// revisit a node (no cycles). [createNode]/ [updateNode] reject an edit that
/// would violate either rule, emitting [DecisionGraphConfigError] and leaving
/// the prior [DecisionGraphConfigLoaded] state's tree untouched. See `AIO-181`
/// §3.
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
  /// `null` if the write was rejected.
  ///
  /// A freshly created node isn't reachable from the graph's root yet
  /// (`DecisionGraphRepository.getAllNodes` only returns nodes reachable by
  /// walking from the root), so the post-write [load] this method calls would
  /// normally drop it straight back out of
  /// [DecisionGraphConfigLoaded.nodesById] — which broke every caller that
  /// immediately follows up with [updateNode]/[setRoot] to attach the new node
  /// (the form's "continue to condition" chaining flow, and the empty-graph
  /// "add first condition" flow both do exactly this): that follow-up call
  /// would see the just-created id as absent from
  /// [DecisionGraphConfigLoaded.nodesById] and reject with
  /// [DecisionGraphConfigErrorReason.danglingBranchTarget]/`nodeNotFound`,
  /// discarding the edit. Fixed by re-merging the new orphan node into the
  /// reloaded state whenever the reload didn't already pick it up — found via
  /// manual QA of `AIO-181` (`/verify` follow-up), see that change's
  /// `tasks.md` for the reproduction. An orphan that's never subsequently
  /// attached (the user abandons the edit) simply stays in this merged-in
  /// state until the next full [load] — matches [deleteNode]'s existing
  /// "cleanup is the editor UI's responsibility" precedent.
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
    final violation = _validateTree(candidate);
    if (violation != null) {
      _emitInvariantError(loaded, violation);
      return null;
    }

    await _repository.upsertNode(node);
    await load(loaded.context);
    if (isClosed) return node.id;
    final reloaded = _requireLoaded();
    if (reloaded != null && !reloaded.nodesById.containsKey(node.id)) {
      emit(
        DecisionGraphConfigLoaded(
          context: reloaded.context,
          graph: reloaded.graph,
          nodesById: {...reloaded.nodesById, node.id: node},
        ),
      );
    }
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
    final violation = _validateTree(candidate);
    if (violation != null) {
      _emitInvariantError(loaded, violation);
      return;
    }

    await _repository.upsertNode(node);
    await load(loaded.context);
  }

  /// Deletes the node with id [id] and every node transitively reachable from
  /// it via a matched/unmatched [ToNodeBranch] (its descendants), clearing the
  /// graph root first if [id] was the root. Never rejected — deleting a node
  /// can only ever shrink the tree, so it can't violate the strict-tree
  /// invariant. Matches design.md §3.5's "Deleting a node with children asks
  /// first ... `Delete this condition and its 2 descendants?`" — the confirm
  /// dialog promises cascading deletion, so this actually performs it rather
  /// than leaving descendants orphaned in the repository (unreachable from the
  /// root, but never actually removed). Fixed via manual QA of `AIO-181` — the
  /// previous single-node delete left every descendant as leaked, permanently
  /// unreachable rows.
  Future<void> deleteNode(String id) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;
    if (!loaded.nodesById.containsKey(id)) return;

    for (final nodeId in descendantIdsOf(id, loaded.nodesById)) {
      await _repository.deleteNode(nodeId);
    }
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
  /// update edit already merged in): every node id is referenced as a
  /// `DecisionBranch.toNode` target from at most one branch anywhere in
  /// [nodesById], every such target actually exists in [nodesById], and
  /// no cycle exists anywhere in [nodesById] — checked across the whole
  /// node set (see [_detectCycle]'s own dartdoc for why this isn't scoped
  /// to the graph's current root). Returns the classified rejection
  /// reason, or `null` if the tree is valid.
  DecisionGraphConfigErrorReason? _validateTree(
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

    if (_detectCycle(nodesById)) {
      return DecisionGraphConfigErrorReason.cycleDetected;
    }

    return null;
  }

  /// Whether [nodesById] contains a cycle anywhere in its
  /// `DecisionBranch.toNode` edges — an iterative depth-first search from
  /// every node (not just `DecisionGraph.rootNodeId`), marking each node on
  /// the current path (`onPath`) versus fully explored (`visited`), the
  /// standard three-color cycle check. Scoped to the whole node set rather
  /// than a root-reachability walk so a cycle among nodes not yet attached to
  /// the live tree — e.g. two freshly [createNode]-d nodes wired into a mutual
  /// loop before either is attached as anyone's branch target or set as the
  /// root — is rejected too, not just a cycle already reachable from the root.
  /// Added for `AIO-181` (`/verify` fix pass 2 — the previous root-only walk
  /// missed exactly this case).
  bool _detectCycle(Map<String, DecisionNode> nodesById) {
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
            ? const <DecisionBranch>[]
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
        if (branch is! ToNodeBranch) continue;
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
/// matched/unmatched [ToNodeBranch] edge (its descendants), looked up in
/// [nodesById] — the full set of ids [DecisionGraphConfigCubit.deleteNode]
/// removes for [id]. Shared with the editor UI (`DecisionNodeForm`'s
/// delete-confirm dialog) so the descendant count it displays always
/// matches what the cascading delete actually removes. A [ToNodeBranch]
/// target missing from [nodesById] (a dangling reference) is simply not
/// walked further, the same defensive treatment
/// `decision_graph_evaluator.dart` gives it at evaluation time.
Set<String> descendantIdsOf(String id, Map<String, DecisionNode> nodesById) {
  final result = <String>{};
  final stack = [id];
  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    if (!result.add(current)) continue;
    final node = nodesById[current];
    if (node == null) continue;
    for (final branch in [node.matchedBranch, node.unmatchedBranch]) {
      if (branch is ToNodeBranch) stack.add(branch.nodeId);
    }
  }
  return result;
}
