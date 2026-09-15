// domain/repositories/transition_precondition_repository.dart — TransitionPreconditionRepository interface (domain layer).

import 'package:meta/meta.dart';

import 'package:aion/features/tickets/domain/entities/transition_node.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// A project-authored transition-precondition graph for one [SddStage] — a
/// strict binary tree of `TransitionNode`s. Mirrors
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

/// Read/write access to [TransitionGraph]/[TransitionNode] persistence. A dumb
/// persistence layer only — no validation, no invariant enforcement. The
/// strict-tree invariant (a node referenced as a child from at most one
/// branch) lives in `TransitionPreconditionConfigCubit`, per this project's
/// Cubit-vs-repository split (validation/invariant logic lives in Cubits, not
/// repositories). Implemented by the data layer
/// (`DriftTransitionPreconditionRepository`); UI and domain code depend only
/// on this interface, never on a concrete data source. Added for `AIO-1936`.
///
/// Originally keyed every graph by [SddStage] alone — one tree shared by
/// every ticket type reaching that stage. `AIO-2903` widened every
/// stage-taking method below to also take a [TicketType]`?` `type`:
/// `null` means "the shared, type-agnostic graph" (what every method meant
/// before this change, and still the only thing 5 of the 6
/// precondition-bearing stages ever use); a concrete [TicketType] means "this
/// type's own override graph" — currently only [TicketType.bug]'s `proposed`/
/// `applying` configure one. [getGraph]/[getAllNodes] resolve a concrete
/// [type] against its own override first, falling back to the shared graph
/// (`type: null`) if that type has never configured one — implementations
/// apply this fallback consistently, so callers never need to retry with
/// `null` themselves.
abstract interface class TransitionPreconditionRepository {
  /// Returns [stage]'s currently-configured [TransitionGraph] for [type] —
  /// [type]'s own override if one has been configured, else [stage]'s
  /// shared graph (`type: null`), else
  /// `TransitionGraph(stage: stage, rootNodeId: null)` — always
  /// `TransitionOutcome.allowed` — if neither has been seeded yet. Added the
  /// [type] parameter for `AIO-2903`.
  Future<TransitionGraph> getGraph(SddStage stage, TicketType? type);

  /// Returns the [TransitionNode] with id [id], or `null` if none exists.
  /// Node rows aren't `(SddStage, TicketType)`-scoped themselves — a node
  /// belongs to whichever graph's root can reach it — so this needs no
  /// [type] parameter, unchanged since `AIO-1936`.
  Future<TransitionNode?> getNode(String id);

  /// Returns every [TransitionNode] belonging to [stage]/[type]'s resolved
  /// graph (see [getGraph]'s fallback rule). Added the [type] parameter for
  /// `AIO-2903`.
  Future<List<TransitionNode>> getAllNodes(SddStage stage, TicketType? type);

  /// Persists [node] — creating it if its id is new, replacing its
  /// existing row otherwise (matched by [TransitionNode.id]). No [type]
  /// parameter, for the same reason as [getNode].
  Future<void> upsertNode(TransitionNode node);

  /// Deletes the node with id [id]. No [type] parameter, for the same
  /// reason as [getNode].
  Future<void> deleteNode(String id);

  /// Sets [stage]/[type]'s own graph root to [nodeId] (`null` clears it,
  /// meaning "no graph configured for this exact `(stage, type)`, fall back
  /// to the shared graph if [type] is non-`null`, else always allowed").
  /// Always writes [type]'s own row — never the shared graph, even if
  /// [type] is currently falling back to it — so configuring a type-specific
  /// override never mutates the graph other types still share. Added the
  /// [type] parameter for `AIO-2903`.
  Future<void> setRoot(SddStage stage, TicketType? type, String? nodeId);

  /// Seeds a baseline [TransitionGraph]/[TransitionNode] set for each of the
  /// 6 precondition-bearing `SddStage` values' shared graph (`exploring`,
  /// `verifying`, `proposed`, `designBrief`, `designSync`, `applying`) iff
  /// none exist yet (idempotent) — each baseline tree reproduces that
  /// stage's exact pre-existing hardcoded `TicketsCubit._sddStageAdvanceCheck`
  /// branch as data, per `AIO-1936` §3. `null`/`archived` get no seeded
  /// graph — neither has a precondition today. Called once at app startup
  /// for the active project, and by the schema migration's backfill for
  /// every pre-existing project. A no-op when any [TransitionGraph] row
  /// already exists, so it's safe to call unconditionally — mirrors
  /// `WorkflowStatusRepository .seedDefaultsIfEmpty`'s own precedent.
  ///
  /// `AIO-2903` added [TicketType.bug]'s own `(proposed, bug)`/
  /// `(applying, bug)` override seeds alongside the shared ones — see
  /// implementations' own dartdoc for why those two stages, specifically,
  /// need a Bug-only tree rather than sharing Epic/Story's.
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
  /// root) for every `(SddStage, TicketType?)` combination that has ever
  /// been seeded/configured, in one batch — a combination with no graph row
  /// yet, or a graph row with a `null` root, contributes `0`. Powers
  /// `WorkflowStatusSettingsScreen`'s "Configure precondition" affordance
  /// count badge (`AIO-1936` §5.1/§5.2) without an N-query fan-out —
  /// implementations fetch every graph row and every node row once each,
  /// then walk each graph's reachable set in memory. Added for that change's
  /// post-`/verify` follow-up; keyed by `(SddStage, TicketType?)` instead of
  /// `SddStage` alone since `AIO-2903`, with `null` meaning the shared graph,
  /// same as every other method above.
  Future<Map<(SddStage, TicketType?), int>> getNodeCounts();
}
