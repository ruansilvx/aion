// core/automation/default_decision_graphs.dart — baseline DecisionGraph/DecisionNode fallback data (core layer).

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_condition_catalog.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';

/// Node id for [defaultDecisionNodesById]'s
/// [AutomationContext.codingExecutionRetry] baseline node.
const attemptExceedsMaxDefaultNodeId = 'default-attempt-exceeds-max';

/// Node id for [defaultDecisionNodesById]'s
/// [AutomationContext.codingExecution] baseline node.
const sessionOverageDetectedDefaultNodeId = 'default-session-overage-detected';

/// The baseline `DecisionGraph`/`DecisionNode` data reproducing this
/// codebase's pre-`aion-arch/changes/automation-decision-graphs`
/// hardcoded checks — a single node per context: `attemptExceedsMax`
/// (maxAttempts: 2) for [AutomationContext.codingExecutionRetry],
/// `sessionOverageDetected` for [AutomationContext.codingExecution].
/// Every other context has no baseline node (its
/// [defaultDecisionGraphFor] resolves a `null` root).
///
/// Two consumers share this single source of truth so it's never
/// duplicated as inline literals:
/// - `AutomationDecisionDao.seedDefaultsIfEmpty` persists it into a
///   fresh project's database (and backfills it for every pre-18
///   database on upgrade).
/// - `TicketsCubit._evaluateDecisionGraph` falls back to it directly
///   (no I/O) when constructed without a `DecisionGraphRepository` —
///   mirroring `defaultWorkflowStatuses`'s own no-repository fallback
///   precedent, so a cubit built without one still enforces the
///   `codingExecutionRetry` cap and the `codingExecution` overage-forces-
///   `gated` behavior exactly as it did before this graph mechanism
///   existed, rather than silently no-opping into an unbounded retry
///   loop. Every other context's `null`-root fallback already matches
///   plain `auto` confidence's pre-existing behavior with no data needed.
final Map<String, DecisionNode> defaultDecisionNodesById = {
  attemptExceedsMaxDefaultNodeId: DecisionNode(
    id: attemptExceedsMaxDefaultNodeId,
    conditionId: attemptExceedsMaxCondition.id,
    conditionParams: const {'maxAttempts': 2},
    matchedBranch: const DecisionBranch.terminal(DecisionOutcome.gated),
    unmatchedBranch: const DecisionBranch.terminal(DecisionOutcome.proceed),
  ),
  sessionOverageDetectedDefaultNodeId: DecisionNode(
    id: sessionOverageDetectedDefaultNodeId,
    conditionId: sessionOverageDetectedCondition.id,
    conditionParams: const {},
    matchedBranch: const DecisionBranch.terminal(DecisionOutcome.gated),
    unmatchedBranch: const DecisionBranch.terminal(DecisionOutcome.proceed),
  ),
};

/// The baseline [DecisionGraph] for [context] — see
/// [defaultDecisionNodesById]'s dartdoc. A `null`-root graph for every
/// context except [AutomationContext.codingExecutionRetry]/
/// [AutomationContext.codingExecution].
DecisionGraph defaultDecisionGraphFor(AutomationContext context) {
  final rootNodeId = switch (context) {
    AutomationContext.codingExecutionRetry => attemptExceedsMaxDefaultNodeId,
    AutomationContext.codingExecution => sessionOverageDetectedDefaultNodeId,
    AutomationContext.sddStage ||
    AutomationContext.chatBranching ||
    AutomationContext.codingExecutionResume ||
    AutomationContext.ticketCreation ||
    AutomationContext.ticketLinking ||
    AutomationContext.specAutoLink => null,
  };
  return DecisionGraph(context: context, rootNodeId: rootNodeId);
}
