// core/automation/decision_condition_catalog.dart — DecisionConditionSpec catalog (core layer).

import 'package:meta/meta.dart';

import 'package:aion/core/automation/automation_context.dart';

/// The data type of one [DecisionConditionSpec] parameter. `integer` is
/// the only kind either of this catalog's two shipped conditions needs;
/// more kinds are added here as new conditions are added to
/// [decisionConditionsFor]'s catalog — a catalog entry plus a matching
/// `decision_graph_evaluator.dart` case, no schema change. Added for
/// `aion-arch/changes/automation-decision-graphs`.
enum DecisionConditionParameterType {
  /// A whole-number field, rendered as a digits-only numeric input.
  integer,
}

/// One parameter a [DecisionConditionSpec] accepts, driving
/// `DecisionNodeForm`'s typed parameter field. Added for
/// `aion-arch/changes/automation-decision-graphs`.
@immutable
class DecisionConditionParameterSpec {
  /// Creates a [DecisionConditionParameterSpec].
  const DecisionConditionParameterSpec({
    required this.name,
    required this.type,
    required this.defaultValue,
  });

  /// The key this parameter is stored under in `DecisionNode
  /// .conditionParams`.
  final String name;

  /// This parameter's data type.
  final DecisionConditionParameterType type;

  /// The value a newly-added node of this condition starts with.
  final Object defaultValue;
}

/// Describes one selectable entry in a `DecisionNodeForm` condition
/// picker: its identity ([id], referenced by `DecisionNode.conditionId`),
/// its display copy, which [AutomationContext] values it's valid for, and
/// what parameters it takes (empty for a flag-only condition). Added for
/// `aion-arch/changes/automation-decision-graphs`.
@immutable
class DecisionConditionSpec {
  /// Creates a [DecisionConditionSpec].
  const DecisionConditionSpec({
    required this.id,
    required this.displayName,
    required this.contexts,
    required this.parameterSpecs,
  });

  /// Stable identifier, referenced by `DecisionNode.conditionId` and by
  /// `decision_graph_evaluator.dart`'s condition registry.
  final String id;

  /// User-facing label shown in the condition picker.
  final String displayName;

  /// Which [AutomationContext] values this condition is valid for —
  /// [decisionConditionsFor] filters the full catalog down to this set.
  final List<AutomationContext> contexts;

  /// This condition's parameters, in display order. Empty for a
  /// flag-only condition (the parameter field is hidden entirely).
  final List<DecisionConditionParameterSpec> parameterSpecs;
}

/// The catalog entry reproducing `TicketsCubit
/// ._effectiveCodingExecutionRetryConfidence`'s former hardcoded
/// `attempt > _maxVerifyRetries` check as data — the seeded baseline
/// `DecisionNode` for [AutomationContext.codingExecutionRetry]'s graph
/// uses this condition with `maxAttempts: 2`, matching that removed
/// literal's `_maxVerifyRetries` value exactly.
const attemptExceedsMaxCondition = DecisionConditionSpec(
  id: 'attemptExceedsMax',
  displayName: 'Attempt count exceeds',
  contexts: [AutomationContext.codingExecutionRetry],
  parameterSpecs: [
    DecisionConditionParameterSpec(
      name: 'maxAttempts',
      type: DecisionConditionParameterType.integer,
      defaultValue: 3,
    ),
  ],
);

/// The catalog entry reproducing `TicketsCubit
/// ._effectiveCodingExecutionConfidence`'s former hardcoded
/// `_overageDetectedThisSession` check as data — the seeded baseline
/// `DecisionNode` for [AutomationContext.codingExecution]'s graph uses
/// this condition. Takes no parameter — a session either has detected a
/// budget overage or it hasn't.
const sessionOverageDetectedCondition = DecisionConditionSpec(
  id: 'sessionOverageDetected',
  displayName: 'Session budget overage detected',
  contexts: [AutomationContext.codingExecution],
  parameterSpecs: [],
);

/// Every condition this proposal ships, regardless of context. Adding a
/// condition for another [AutomationContext] later is additive: append a
/// spec here plus a matching case in
/// `decision_graph_evaluator.dart`'s registry — no schema change.
const List<DecisionConditionSpec> decisionConditionCatalog = [
  attemptExceedsMaxCondition,
  sessionOverageDetectedCondition,
];

/// The subset of [decisionConditionCatalog] valid for [context] — what a
/// `DecisionNodeForm` condition picker offers when editing that context's
/// graph.
List<DecisionConditionSpec> decisionConditionsFor(AutomationContext context) {
  return decisionConditionCatalog
      .where((spec) => spec.contexts.contains(context))
      .toList();
}

/// [spec]'s parameters seeded to their [DecisionConditionParameterSpec
/// .defaultValue] — the `conditionParams` a freshly created [DecisionNode]
/// for [spec] starts with, whether authored as a graph's root or chained
/// onto an existing node's branch via `DecisionNodeForm`'s "continue to
/// condition" mode. Added for
/// `aion-arch/changes/automation-decision-graphs` (`/verify` fix pass).
Map<String, dynamic> defaultConditionParams(DecisionConditionSpec spec) => {
  for (final param in spec.parameterSpecs) param.name: param.defaultValue,
};

/// Looks up [decisionConditionCatalog] by [conditionId], or `null` if
/// [conditionId] doesn't match any shipped condition — a small shared
/// lookup so `DecisionNodeForm`/`DecisionOutlineList`/
/// `DecisionGraphEditorScreen` don't each repeat their own
/// `decisionConditionCatalog.where(...).firstOrNull`. Added for
/// `aion-arch/changes/automation-decision-graphs` (`/verify` fix pass).
DecisionConditionSpec? decisionConditionSpecById(String conditionId) {
  for (final spec in decisionConditionCatalog) {
    if (spec.id == conditionId) return spec;
  }
  return null;
}
