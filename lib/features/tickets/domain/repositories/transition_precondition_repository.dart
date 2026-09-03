// domain/repositories/transition_precondition_repository.dart — TransitionPreconditionRepository interface (domain layer).

import 'package:meta/meta.dart';

import 'package:aion/features/tickets/domain/entities/transition_node.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';

/// A project-authored transition-precondition graph for one [SddStage] —
/// a strict binary tree of `TransitionNode`s. Mirrors
/// `core/automation/decision_graph.dart`'s `DecisionGraph` shape, one level
/// simpler (no separate condition-outcome enum to carry — `TransitionNode`
/// itself resolves outcomes via `TransitionBranch.terminal`). Added for
/// `AIO-1936`.
@immutable
class TransitionGraph {
  /// Creates a [TransitionGraph].
  const TransitionGraph({required this.stage, required this.rootNodeId});

  /// Which [SddStage] this graph governs.
  final SddStage stage;

  /// The id of the tree's entry-point `TransitionNode`, or `null` if no
  /// graph is configured for [stage] yet — meaning the stage always
  /// advances freely (`TransitionOutcome.allowed`).
  final String? rootNodeId;

  /// Returns a copy of this graph with [rootNodeId] replaced.
  TransitionGraph copyWithRoot(String? rootNodeId) =>
      TransitionGraph(stage: stage, rootNodeId: rootNodeId);

  @override
  bool operator ==(Object other) =>
      other is TransitionGraph &&
      other.stage == stage &&
      other.rootNodeId == rootNodeId;

  @override
  int get hashCode => Object.hash(stage, rootNodeId);
}

/// Read/write access to [TransitionGraph]/[TransitionNode] persistence. A
/// dumb persistence layer only — no validation, no invariant enforcement.
/// The strict-tree invariant (a node referenced as a child from at most one
/// branch) lives in `TransitionPreconditionConfigCubit`, per this project's
/// Cubit-vs-repository split (validation/invariant logic lives in Cubits,
/// not repositories). Implemented by the data layer
/// (`DriftTransitionPreconditionRepository`); UI and domain code depend
/// only on this interface, never on a concrete data source. Added for
/// `AIO-1936`.
abstract interface class TransitionPreconditionRepository {
  /// Returns [stage]'s currently-configured [TransitionGraph], defaulting
  /// to `TransitionGraph(stage: stage, rootNodeId: null)` — always
  /// `TransitionOutcome.allowed` — if [stage] hasn't been seeded yet.
  Future<TransitionGraph> getGraph(SddStage stage);

  /// Returns the [TransitionNode] with id [id], or `null` if none exists.
  Future<TransitionNode?> getNode(String id);

  /// Returns every [TransitionNode] belonging to [stage]'s graph.
  Future<List<TransitionNode>> getAllNodes(SddStage stage);

  /// Persists [node] — creating it if its id is new, replacing its
  /// existing row otherwise (matched by [TransitionNode.id]).
  Future<void> upsertNode(TransitionNode node);

  /// Deletes the node with id [id].
  Future<void> deleteNode(String id);

  /// Sets [stage]'s graph root to [nodeId] (`null` clears it, meaning "no
  /// graph configured, always allowed").
  Future<void> setRoot(SddStage stage, String? nodeId);

  /// Seeds a baseline [TransitionGraph]/[TransitionNode] set for each of
  /// the 5 precondition-bearing `SddStage` values (`exploring`,
  /// `verifying`, `proposed`, `designBrief`, `designSync`) iff none exist
  /// yet (idempotent) — each baseline tree reproduces that stage's exact
  /// pre-existing hardcoded `TicketsCubit._sddStageAdvanceCheck` branch as
  /// data, per
  /// `AIO-1936` §3.
  /// `null`/`archived` get no seeded graph — neither has a precondition
  /// today. Called once at app startup for the active project, and by the
  /// schema migration's backfill for every pre-existing project. A no-op
  /// when any [TransitionGraph] row already exists, so it's safe to call
  /// unconditionally — mirrors `WorkflowStatusRepository
  /// .seedDefaultsIfEmpty`'s own precedent.
  Future<void> seedDefaultsIfEmpty();

  /// Fires (with no payload) after every successful [upsertNode]/
  /// [deleteNode]/[setRoot] write. This is the "config changed" signal
  /// `TicketsCubit`'s cached graph copy and
  /// `TransitionPreconditionConfigCubit`'s own state subscribe to, so the
  /// two Cubits stay consistent through the repository layer rather than
  /// holding a direct reference to each other — mirrors
  /// `WorkflowStatusRepository.onChanged`'s own precedent.
  Stream<void> get onChanged;

  /// The current field-check count (every node reachable from its graph's
  /// root) for every [SddStage] that has ever been seeded/configured, in
  /// one batch — a stage with no graph row yet, or a graph row with a
  /// `null` root, contributes `0`. Powers `WorkflowStatusSettingsScreen`'s
  /// "Configure precondition" affordance count badge
  /// (`AIO-1936`
  /// §5.1/§5.2) without an N-query fan-out over the 5 precondition-bearing
  /// stages — implementations fetch every graph row and every node row
  /// once each, then walk each graph's reachable set in memory. Added for
  /// that change's post-`/verify` follow-up.
  Future<Map<SddStage, int>> getNodeCounts();
}
