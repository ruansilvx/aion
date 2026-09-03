// core/automation/decision_field_catalog.dart — rule-builder field/operator vocabulary + node-display helpers (core layer).

import 'package:meta/meta.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_condition_catalog.dart';
import 'package:aion/core/automation/decision_graph_evaluator.dart';
import 'package:aion/core/automation/decision_node.dart';

/// The data type of one [DecisionFieldSpec] — selects which
/// [DecisionRuleOperator]s [operatorsFor] offers and which value control
/// `DecisionNodeForm`'s rule trio renders. Added for
/// `AIO-661`.
enum DecisionFieldType {
  /// A whole-number field, rendered as a digits-only numeric input.
  integer,

  /// A `true`/`false` field, rendered as a two-option picker.
  boolean,
}

/// One field a rule-builder condition can compare against — the
/// vocabulary `DecisionNodeForm`'s "Custom rule" field picker offers.
/// Mirrors [DecisionConditionSpec]'s shape (`id`, `displayName`,
/// `contexts`) plus a [type] selecting its operator/value-control kind.
/// Added for `AIO-661`.
@immutable
class DecisionFieldSpec {
  /// Creates a [DecisionFieldSpec].
  const DecisionFieldSpec({
    required this.id,
    required this.displayName,
    required this.type,
    required this.contexts,
  });

  /// Stable identifier, stored under `DecisionNode.conditionParams['field']`
  /// for a rule-builder node and read back by
  /// `decision_graph_evaluator.dart`'s `_fieldAccessors`.
  final String id;

  /// User-facing label shown in the field picker and (for a rule-builder
  /// node) as [decisionNodeTitle].
  final String displayName;

  /// This field's value type — selects [operatorsFor]'s offered operators
  /// and the value control `DecisionNodeForm` renders.
  final DecisionFieldType type;

  /// Which [AutomationContext] values this field is valid for —
  /// [decisionFieldsFor] filters the full catalog down to this set.
  final List<AutomationContext> contexts;
}

/// The catalog entry exposing `DecisionEvalContext.attempt` — the same
/// signal [attemptExceedsMaxCondition] already reads, now also pickable
/// with any [DecisionRuleOperator] rather than a fixed `>` threshold.
const attemptField = DecisionFieldSpec(
  id: 'attempt',
  displayName: 'Attempt count',
  type: DecisionFieldType.integer,
  contexts: [AutomationContext.codingExecutionRetry],
);

/// The catalog entry exposing `DecisionEvalContext.sessionOverageDetected`
/// — the same signal [sessionOverageDetectedCondition] already reads, now
/// also pickable as `== false` (the fixed catalog condition can only ever
/// match a detected overage, never gate on its absence).
const sessionOverageDetectedField = DecisionFieldSpec(
  id: 'sessionOverageDetected',
  displayName: 'Session budget overage detected',
  type: DecisionFieldType.boolean,
  contexts: [AutomationContext.codingExecution],
);

/// Every field a rule-builder condition can be built from, regardless of
/// context. Exactly the two entries above — see
/// `AIO-661`'s domain task
/// scope note for why this doesn't yet cover every `AutomationContext`.
const List<DecisionFieldSpec> decisionFieldCatalog = [
  attemptField,
  sessionOverageDetectedField,
];

/// The subset of [decisionFieldCatalog] valid for [context] — what
/// `DecisionNodeForm`'s rule-builder field picker offers when editing
/// that context's graph.
List<DecisionFieldSpec> decisionFieldsFor(AutomationContext context) {
  return decisionFieldCatalog
      .where((field) => field.contexts.contains(context))
      .toList();
}

/// A comparison a rule-builder condition can apply between a
/// [DecisionFieldSpec]'s current value and an authored value.
/// [operatorsFor] narrows this to the subset valid for a given
/// [DecisionFieldType]. Added for
/// `AIO-661`.
enum DecisionRuleOperator {
  /// The field's value equals the authored value.
  equals,

  /// The field's value does not equal the authored value.
  notEquals,

  /// The field's value is strictly greater than the authored value.
  /// `int` fields only.
  greaterThan,

  /// The field's value is greater than or equal to the authored value.
  /// `int` fields only.
  greaterThanOrEqual,

  /// The field's value is strictly less than the authored value. `int`
  /// fields only.
  lessThan,

  /// The field's value is less than or equal to the authored value. `int`
  /// fields only.
  lessThanOrEqual,
}

/// The [DecisionRuleOperator] values valid for [type] — an `integer`
/// field offers all six; a `boolean` field offers only `equals`, fixed
/// (its value is picked directly as `true`/`false` via the value control,
/// so `is <value>` alone is already fully expressive — no `notEquals`
/// pair is offered, matching design.md (Component Spec) §1.2: a boolean
/// field's operator picker renders a single, disabled `is` trigger rather
/// than a real choice).
List<DecisionRuleOperator> operatorsFor(DecisionFieldType type) =>
    switch (type) {
      DecisionFieldType.integer => DecisionRuleOperator.values,
      DecisionFieldType.boolean => const [DecisionRuleOperator.equals],
    };

/// The reserved `DecisionNode.conditionId` value marking a rule-builder
/// condition — never collides with a real [decisionConditionCatalog]
/// entry (none of which use this id).
const ruleBuilderConditionId = 'ruleBuilder';

/// Synthesizes the "Custom rule" entry `DecisionNodeForm`'s condition
/// picker appends after [decisionConditionsFor]'s real catalog entries —
/// `null` if [context] has no rule-builder fields at all (nothing to
/// build a rule from). [DecisionConditionSpec.displayName] here is a
/// plain-English fallback (matching every other catalog entry's
/// unlocalized `displayName`); `DecisionNodeForm`'s condition picker
/// overrides this specific row's rendered label with the localized
/// `decisionGraphRuleBuilderLabel` string instead.
DecisionConditionSpec? ruleBuilderConditionSpec(AutomationContext context) {
  if (decisionFieldsFor(context).isEmpty) return null;
  return DecisionConditionSpec(
    id: ruleBuilderConditionId,
    displayName: 'Custom rule',
    contexts: [context],
    parameterSpecs: const [],
  );
}

/// The `conditionParams` a freshly created rule-builder [DecisionNode]
/// for [context] starts with: the first field valid for [context], the
/// first operator valid for that field's type, and that type's zero value
/// (`0` for `integer`, `false` for `boolean`). Mirrors
/// `defaultConditionParams`'s role for the fixed catalog. Returns `{}` if
/// [context] has no rule-builder fields — defensive; the condition picker
/// never offers "Custom rule" in that case, so this is unreachable in
/// practice.
Map<String, dynamic> defaultRuleConditionParams(AutomationContext context) {
  final fields = decisionFieldsFor(context);
  if (fields.isEmpty) return {};
  final field = fields.first;
  final operator = operatorsFor(field.type).first;
  return {
    'field': field.id,
    'operator': operator.name,
    'value': field.type == DecisionFieldType.integer ? 0 : false,
  };
}

/// The fixed set of `AutomationContext` values evaluated from inside a
/// live tool-call handler with an in-flight session — see proposal.md's
/// "Why this only works for 3 of the 8". Not derived from any existing
/// enum/field, since "has a live session at evaluation time" isn't a
/// property any other part of this system currently models — this list
/// is this change's own source of truth for it. Added for
/// `AIO-613`.
const _agentJudgmentEligibleContexts = {
  AutomationContext.ticketCreation,
  AutomationContext.ticketLinking,
  AutomationContext.chatBranching,
};

/// Synthesizes the "Ask the agent" entry `DecisionNodeForm`'s condition
/// picker appends after the rule-builder entry (if any) — `null` if
/// [context] isn't one of the 3 contexts a live session can ever be
/// available for. Added for
/// `AIO-613`.
DecisionConditionSpec? agentJudgmentConditionSpec(AutomationContext context) {
  if (!_agentJudgmentEligibleContexts.contains(context)) return null;
  return DecisionConditionSpec(
    id: agentJudgmentConditionId,
    displayName: 'Ask the agent',
    contexts: [context],
    parameterSpecs: const [],
  );
}

/// The `conditionParams` a freshly created `agentJudgment` [DecisionNode]
/// starts with: an empty, unauthored prompt. Mirrors
/// [defaultRuleConditionParams]'s role for the rule-builder kind. Added
/// for `AIO-613`.
Map<String, dynamic> defaultAgentJudgmentConditionParams(
  AutomationContext context,
) => const {'prompt': ''};

/// Whether [conditionId] is a condition `GraphCanvas`/`DecisionOutlineList`
/// know how to render for [context] — a real [decisionConditionCatalog]
/// entry, [ruleBuilderConditionId], or [agentJudgmentConditionId]. Replaces
/// the bare `decisionConditionSpecById(id) != null` check `GraphCanvas`'s
/// layout used to flag a node `isError`, which (before this) flagged every
/// rule-builder node as "INCOMPLETE" simply for not being in the fixed
/// catalog.
bool isRecognizedConditionId(String conditionId, AutomationContext context) {
  return decisionConditionSpecById(conditionId) != null ||
      conditionId == ruleBuilderConditionId ||
      conditionId == agentJudgmentConditionId;
}

/// [operator]'s short display symbol for [type] — the compact glyph shown
/// in a rule-builder node's parameter chip (e.g. `>`, `≥`, `is`, `is
/// not`). A `boolean` field renders `equals`/`notEquals` as the words
/// `is`/`is not` (there being no `true`/`false`-specific operator pair);
/// every other combination renders the matching arithmetic/equality
/// glyph. Falls back to the `integer` glyph set for any operator a
/// `boolean` field can't actually produce (defensive — never reachable by
/// construction, since [operatorsFor] never offers those operators for a
/// `boolean` field).
String _operatorSymbol(DecisionRuleOperator operator, DecisionFieldType type) {
  if (type == DecisionFieldType.boolean) {
    switch (operator) {
      case DecisionRuleOperator.equals:
        return 'is';
      case DecisionRuleOperator.notEquals:
        return 'is not';
      case DecisionRuleOperator.greaterThan:
      case DecisionRuleOperator.greaterThanOrEqual:
      case DecisionRuleOperator.lessThan:
      case DecisionRuleOperator.lessThanOrEqual:
        break; // Fall through to the shared glyph set below.
    }
  }
  return switch (operator) {
    DecisionRuleOperator.equals => '=',
    DecisionRuleOperator.notEquals => '≠',
    DecisionRuleOperator.greaterThan => '>',
    DecisionRuleOperator.greaterThanOrEqual => '≥',
    DecisionRuleOperator.lessThan => '<',
    DecisionRuleOperator.lessThanOrEqual => '≤',
  };
}

/// [DecisionRuleOperator.values].byName(`name`), or `null` if `name`
/// doesn't match any value — guards the `ArgumentError` `Enum.byName`
/// throws for an unrecognized name, so a malformed/stale
/// `conditionParams['operator']` (e.g. from a future app version's
/// operator this build doesn't know) degrades to "unresolved" rather than
/// crashing the form/canvas/outline render.
DecisionRuleOperator? _parseRuleOperator(Object? raw) {
  if (raw is! String) return null;
  try {
    return DecisionRuleOperator.values.byName(raw);
  } on ArgumentError {
    return null;
  }
}

/// [field.id]'s [DecisionFieldSpec] in [decisionFieldCatalog], or `null`
/// if [fieldId] doesn't match any shipped field.
DecisionFieldSpec? _fieldById(String fieldId) {
  for (final field in decisionFieldCatalog) {
    if (field.id == fieldId) return field;
  }
  return null;
}

/// [node]'s display title: a catalog spec's `displayName` when
/// [node.conditionId] resolves via [decisionConditionSpecById], (for a
/// rule-builder node) the chosen field's `displayName` — read from
/// `node.conditionParams['field']`, looked up in [decisionFieldCatalog] —
/// or (for an `agentJudgment` node) the plain-English fallback `'Ask the
/// agent'`, since there's no catalog/field spec to look up (unlike the
/// rule-builder case). This file is a `core/` file with no
/// Flutter/`AppLocalizations` dependency today, so this fallback is
/// unlocalized — `DecisionNodeForm`'s condition-picker row overrides its
/// own rendered label with the localized
/// `decisionGraphAgentJudgmentLabel` string instead, exactly mirroring
/// how the rule-builder case's picker row is separately overridden by
/// `decisionGraphRuleBuilderLabel`. Falls back to [node.conditionId]
/// itself when nothing resolves (mirrors every call site's former
/// `spec?.displayName ?? node.conditionId` pattern, generalized to also
/// cover the rule-builder and agent-judgment cases). Never throws on a
/// missing/malformed `conditionParams` shape.
String decisionNodeTitle(DecisionNode node) {
  final spec = decisionConditionSpecById(node.conditionId);
  if (spec != null) return spec.displayName;
  if (node.conditionId == ruleBuilderConditionId) {
    final fieldId = node.conditionParams['field'];
    final field = fieldId is String ? _fieldById(fieldId) : null;
    if (field != null) return field.displayName;
  }
  if (node.conditionId == agentJudgmentConditionId) return 'Ask the agent';
  return node.conditionId;
}

/// [node]'s parameter-chip text: a catalog spec's existing
/// `conditionParameterSummary` output when [node.conditionId] resolves
/// via [decisionConditionSpecById], (for a rule-builder node) the
/// operator symbol followed by the value (e.g. `> 3`, `is False`) built
/// from `node.conditionParams`, or (for an `agentJudgment` node) the
/// authored `conditionParams['prompt']` itself, truncated to ~120 chars
/// mirroring `agent_bridge/index.mjs`'s `summarizeToolInput` truncation
/// convention.
/// `null` for a flag-only catalog condition, a rule-builder node whose
/// `conditionParams` is missing/malformed (an unrecognized `field` or
/// `operator`, or a `null` field), or an `agentJudgment` node whose
/// `prompt` is missing, non-`String`, or empty — never throws.
String? decisionNodeSummary(DecisionNode node) {
  final spec = decisionConditionSpecById(node.conditionId);
  if (spec != null) return conditionParameterSummary(spec, node.conditionParams);

  if (node.conditionId == agentJudgmentConditionId) {
    final prompt = node.conditionParams['prompt'];
    if (prompt is! String || prompt.isEmpty) return null;
    return prompt.length > 120 ? '${prompt.substring(0, 120)}…' : prompt;
  }

  if (node.conditionId != ruleBuilderConditionId) return null;

  final params = node.conditionParams;
  final fieldId = params['field'];
  final field = fieldId is String ? _fieldById(fieldId) : null;
  if (field == null) return null;
  final operator = _parseRuleOperator(params['operator']);
  if (operator == null) return null;

  final symbol = _operatorSymbol(operator, field.type);
  final value = params['value'];
  final displayValue = field.type == DecisionFieldType.boolean
      ? (value == true ? 'True' : 'False')
      : value;
  return '$symbol $displayValue';
}
