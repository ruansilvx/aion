// core/automation/decision_graph_repository.dart — DecisionGraphRepository interface (core layer).

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_node.dart';

/// Read/write access to [DecisionGraph]/[DecisionNode] persistence. A dumb
/// persistence layer only — no validation, no invariant enforcement. The
/// strict-tree invariant (a node referenced as a child from at most one
/// branch) lives in `DecisionGraphConfigCubit`, per this project's
/// Cubit-vs-repository split (validation/invariant logic lives in Cubits, not
/// repositories). Implemented by the data layer
/// (`DriftDecisionGraphRepository`); UI and domain code depend only on this
/// interface, never on a concrete data source. Added for `AIO-181`.
abstract interface class DecisionGraphRepository {
  /// Returns [context]'s currently-configured [DecisionGraph], defaulting
  /// to `DecisionGraph(context: context, rootNodeId: null)` — always
  /// `DecisionOutcome.proceed` — if [context] hasn't been seeded yet.
  Future<DecisionGraph> getGraph(AutomationContext context);

  /// Returns the [DecisionNode] with id [id], or `null` if none exists.
  Future<DecisionNode?> getNode(String id);

  /// Returns every [DecisionNode] belonging to [context]'s graph.
  Future<List<DecisionNode>> getAllNodes(AutomationContext context);

  /// Persists [node] — creating it if its id is new, replacing its
  /// existing row otherwise (matched by [DecisionNode.id]).
  Future<void> upsertNode(DecisionNode node);

  /// Deletes the node with id [id].
  Future<void> deleteNode(String id);

  /// Sets [context]'s graph root to [nodeId] (`null` clears it, meaning
  /// "no graph configured, always `proceed`").
  Future<void> setRoot(AutomationContext context, String? nodeId);

  /// Seeds a [DecisionGraph] row for every [AutomationContext] value iff
  /// none exist yet (idempotent) — a `null`-root graph for every context
  /// except [AutomationContext.codingExecutionRetry]/
  /// [AutomationContext.codingExecution], which each also get a single
  /// baseline [DecisionNode] reproducing their former hardcoded ad hoc
  /// check as data. Called once at app startup for the active project,
  /// and by the schema-18 migration's backfill for every pre-existing
  /// project. A no-op when any [DecisionGraph] row already exists, so
  /// it's safe to call unconditionally — mirrors
  /// `WorkflowStatusRepository.seedDefaultsIfEmpty`'s own precedent.
  Future<void> seedDefaultsIfEmpty();

  /// Fires (with no payload) after every successful [upsertNode]/
  /// [deleteNode]/[setRoot] write. This is the "config changed" signal
  /// `TicketsCubit`'s cached decision-graph copy and
  /// `DecisionGraphConfigCubit`'s own state subscribe to, so the two
  /// Cubits stay consistent through the repository layer rather than
  /// holding a direct reference to each other — mirrors
  /// `WorkflowStatusRepository.onChanged`'s own precedent.
  Stream<void> get onChanged;
}
