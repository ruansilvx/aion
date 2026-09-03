// core/automation/decision_graph.dart — DecisionGraph entity (core layer).

import 'package:meta/meta.dart';

import 'package:aion/core/automation/automation_context.dart';

/// A project-authored decision graph for one [AutomationContext] — a
/// strict binary tree of [DecisionNode]s (`decision_node.dart`), only
/// ever consulted once that context's persisted `AutomationConfidence`
/// has already resolved to `AutomationConfidence.auto`. Added for
/// `AIO-181`.
@immutable
class DecisionGraph {
  /// Creates a [DecisionGraph].
  const DecisionGraph({required this.context, required this.rootNodeId});

  /// Which [AutomationContext] this graph governs.
  final AutomationContext context;

  /// The id of the tree's entry-point `DecisionNode`, or `null` if no
  /// graph is configured for [context] yet — meaning `auto` always
  /// resolves to `DecisionOutcome.proceed`, exactly as plain `auto`
  /// confidence always has.
  final String? rootNodeId;

  /// Returns a copy of this graph with [rootNodeId] replaced.
  DecisionGraph copyWithRoot(String? rootNodeId) =>
      DecisionGraph(context: context, rootNodeId: rootNodeId);

  @override
  bool operator ==(Object other) =>
      other is DecisionGraph &&
      other.context == context &&
      other.rootNodeId == rootNodeId;

  @override
  int get hashCode => Object.hash(context, rootNodeId);
}
