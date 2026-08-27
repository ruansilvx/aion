// core/automation/decision_graph_evaluator.dart — evaluateDecisionGraph pure evaluator (core layer).

import 'package:meta/meta.dart';

import 'package:aion/core/automation/decision_condition_catalog.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';

/// Every value a [DecisionConditionSpec]'s evaluator might need to read,
/// bundled by the call site rather than fetched by
/// [evaluateDecisionGraph] itself — keeps that function pure (no I/O) and
/// trivially unit-testable. Every field is optional; a condition this
/// proposal doesn't ship (or a context whose graph has no configured
/// root) never reads most of them. Added for
/// `aion-arch/changes/automation-decision-graphs`.
@immutable
class DecisionEvalContext {
  /// Creates a [DecisionEvalContext].
  const DecisionEvalContext({
    this.attempt,
    this.sessionOverageDetected = false,
  });

  /// How many verification failures have happened so far this
  /// coding-execution run (1-based) — read by the `attemptExceedsMax`
  /// condition. `null` for any call site that doesn't track a retry
  /// attempt count.
  final int? attempt;

  /// Whether a budget/consumption overage has already been detected this
  /// session — read by the `sessionOverageDetected` condition.
  final bool sessionOverageDetected;
}

/// `conditionId → bool Function(DecisionEvalContext, params)` registry —
/// how each shipped [DecisionConditionSpec] is actually evaluated. Adding
/// a condition to `decision_condition_catalog.dart`'s catalog also means
/// adding its case here.
final Map<
  String,
  bool Function(DecisionEvalContext input, Map<String, dynamic> params)
>
_conditionEvaluators = {
  'attemptExceedsMax': (input, params) {
    final attempt = input.attempt;
    if (attempt == null) return false;
    final maxAttempts = (params['maxAttempts'] as num?)?.toInt() ?? 3;
    return attempt > maxAttempts;
  },
  'sessionOverageDetected': (input, _) => input.sessionOverageDetected,
};

/// Walks [graph] from its `DecisionGraph.rootNodeId`, evaluating each
/// [DecisionNode] (looked up in [nodesById]) against [input] via
/// [_conditionEvaluators], following `DecisionNode.matchedBranch`/
/// `.unmatchedBranch` until a `DecisionBranch.terminal` is reached.
/// Returns [DecisionOutcome.proceed] immediately if
/// `DecisionGraph.rootNodeId` is `null` (no graph configured) or if the
/// walk ever references a node id missing from [nodesById] (defensive —
/// a dangling reference should never silently block automation that
/// otherwise resolved to `auto`). Pure — no I/O, no dependency on
/// `DecisionGraphRepository`. Added for
/// `aion-arch/changes/automation-decision-graphs`.
DecisionOutcome evaluateDecisionGraph(
  DecisionGraph graph,
  Map<String, DecisionNode> nodesById,
  DecisionEvalContext input,
) {
  var currentId = graph.rootNodeId;
  if (currentId == null) return DecisionOutcome.proceed;

  while (true) {
    final node = nodesById[currentId];
    if (node == null) return DecisionOutcome.proceed;

    final evaluator = _conditionEvaluators[node.conditionId];
    final matched = evaluator?.call(input, node.conditionParams) ?? false;
    final branch = matched ? node.matchedBranch : node.unmatchedBranch;

    switch (branch) {
      case ToNodeBranch(:final nodeId):
        currentId = nodeId;
      case TerminalBranch(:final outcome):
        return outcome;
    }
  }
}
