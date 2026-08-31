// core/automation/decision_graph_evaluator.dart — evaluateDecisionGraph pure evaluator (core layer).

import 'package:meta/meta.dart';

import 'package:aion/core/automation/decision_condition_catalog.dart';
import 'package:aion/core/automation/decision_field_catalog.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';
import 'package:aion/core/contracts/agent_session_handle.dart';

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
    this.session,
    this.askAgentJudgment,
  });

  /// How many verification failures have happened so far this
  /// coding-execution run (1-based) — read by the `attemptExceedsMax`
  /// condition. `null` for any call site that doesn't track a retry
  /// attempt count.
  final int? attempt;

  /// Whether a budget/consumption overage has already been detected this
  /// session — read by the `sessionOverageDetected` condition.
  final bool sessionOverageDetected;

  /// The in-flight run's resumable session, if one exists at this call
  /// site — read by the `agentJudgment` condition. `null` for every
  /// context with no live tool-call-blocked session (5 of 8
  /// `AutomationContext` values always pass `null` here; see
  /// proposal.md's "Why this only works for 3 of the 8" section).
  final AgentSessionHandle? session;

  /// Performs the actual `agentJudgment` round trip: asks [prompt] as a
  /// scoped yes/no question inside [session], returning `true`/`false`
  /// for a clear answer or `null` for anything else (no session
  /// available, the call errored, an ambiguous/empty response). Real I/O
  /// — the one reason [evaluateDecisionGraph] is no longer pure. `null`
  /// (the default) for a call site with no way to ask at all, in which
  /// case an `agentJudgment` node always resolves unmatched without
  /// attempting a call.
  final Future<bool?> Function(AgentSessionHandle session, String prompt)?
  askAgentJudgment;
}

/// The reserved `DecisionNode.conditionId` value marking an
/// `agentJudgment` condition — never collides with a real catalog
/// entry or [ruleBuilderConditionId].
const agentJudgmentConditionId = 'agentJudgment';

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
  'ruleBuilder': (input, params) => _evaluateRule(input, params),
};

/// `DecisionFieldSpec.id → current value` for every
/// `decisionFieldCatalog` entry — how [_evaluateRule] resolves
/// `params['field']` to the [DecisionEvalContext] value it names. Adding
/// a field to `decision_field_catalog.dart`'s catalog also means adding
/// its accessor here.
final Map<String, Object? Function(DecisionEvalContext input)> _fieldAccessors =
    {
      'attempt': (input) => input.attempt,
      'sessionOverageDetected': (input) => input.sessionOverageDetected,
    };

/// Evaluates a `ruleBuilder` condition: resolves `params['field']` via
/// [_fieldAccessors], `params['operator']` via a guarded
/// `DecisionRuleOperator.values.byName`, and compares the field's current
/// [input] value against `params['value']` per that operator. Returns
/// `false` — never throws — for every failure mode: an unrecognized
/// `field`, an unrecognized `operator`, a `null` field value (e.g.
/// `attempt` unset for a context that never populated it), or a numeric
/// operator (`greaterThan`/etc.) applied to a non-`num` value. This
/// defensive-`false` contract is load-bearing: it's what lets a
/// malformed/stale rule (e.g. authored against a field a later app
/// version removed) fail its condition silently rather than crash the
/// walk that's evaluating an otherwise-healthy graph.
bool _evaluateRule(DecisionEvalContext input, Map<String, dynamic> params) {
  final fieldId = params['field'];
  final accessor = fieldId is String ? _fieldAccessors[fieldId] : null;
  if (accessor == null) return false;
  final fieldValue = accessor(input);
  if (fieldValue == null) return false;

  final operatorName = params['operator'];
  DecisionRuleOperator? operator;
  if (operatorName is String) {
    try {
      operator = DecisionRuleOperator.values.byName(operatorName);
    } on ArgumentError {
      operator = null;
    }
  }
  if (operator == null) return false;

  final target = params['value'];
  return switch (operator) {
    DecisionRuleOperator.equals => fieldValue == target,
    DecisionRuleOperator.notEquals => fieldValue != target,
    DecisionRuleOperator.greaterThan =>
      fieldValue is num && target is num && fieldValue > target,
    DecisionRuleOperator.greaterThanOrEqual =>
      fieldValue is num && target is num && fieldValue >= target,
    DecisionRuleOperator.lessThan =>
      fieldValue is num && target is num && fieldValue < target,
    DecisionRuleOperator.lessThanOrEqual =>
      fieldValue is num && target is num && fieldValue <= target,
  };
}

/// Evaluates an `agentJudgment` condition: reads `params['prompt']` (a
/// `String`; defensively `false`/unmatched if missing or not a `String` —
/// the same posture [_evaluateRule] already uses for a malformed
/// rule-builder node), and, if [input] carries both a live
/// `DecisionEvalContext.session` and a `DecisionEvalContext.askAgentJudgment`
/// implementation, awaits it for the answer. `false` (unmatched) for any
/// failure mode — no session, no way to ask, or an ambiguous/`null`
/// answer. The one place in this file that performs real I/O — see
/// `aion-arch/changes/decision-graph-agentjudgment-condition/design.md`
/// §5.
Future<bool> _evaluateAgentJudgment(
  DecisionEvalContext input,
  Map<String, dynamic> params,
) async {
  final prompt = params['prompt'];
  final session = input.session;
  final ask = input.askAgentJudgment;
  if (prompt is! String || session == null || ask == null) return false;
  final answer = await ask(session, prompt);
  return answer ?? false;
}

/// Walks [graph] from its `DecisionGraph.rootNodeId`, evaluating each
/// [DecisionNode] (looked up in [nodesById]) against [input] via
/// [_conditionEvaluators] (or, for an `agentJudgment` node,
/// [_evaluateAgentJudgment]), following `DecisionNode.matchedBranch`/
/// `.unmatchedBranch` until a `DecisionBranch.terminal` is reached.
/// Returns [DecisionOutcome.proceed] immediately if
/// `DecisionGraph.rootNodeId` is `null` (no graph configured) or if the
/// walk ever references a node id missing from [nodesById] (defensive —
/// a dangling reference should never silently block automation that
/// otherwise resolved to `auto`). No longer pure — an `agentJudgment` node
/// performs real I/O via [DecisionEvalContext.askAgentJudgment] (see
/// design.md §5; `providers.md`'s "Decision graphs" section still
/// describes this function as pure and needs correcting when this change
/// is archived). A walk that never reaches an `agentJudgment` node stays
/// exactly as fast as before — the `await` only actually suspends on that
/// one branch. Added for `aion-arch/changes/automation-decision-graphs`.
Future<DecisionOutcome> evaluateDecisionGraph(
  DecisionGraph graph,
  Map<String, DecisionNode> nodesById,
  DecisionEvalContext input,
) async {
  var currentId = graph.rootNodeId;
  if (currentId == null) return DecisionOutcome.proceed;

  while (true) {
    final node = nodesById[currentId];
    if (node == null) return DecisionOutcome.proceed;

    final matched = node.conditionId == agentJudgmentConditionId
        ? await _evaluateAgentJudgment(input, node.conditionParams)
        : (_conditionEvaluators[node.conditionId]?.call(
                input,
                node.conditionParams,
              ) ??
              false);
    final branch = matched ? node.matchedBranch : node.unmatchedBranch;

    switch (branch) {
      case ToNodeBranch(:final nodeId):
        currentId = nodeId;
      case TerminalBranch(:final outcome):
        return outcome;
    }
  }
}
