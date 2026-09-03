// presentation/widgets/decision_node_form.dart — DecisionNodeForm condition-editing form (presentation layer).

import 'dart:async' show unawaited;

import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        KeyDownEvent,
        LengthLimitingTextInputFormatter,
        LogicalKeyboardKey,
        TextInputType;
import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// Localized display label for [outcome] — module-private since
/// [DecisionNodeForm]/`DecisionOutlineList` are its only consumers.
String decisionOutcomeLabel(BuildContext context, DecisionOutcome outcome) =>
    switch (outcome) {
      DecisionOutcome.proceed => context.l10n.decisionGraphOutcomeProceedLabel,
      DecisionOutcome.gated => context.l10n.decisionGraphOutcomeGatedLabel,
      DecisionOutcome.decline => context.l10n.decisionGraphOutcomeDeclineLabel,
      DecisionOutcome.modelJudgment =>
        context.l10n.decisionGraphOutcomeModelJudgmentLabel,
    };

/// The color token associated with [outcome] — `success`/`warning`/
/// `danger`/`secondary` per design.md §0.1's outcome color map.
Color decisionOutcomeColor(AionColors c, DecisionOutcome outcome) =>
    switch (outcome) {
      DecisionOutcome.proceed => c.success,
      DecisionOutcome.gated => c.warning,
      DecisionOutcome.decline => c.danger,
      DecisionOutcome.modelJudgment => c.secondary,
    };

/// [context]'s full condition catalog for `DecisionNodeForm`'s picker(s):
/// [decisionConditionsFor]'s real catalog entries, plus the synthetic "Custom
/// rule" entry from [ruleBuilderConditionSpec] when [context] has a non-empty
/// rule-builder field vocabulary. Shared by
/// [_DecisionNodeFormState.initState]/`.build` and (via `_BranchSection`'s own
/// `catalog` parameter) the chained-branch picker, so a branch can chain into
/// a fresh rule-builder condition exactly like it can chain into a fixed
/// catalog one. Added for `AIO-661`.
List<DecisionConditionSpec> _catalogFor(AutomationContext context) => [
  ...decisionConditionsFor(context),
  ?ruleBuilderConditionSpec(context),
  ?agentJudgmentConditionSpec(context),
];

/// [operator]'s full-word label for [type] — shown in the rule-builder
/// operator picker's trigger and menu rows (e.g. `Is greater than`, `Equals`,
/// `Is` for a `boolean` field's `equals`). Distinct from
/// `decision_field_catalog.dart`'s own operator-symbol formatting (used
/// internally by `decisionNodeSummary`'s compact chip text, e.g. `>`, `is`) —
/// that helper lives in the domain layer and can't depend on this
/// presentation-layer one, so the two are separate, deliberately consistent
/// mappings rather than one shared function. Per `AIO-661`'s Component Spec
/// §1.2 Operator catalog. Added for `AIO-661`.
String _ruleOperatorLabel(
  DecisionRuleOperator operator,
  DecisionFieldType type,
) {
  if (type == DecisionFieldType.boolean) {
    return switch (operator) {
      DecisionRuleOperator.equals => 'Is',
      DecisionRuleOperator.notEquals => 'Is not',
      DecisionRuleOperator.greaterThan ||
      DecisionRuleOperator.greaterThanOrEqual ||
      DecisionRuleOperator.lessThan ||
      DecisionRuleOperator.lessThanOrEqual => 'Is',
    };
  }
  return switch (operator) {
    DecisionRuleOperator.equals => 'Equals',
    DecisionRuleOperator.notEquals => 'Is not',
    DecisionRuleOperator.greaterThan => 'Is greater than',
    DecisionRuleOperator.greaterThanOrEqual => 'Is at least',
    DecisionRuleOperator.lessThan => 'Is less than',
    DecisionRuleOperator.lessThanOrEqual => 'Is at most',
  };
}

/// [branch]'s chained child's condition display name, resolved from
/// [nodesById] — feeds [DecisionNodeForm]'s `...ChildConditionLabel`
/// parameters. `null` for a terminal branch, or for a [DecisionBranch .toNode]
/// whose target is missing from [nodesById] (a dangling reference — the same
/// defensive treatment `decision_graph_evaluator.dart` gives it at evaluation
/// time). Shared by `DecisionOutlineList` and `DecisionGraphEditorScreen`'s
/// canvas pane so the two panes can't resolve this differently. Added for
/// `AIO-181` (`/verify` fix pass).
String? chainedChildConditionLabel(
  DecisionBranch branch,
  Map<String, DecisionNode> nodesById,
) {
  if (branch is! ToNodeBranch) return null;
  final child = nodesById[branch.nodeId];
  if (child == null) return null;
  return decisionNodeTitle(child);
}

/// Whether a [DecisionNodeForm] branch (matched or unmatched) currently
/// terminates in an outcome, or continues the strict tree into another
/// condition — the form-local mirror of [DecisionBranch]'s two variants,
/// driving the two-segment control design.md §3.3/§3.4 specifies. Added for
/// `AIO-181` (`/verify` fix pass — this mode was previously unreachable from
/// the form, capping every graph at one node).
enum DecisionBranchMode {
  /// The branch resolves to a terminal [DecisionOutcome] — design.md's
  /// "End here" segment.
  endHere,

  /// The branch continues into another [DecisionNode] — design.md's
  /// "Continue to condition" segment.
  continueToCondition,
}

/// One condition-editing form: a condition picker (over
/// `decisionConditionsFor(automationContext)`), that condition's typed
/// parameter fields, and a matched/unmatched branch picker pair — each
/// branch independently either ends in a terminal [DecisionOutcome] or
/// continues to another condition (a chained child [DecisionNode],
/// created via [onCreateChainedChild] the first time a branch switches
/// into [DecisionBranchMode.continueToCondition]). Shared by both
/// `DecisionOutlineList`'s inline expand-in-place row and `GraphCanvas`'s
/// popover mount (via [DecisionNodeForm.showAsPopover]) — one widget, so
/// the two panes can never render divergent editing UI for the same
/// node.
///
/// Editing an *existing* chained branch's own condition/parameters isn't done
/// from here — once a branch continues to a child node, that child renders as
/// its own row/canvas node (see `DecisionOutlineList`'s recursive rendering)
/// with its own [DecisionNodeForm] mount; this form only ever creates the
/// chain or detaches it (switching a [DecisionBranchMode.continueToCondition]
/// branch back to [DecisionBranchMode.endHere] leaves the child node orphaned
/// rather than deleting it, the same dangling-reference tolerance
/// `decision_graph_evaluator.dart` and `DecisionGraphConfigCubit .deleteNode`
/// already document). Added for `AIO-181`; see its linked Documentation page,
/// §3.
class DecisionNodeForm extends StatefulWidget {
  /// Creates a [DecisionNodeForm]. Pass [initialConditionId]/
  /// [initialConditionParams]/[initialMatchedBranch]/
  /// [initialUnmatchedBranch] when editing an existing node; omit them
  /// (all default to a not-yet-chosen condition and
  /// terminal `gated`/`proceed`) when authoring a brand-new one.
  /// [matchedChildConditionLabel]/[unmatchedChildConditionLabel] must be
  /// supplied (the chained child's condition display name) whenever the
  /// corresponding initial branch is a [DecisionBranch.toNode] — the form
  /// has no repository access of its own to resolve one. [onDelete] is
  /// omitted entirely for a not-yet-saved new node — see its linked
  /// Documentation page, §3.5.
  /// [forceMatchedContinue]/[forceUnmatchedContinue] start that branch's
  /// mode in [DecisionBranchMode.continueToCondition] even though
  /// [initialMatchedBranch]/[initialUnmatchedBranch] is still a
  /// [DecisionBranch.terminal] — used by `DecisionOutlineList`'s
  /// per-branch "+ Add condition" shortcut (design.md §2.3) so tapping it
  /// opens this form with that branch already on the "continue to
  /// condition" segment, rather than requiring the user to find and
  /// toggle it themselves. [descendantCount] is the number of nodes
  /// [onDelete] would cascade-delete along with this one — the form has
  /// no repository access of its own to compute it, so callers pass it
  /// via `descendantIdsOf` (`DecisionGraphConfigCubit`'s own helper,
  /// `.length - 1` to exclude this node itself).
  const DecisionNodeForm({
    super.key,
    required this.automationContext,
    this.initialConditionId,
    this.initialConditionParams = const {},
    this.initialMatchedBranch = const DecisionBranch.terminal(
      DecisionOutcome.gated,
    ),
    this.initialUnmatchedBranch = const DecisionBranch.terminal(
      DecisionOutcome.proceed,
    ),
    this.matchedChildConditionLabel,
    this.unmatchedChildConditionLabel,
    this.forceMatchedContinue = false,
    this.forceUnmatchedContinue = false,
    this.descendantCount = 0,
    required this.onSave,
    required this.onCreateChainedChild,
    required this.onCancel,
    this.onDelete,
  });

  /// Which [AutomationContext] this form's condition picker is scoped to.
  final AutomationContext automationContext;

  /// The condition id to preselect, or `null` for "no condition chosen
  /// yet."
  final String? initialConditionId;

  /// The parameter values to preseed the form with.
  final Map<String, dynamic> initialConditionParams;

  /// The matched branch's preselected shape — terminal or chained.
  final DecisionBranch initialMatchedBranch;

  /// The unmatched branch's preselected shape — terminal or chained.
  final DecisionBranch initialUnmatchedBranch;

  /// Display name of the matched branch's existing chained child's
  /// condition, when [initialMatchedBranch] is a [DecisionBranch.toNode].
  /// Ignored otherwise.
  final String? matchedChildConditionLabel;

  /// Same as [matchedChildConditionLabel], for the unmatched branch.
  final String? unmatchedChildConditionLabel;

  /// Starts the matched branch's mode in
  /// [DecisionBranchMode.continueToCondition] regardless of
  /// [initialMatchedBranch] — see this constructor's own dartdoc.
  final bool forceMatchedContinue;

  /// Same as [forceMatchedContinue], for the unmatched branch.
  final bool forceUnmatchedContinue;

  /// The number of descendant nodes [onDelete] would cascade-delete along
  /// with this one — shown in the delete-confirm dialog per design.md
  /// §3.5 ("Delete this condition and its 2 descendants?"). `0` for a
  /// leaf node (or a not-yet-saved new node, which hides [onDelete]
  /// entirely).
  final int descendantCount;

  /// Called with the form's committed values when Save is pressed (only
  /// enabled once a condition is chosen, every required parameter is
  /// valid, and every branch in [DecisionBranchMode.continueToCondition]
  /// mode has picked a condition to chain to).
  final void Function({
    required String conditionId,
    required Map<String, dynamic> conditionParams,
    required DecisionBranch matchedBranch,
    required DecisionBranch unmatchedBranch,
  })
  onSave;

  /// Called when a branch is switched into
  /// [DecisionBranchMode.continueToCondition] for the first time (no
  /// existing chained child yet) and a chaining condition is picked —
  /// must create a fresh [DecisionNode] for [conditionId] (parameters
  /// seeded via `defaultConditionParams`) and return its id, or `null` if
  /// the write was rejected (mirrors `DecisionGraphConfigCubit
  /// .createNode`'s own return contract). Never called for a branch that
  /// already has a chained child — that id is reused as-is.
  final Future<String?> Function(String conditionId) onCreateChainedChild;

  /// Called when Cancel/Escape/click-outside dismisses the form without
  /// saving.
  final VoidCallback onCancel;

  /// Called when Delete is pressed. `null` hides the Delete action
  /// entirely — used for a not-yet-saved new node, which has nothing to
  /// delete.
  final VoidCallback? onDelete;

  /// Mounts a [DecisionNodeForm] as a popover: an [OverlayEntry] +
  /// [CompositedTransformFollower] anchored below [link]'s target,
  /// dismissed on outside-tap or Escape. Used by `GraphCanvas`'s
  /// node-tap-to-edit interaction — the canvas mount described in
  /// design.md §3's "popover mount". [onSave]/[onCreateChainedChild]/
  /// [onDelete] must already be bound to the caller's
  /// `DecisionGraphConfigCubit` *before* this is called (e.g. via
  /// `context.read` in the tap handler that invokes this) — the
  /// [OverlayEntry] this inserts renders from the app's root `Overlay`,
  /// outside the route-scoped `BlocProvider`'s subtree, so it cannot
  /// safely `context.read` a cubit itself.
  static void showAsPopover(
    BuildContext context, {
    required LayerLink link,
    required AutomationContext automationContext,
    String? initialConditionId,
    Map<String, dynamic> initialConditionParams = const {},
    DecisionBranch initialMatchedBranch = const DecisionBranch.terminal(
      DecisionOutcome.gated,
    ),
    DecisionBranch initialUnmatchedBranch = const DecisionBranch.terminal(
      DecisionOutcome.proceed,
    ),
    String? matchedChildConditionLabel,
    String? unmatchedChildConditionLabel,
    int descendantCount = 0,
    required void Function({
      required String conditionId,
      required Map<String, dynamic> conditionParams,
      required DecisionBranch matchedBranch,
      required DecisionBranch unmatchedBranch,
    })
    onSave,
    required Future<String?> Function(String conditionId) onCreateChainedChild,
    VoidCallback? onDelete,
  }) {
    late OverlayEntry entry;
    void dismiss() => entry.remove();
    entry = OverlayEntry(
      builder: (context) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            dismiss();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: dismiss,
              ),
            ),
            CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              offset: const Offset(12, 0),
              targetAnchor: Alignment.centerRight,
              followerAnchor: Alignment.centerLeft,
              child: _PopoverChrome(
                child: DecisionNodeForm(
                  automationContext: automationContext,
                  initialConditionId: initialConditionId,
                  initialConditionParams: initialConditionParams,
                  initialMatchedBranch: initialMatchedBranch,
                  initialUnmatchedBranch: initialUnmatchedBranch,
                  matchedChildConditionLabel: matchedChildConditionLabel,
                  unmatchedChildConditionLabel: unmatchedChildConditionLabel,
                  descendantCount: descendantCount,
                  onSave:
                      ({
                        required conditionId,
                        required conditionParams,
                        required matchedBranch,
                        required unmatchedBranch,
                      }) {
                        onSave(
                          conditionId: conditionId,
                          conditionParams: conditionParams,
                          matchedBranch: matchedBranch,
                          unmatchedBranch: unmatchedBranch,
                        );
                        dismiss();
                      },
                  onCreateChainedChild: onCreateChainedChild,
                  onCancel: dismiss,
                  onDelete: onDelete == null
                      ? null
                      : () {
                          onDelete();
                          dismiss();
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(entry);
  }

  @override
  State<DecisionNodeForm> createState() => _DecisionNodeFormState();
}

class _DecisionNodeFormState extends State<DecisionNodeForm> {
  DecisionConditionSpec? _condition;
  final Map<String, TextEditingController> _paramControllers = {};

  /// The rule trio's local state — mirrors `_condition`'s own pattern,
  /// populated only while `_condition?.id == ruleBuilderConditionId`. See
  /// [_seedRuleState]. Added for `AIO-661`.
  DecisionFieldSpec? _ruleField;
  DecisionRuleOperator? _ruleOperator;
  TextEditingController? _ruleIntValueController;
  bool _ruleBoolValue = false;

  /// The `agentJudgment` prompt field's local state — mirrors [_ruleField]'s
  /// own pattern, populated only while
  /// `_condition?.id == agentJudgmentConditionId`. See
  /// [_seedAgentJudgmentState]. A save attempt (or a blur while empty) while
  /// this field is empty renders it in the error state per design.md
  /// §2.4/§2.5.5 — tracked here rather than derived, since "untouched" and
  /// "touched-then-emptied" render differently (§2.4's table). Added for
  /// `AIO-613`.
  TextEditingController? _agentPromptController;
  bool _agentPromptShowError = false;

  /// Owns focus for [_agentPromptController]'s field so
  /// [_seedAgentJudgmentState] can attach [_onAgentPromptFocusChange] — the
  /// mechanism behind design.md §2.4's "focus + blur while empty" error
  /// trigger, alongside [_save]'s own save-attempt trigger. Added for
  /// `AIO-613`.
  FocusNode? _agentPromptFocusNode;

  late DecisionBranchMode _matchedMode;
  late DecisionOutcome _matchedOutcome;
  String? _matchedExistingChildId;
  DecisionConditionSpec? _matchedChainCondition;

  late DecisionBranchMode _unmatchedMode;
  late DecisionOutcome _unmatchedOutcome;
  String? _unmatchedExistingChildId;
  DecisionConditionSpec? _unmatchedChainCondition;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final catalog = _catalogFor(widget.automationContext);
    _condition = catalog
        .where((spec) => spec.id == widget.initialConditionId)
        .firstOrNull;
    _seedParamControllers();
    _seedRuleState(widget.initialConditionParams);
    _seedAgentJudgmentState(widget.initialConditionParams);

    switch (widget.initialMatchedBranch) {
      case TerminalBranch(:final outcome):
        _matchedMode = widget.forceMatchedContinue
            ? DecisionBranchMode.continueToCondition
            : DecisionBranchMode.endHere;
        _matchedOutcome = outcome;
      case ToNodeBranch(:final nodeId):
        _matchedMode = DecisionBranchMode.continueToCondition;
        _matchedOutcome = DecisionOutcome.gated;
        _matchedExistingChildId = nodeId;
    }
    switch (widget.initialUnmatchedBranch) {
      case TerminalBranch(:final outcome):
        _unmatchedMode = widget.forceUnmatchedContinue
            ? DecisionBranchMode.continueToCondition
            : DecisionBranchMode.endHere;
        _unmatchedOutcome = outcome;
      case ToNodeBranch(:final nodeId):
        _unmatchedMode = DecisionBranchMode.continueToCondition;
        _unmatchedOutcome = DecisionOutcome.proceed;
        _unmatchedExistingChildId = nodeId;
    }
  }

  @override
  void dispose() {
    for (final controller in _paramControllers.values) {
      controller.dispose();
    }
    _ruleIntValueController?.dispose();
    _agentPromptController?.dispose();
    _agentPromptFocusNode?.dispose();
    super.dispose();
  }

  /// (Re)builds [_paramControllers] for [_condition]'s current
  /// `parameterSpecs`, disposing whatever controllers existed before.
  /// Each new controller gets [_onParamChanged] as a listener — without
  /// it, typing into a parameter field never rebuilds this form (a
  /// `TextEditingController`'s own listeners only drive the `TextField`'s
  /// own internal redraw, not an ancestor's), so `_isValid`/Save's
  /// enabled state and the field's `isError` highlight would silently go
  /// stale until some unrelated state change (e.g. switching the
  /// condition) happened to force a rebuild. Fixed in `/verify` fix
  /// pass 2 — found via this file's first widget test.
  void _seedParamControllers() {
    for (final controller in _paramControllers.values) {
      controller.dispose();
    }
    _paramControllers.clear();
    final condition = _condition;
    if (condition == null) return;
    for (final spec in condition.parameterSpecs) {
      final initial =
          widget.initialConditionParams[spec.name] ?? spec.defaultValue;
      _paramControllers[spec.name] = TextEditingController(
        text: initial.toString(),
      )..addListener(_onParamChanged);
    }
  }

  /// Rebuilds this form so `_isValid`/Save's enabled state and each
  /// parameter field's `isError` highlight reflect the just-typed text —
  /// see [_seedParamControllers]'s own dartdoc for why this is needed at
  /// all.
  void _onParamChanged() {
    if (mounted) setState(() {});
  }

  /// (Re)builds the rule trio's local state (`_ruleField`/`_ruleOperator`/
  /// `_ruleIntValueController`/`_ruleBoolValue`) from [params], disposing
  /// whatever integer-value controller existed before — mirrors
  /// [_seedParamControllers]'s own pattern, for the rule-builder condition
  /// instead of a catalog condition's fixed parameters. Called from
  /// [initState] with [DecisionNodeForm.initialConditionParams] (editing an
  /// existing node) and from the condition picker's `onSelected` handler with
  /// `defaultRuleConditionParams` (freshly picking "Custom rule"). Clears
  /// every rule field to `null` when [_condition] isn't the rule-builder
  /// condition — the trio isn't rendered in that case, but keeping stale state
  /// around would let a leftover `_ruleField` leak into a later save. Never
  /// throws on a missing/malformed [params] shape (an unrecognized
  /// `field`/`operator` falls back to the first valid option, matching this
  /// context's own rule-builder field/ operator vocabulary). Added for
  /// `AIO-661`.
  void _seedRuleState(Map<String, dynamic> params) {
    _ruleIntValueController?.dispose();
    _ruleIntValueController = null;
    final condition = _condition;
    if (condition == null || condition.id != ruleBuilderConditionId) {
      _ruleField = null;
      _ruleOperator = null;
      return;
    }

    final fields = decisionFieldsFor(widget.automationContext);
    final fieldId = params['field'];
    final field =
        (fieldId is String
            ? fields.where((f) => f.id == fieldId).firstOrNull
            : null) ??
        fields.firstOrNull;
    _ruleField = field;
    if (field == null) {
      _ruleOperator = null;
      return;
    }

    final operators = operatorsFor(field.type);
    final operatorName = params['operator'];
    final operator = operatorName is String
        ? operators.where((o) => o.name == operatorName).firstOrNull
        : null;
    _ruleOperator = operator ?? operators.first;

    if (field.type == DecisionFieldType.integer) {
      final value = params['value'];
      _ruleIntValueController = TextEditingController(
        text: (value is num ? value.toInt() : 0).toString(),
      )..addListener(_onParamChanged);
    } else {
      _ruleBoolValue = params['value'] == true;
    }
  }

  /// (Re)builds the `agentJudgment` prompt field's local state
  /// (`_agentPromptController`/`_agentPromptFocusNode`/
  /// `_agentPromptShowError`) from [params], disposing whatever
  /// controller/focus node existed before — mirrors [_seedRuleState]'s own
  /// pattern, for the `agentJudgment` condition instead of the rule-builder
  /// trio. Called from [initState] with
  /// [DecisionNodeForm.initialConditionParams] (editing an existing node) and
  /// from the condition picker's `onSelected` handler with `{'prompt': ''}`
  /// (freshly picking "Ask the agent"). Leaves [_agentPromptController] `null`
  /// when [_condition] isn't the `agentJudgment` condition — the field isn't
  /// rendered in that case, but keeping a stale controller around would leak
  /// into a later save. Never throws on a missing/malformed `params` shape.
  /// Added for `AIO-613`.
  void _seedAgentJudgmentState(Map<String, dynamic> params) {
    _agentPromptController?.dispose();
    _agentPromptController = null;
    _agentPromptFocusNode?.dispose();
    _agentPromptFocusNode = null;
    _agentPromptShowError = false;
    final condition = _condition;
    if (condition == null || condition.id != agentJudgmentConditionId) return;

    final prompt = params['prompt'];
    _agentPromptController = TextEditingController(
      text: prompt is String ? prompt : '',
    )..addListener(_onParamChanged);
    _agentPromptFocusNode = FocusNode()
      ..addListener(_onAgentPromptFocusChange);
  }

  /// Design.md §2.4's "focus + blur while empty" error trigger — the
  /// counterpart to [_save]'s save-attempt trigger. Fires the error state the
  /// moment the field loses focus while still empty; does nothing on gaining
  /// focus (an untouched, unfocused field is never itself an error — §2.4's
  /// "before any interaction" row) and does nothing once
  /// [_agentPromptShowError] is already `true` (avoids a redundant rebuild).
  /// Added for `AIO-613`.
  void _onAgentPromptFocusChange() {
    final focusNode = _agentPromptFocusNode;
    if (focusNode == null || focusNode.hasFocus || _agentPromptShowError) {
      return;
    }
    if ((_agentPromptController?.text.trim() ?? '').isEmpty) {
      setState(() => _agentPromptShowError = true);
    }
  }

  /// A branch in [DecisionBranchMode.continueToCondition] is valid once
  /// it either already has a chained child, or a chaining condition has
  /// been picked for a brand-new chain — mirrors [_save]'s own
  /// resolution logic.
  bool _branchValid({
    required DecisionBranchMode mode,
    required String? existingChildId,
    required DecisionConditionSpec? chainCondition,
  }) => switch (mode) {
    DecisionBranchMode.endHere => true,
    DecisionBranchMode.continueToCondition =>
      existingChildId != null || chainCondition != null,
  };

  bool get _isValid {
    final condition = _condition;
    if (condition == null) return false;
    if (condition.id == ruleBuilderConditionId) {
      final field = _ruleField;
      if (field == null || _ruleOperator == null) return false;
      if (field.type == DecisionFieldType.integer) {
        final text = _ruleIntValueController?.text.trim() ?? '';
        if (int.tryParse(text) == null) return false;
      }
    } else if (condition.id == agentJudgmentConditionId) {
      if ((_agentPromptController?.text.trim() ?? '').isEmpty) return false;
    } else {
      for (final spec in condition.parameterSpecs) {
        final text = _paramControllers[spec.name]?.text.trim() ?? '';
        if (int.tryParse(text) == null) return false;
      }
    }
    return _branchValid(
          mode: _matchedMode,
          existingChildId: _matchedExistingChildId,
          chainCondition: _matchedChainCondition,
        ) &&
        _branchValid(
          mode: _unmatchedMode,
          existingChildId: _unmatchedExistingChildId,
          chainCondition: _unmatchedChainCondition,
        );
  }

  /// Resolves one branch to its committed [DecisionBranch], creating a
  /// fresh chained child via [DecisionNodeForm.onCreateChainedChild] the
  /// first time a branch enters [DecisionBranchMode.continueToCondition]
  /// (an existing chained child's id is reused untouched). Returns `null`
  /// if resolution isn't possible (invalid state, or child creation was
  /// rejected) — the caller aborts the whole save in that case.
  Future<DecisionBranch?> _resolveBranch({
    required DecisionBranchMode mode,
    required DecisionOutcome outcome,
    required String? existingChildId,
    required DecisionConditionSpec? chainCondition,
  }) async {
    switch (mode) {
      case DecisionBranchMode.endHere:
        return DecisionBranch.terminal(outcome);
      case DecisionBranchMode.continueToCondition:
        if (existingChildId != null) {
          return DecisionBranch.toNode(existingChildId);
        }
        final condition = chainCondition;
        if (condition == null) return null;
        final childId = await widget.onCreateChainedChild(condition.id);
        return childId == null ? null : DecisionBranch.toNode(childId);
    }
  }

  Future<void> _save() async {
    final condition = _condition;
    if (condition == null) return;
    if (!_isValid) {
      // An empty prompt is the one validity failure this form surfaces
      // inline (§2.4/§2.5.5) rather than just leaving Save disabled —
      // every other invalid state here has no dedicated error copy of its
      // own.
      if (condition.id == agentJudgmentConditionId) {
        setState(() => _agentPromptShowError = true);
      }
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    final params = condition.id == ruleBuilderConditionId
        ? <String, dynamic>{
            'field': _ruleField!.id,
            'operator': _ruleOperator!.name,
            'value': _ruleField!.type == DecisionFieldType.integer
                ? int.parse(_ruleIntValueController!.text.trim())
                : _ruleBoolValue,
          }
        : condition.id == agentJudgmentConditionId
        ? <String, dynamic>{'prompt': _agentPromptController!.text.trim()}
        : <String, dynamic>{
            for (final spec in condition.parameterSpecs)
              spec.name: int.parse(_paramControllers[spec.name]!.text.trim()),
          };
    final matchedBranch = await _resolveBranch(
      mode: _matchedMode,
      outcome: _matchedOutcome,
      existingChildId: _matchedExistingChildId,
      chainCondition: _matchedChainCondition,
    );
    final unmatchedBranch = await _resolveBranch(
      mode: _unmatchedMode,
      outcome: _unmatchedOutcome,
      existingChildId: _unmatchedExistingChildId,
      chainCondition: _unmatchedChainCondition,
    );
    if (!mounted) return;
    if (matchedBranch == null || unmatchedBranch == null) {
      setState(() => _saving = false);
      return;
    }
    widget.onSave(
      conditionId: condition.id,
      conditionParams: params,
      matchedBranch: matchedBranch,
      unmatchedBranch: unmatchedBranch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final catalog = _catalogFor(widget.automationContext);

    return Padding(
      padding: const EdgeInsets.all(AionSpacing.sp16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.decisionGraphConditionPickerLabel,
            style: AionText.label.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: 7),
          _ConditionPicker(
            items: catalog,
            value: _condition,
            onSelected: (spec) => setState(() {
              _condition = spec;
              _seedParamControllers();
              _seedRuleState(
                spec.id == ruleBuilderConditionId
                    ? defaultRuleConditionParams(widget.automationContext)
                    : const {},
              );
              _seedAgentJudgmentState(
                spec.id == agentJudgmentConditionId
                    ? defaultAgentJudgmentConditionParams(
                        widget.automationContext,
                      )
                    : const {},
              );
            }),
          ),
          if (_condition != null)
            if (_condition!.id == ruleBuilderConditionId) ...[
              const SizedBox(height: AionSpacing.sp16),
              _buildRuleTrio(context, c),
            ] else if (_condition!.id == agentJudgmentConditionId) ...[
              const SizedBox(height: AionSpacing.sp16),
              _buildAgentPromptField(context, c),
            ] else
              for (final spec in _condition!.parameterSpecs) ...[
                const SizedBox(height: AionSpacing.sp16),
                Text(
                  context.l10n.decisionGraphParameterLabel,
                  style: AionText.label.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: 7),
                SizedBox(
                  width: 132,
                  child: AppTextField(
                    controller: _paramControllers[spec.name]!,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    isError:
                        int.tryParse(
                          _paramControllers[spec.name]!.text.trim(),
                        ) ==
                        null,
                  ),
                ),
              ],
          const SizedBox(height: AionSpacing.sp16),
          _BranchSection(
            label: context.l10n.decisionGraphMatchedLabel,
            dotColor: c.primary,
            chainEyebrow: context.l10n.decisionGraphThenCheck,
            mode: _matchedMode,
            onModeChanged: (m) => setState(() => _matchedMode = m),
            outcome: _matchedOutcome,
            onOutcomeSelected: (o) => setState(() => _matchedOutcome = o),
            catalog: catalog,
            existingChildConditionLabel: widget.matchedChildConditionLabel,
            chainCondition: _matchedChainCondition,
            onChainConditionSelected: (spec) =>
                setState(() => _matchedChainCondition = spec),
          ),
          const SizedBox(height: AionSpacing.sp16),
          _BranchSection(
            label: context.l10n.decisionGraphUnmatchedLabel,
            dotColor: c.borderStrong,
            chainEyebrow: context.l10n.decisionGraphOtherwiseCheck,
            mode: _unmatchedMode,
            onModeChanged: (m) => setState(() => _unmatchedMode = m),
            outcome: _unmatchedOutcome,
            onOutcomeSelected: (o) => setState(() => _unmatchedOutcome = o),
            catalog: catalog,
            existingChildConditionLabel: widget.unmatchedChildConditionLabel,
            chainCondition: _unmatchedChainCondition,
            onChainConditionSelected: (spec) =>
                setState(() => _unmatchedChainCondition = spec),
          ),
          const SizedBox(height: AionSpacing.sp16),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border, width: 1)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: AionSpacing.sp16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.onDelete != null)
                    AppButton(
                      label: context.l10n.decisionGraphDeleteButton,
                      variant: AppButtonVariant.destructive,
                      onPressed: () async {
                        final descendantCount = widget.descendantCount;
                        final confirmed = await showAppConfirmDialog(
                          context,
                          title: descendantCount > 0
                              ? context.l10n
                                    .decisionGraphDeleteConfirmTitleWithDescendants(
                                      descendantCount,
                                    )
                              : context.l10n.decisionGraphDeleteConfirmTitle,
                          message:
                              context.l10n.decisionGraphDeleteConfirmMessage,
                          confirmLabel: context.l10n.decisionGraphDeleteButton,
                          tone: ConfirmDialogTone.destructive,
                        );
                        if (confirmed) widget.onDelete!();
                      },
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: context.l10n.commonCancel,
                        variant: AppButtonVariant.ghost,
                        onPressed: widget.onCancel,
                      ),
                      const SizedBox(width: AionSpacing.sp8),
                      AppButton(
                        label: context.l10n.commonSave,
                        onPressed: _isValid && !_saving
                            ? () => unawaited(_save())
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The field/operator/value trio rendered in place of the generic
  /// per-catalog-parameter loop when
  /// `_condition?.id == ruleBuilderConditionId` — [decisionFieldsFor]'s field
  /// picker, an operator picker over `operatorsFor(field.type)`, and a value
  /// control (digits-only [AppTextField] for `integer`, a `True`/`False`
  /// picker for `boolean`). Per `AIO-661` §3. Added for `AIO-661`.
  Widget _buildRuleTrio(BuildContext context, AionColors c) {
    final fields = decisionFieldsFor(widget.automationContext);
    final field = _ruleField;
    final operators = field == null
        ? const <DecisionRuleOperator>[]
        : operatorsFor(field.type);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.decisionGraphRuleFieldLabel,
          style: AionText.label.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: 7),
        if (field != null)
          _RulePicker<DecisionFieldSpec>(
            items: fields,
            value: field,
            itemLabel: (f) => f.displayName,
            semanticsLabel: context.l10n.decisionGraphRuleFieldLabel,
            onSelected: (selected) => setState(() {
              _ruleField = selected;
              final newOperators = operatorsFor(selected.type);
              _ruleOperator = newOperators.first;
              _ruleIntValueController?.dispose();
              _ruleIntValueController = null;
              if (selected.type == DecisionFieldType.integer) {
                _ruleIntValueController = TextEditingController(text: '0')
                  ..addListener(_onParamChanged);
              } else {
                _ruleBoolValue = false;
              }
            }),
          ),
        const SizedBox(height: AionSpacing.sp16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.decisionGraphRuleOperatorLabel,
                    style: AionText.label.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: 7),
                  if (field != null && _ruleOperator != null)
                    _RulePicker<DecisionRuleOperator>(
                      items: operators,
                      value: _ruleOperator!,
                      itemLabel: (o) => _ruleOperatorLabel(o, field.type),
                      semanticsLabel:
                          context.l10n.decisionGraphRuleOperatorLabel,
                      onSelected: (selected) =>
                          setState(() => _ruleOperator = selected),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AionSpacing.sp12),
            SizedBox(
              width: 132,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.decisionGraphRuleValueLabel,
                    style: AionText.label.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: 7),
                  if (field == null)
                    const SizedBox(height: 40)
                  else if (field.type == DecisionFieldType.integer)
                    AppTextField(
                      controller: _ruleIntValueController!,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      isError:
                          int.tryParse(_ruleIntValueController!.text.trim()) ==
                          null,
                    )
                  else
                    _RulePicker<bool>(
                      items: const [true, false],
                      value: _ruleBoolValue,
                      itemLabel: (v) => v ? 'True' : 'False',
                      semanticsLabel: context.l10n.decisionGraphRuleValueLabel,
                      onSelected: (selected) =>
                          setState(() => _ruleBoolValue = selected),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The `agentJudgment` condition's single field: a multi-line prompt
  /// (`AgentPromptField`), rendered in place of both the generic
  /// per-catalog-parameter loop and the rule trio when
  /// `_condition?.id == agentJudgmentConditionId`. Per `AIO-613` §2 — label +
  /// required marker, placeholder example question, a default two-sentence
  /// helper (states the yes/no branch semantics, per §2.2's "the one place
  /// this is stated"), a `n/240` counter once the prompt reaches 180
  /// characters, and the error treatment (§2.5.5) once [_agentPromptShowError]
  /// is set (a save attempt, or blurring while empty — see
  /// [_save]/[_onAgentPromptFocusChange]). Added for `AIO-613`.
  Widget _buildAgentPromptField(BuildContext context, AionColors c) {
    final controller = _agentPromptController!;
    final length = controller.text.length;
    final isEmpty = controller.text.trim().isEmpty;
    final isError = _agentPromptShowError && isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: controller,
          focusNode: _agentPromptFocusNode,
          labelText: context.l10n.decisionGraphAgentPromptLabel,
          hintText: context.l10n.decisionGraphAgentPromptPlaceholder,
          isRequired: true,
          maxLines: 4,
          inputFormatters: [LengthLimitingTextInputFormatter(240)],
          isError: isError,
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Text(
                isError
                    ? context.l10n.decisionGraphAgentPromptRequiredError
                    : context.l10n.decisionGraphAgentPromptHelper,
                style: AionText.bodySm.copyWith(
                  color: isError ? c.danger : c.textMuted,
                ),
              ),
            ),
            if (length >= 180) ...[
              const SizedBox(width: AionSpacing.sp8),
              Text(
                '$length/240',
                style: AionText.time.copyWith(
                  color: length >= 240
                      ? c.danger
                      : length >= 220
                      ? c.warning
                      : c.textMuted,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A `DecisionConditionSpec` never equal (by identity — the class has no
/// overridden `==`) to any real [decisionConditionCatalog] entry, deliberately
/// constructed with `DecisionConditionSpec(...)` rather than
/// `const DecisionConditionSpec(...)` so it can never be canonicalized into
/// the same instance as a real spec. Used as [_ConditionPicker]'s
/// `SelectionMenu.currentValue` when nothing is chosen yet — see that picker's
/// own comment for why. Added for `AIO-181` (`/verify` fix pass 2).
final _unselectedConditionSentinel = DecisionConditionSpec(
  id: '__unselected__',
  displayName: '',
  contexts: const [],
  parameterSpecs: const [],
);

/// The condition-picker trigger + [SelectionMenu] for [DecisionNodeForm].
class _ConditionPicker extends StatelessWidget {
  const _ConditionPicker({
    required this.items,
    required this.value,
    required this.onSelected,
  });

  final List<DecisionConditionSpec> items;
  final DecisionConditionSpec? value;
  final ValueChanged<DecisionConditionSpec> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final current = value;
    // The rule-builder entry's `displayName` ('Custom rule') is a
    // plain-English domain-layer fallback, not the localized copy this
    // picker actually shows — see `ruleBuilderConditionSpec`'s own
    // dartdoc.
    String label(DecisionConditionSpec spec) => switch (spec.id) {
      ruleBuilderConditionId => context.l10n.decisionGraphRuleBuilderLabel,
      agentJudgmentConditionId => context.l10n.decisionGraphAgentJudgmentLabel,
      _ => spec.displayName,
    };
    final trigger = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceHover,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  current == null
                      ? context.l10n.decisionGraphConditionPickerPlaceholder
                      : label(current),
                  style: AionText.bodySm.copyWith(
                    color: current == null ? c.textMuted : c.textPrimary,
                    fontWeight: current == null
                        ? FontWeight.w400
                        : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (items.isEmpty) return trigger;

    return SelectionMenu<DecisionConditionSpec>(
      semanticsLabel: context.l10n.decisionGraphConditionPickerLabel,
      items: items,
      itemLabel: label,
      // `SelectionMenu` excludes `currentValue` from its offered list —
      // when nothing is chosen yet, `_unselectedConditionSentinel` (never
      // `==` a real catalog entry, since `DecisionConditionSpec` has no
      // overridden equality) is passed instead of e.g. `items.first`, so
      // every item stays selectable. Passing `items.first` here used to
      // silently hide the picker's first (often *only*) item whenever no
      // condition was yet selected — a real lockout for
      // `codingExecutionRetry`/`codingExecution`, whose catalog has
      // exactly one entry each. Fixed in `/verify` fix pass 2.
      currentValue: current ?? _unselectedConditionSentinel,
      onSelected: onSelected,
      trigger: trigger,
    );
  }
}

/// A compact `SelectionMenu<T>` trigger for the rule-builder trio's
/// field/operator/boolean-value pickers — styled like [_ConditionPicker]'s own
/// trigger, minus its "not yet chosen" sentinel handling: every rule-builder
/// field/operator/value always has a selected [value] the moment a
/// rule-builder condition is chosen (seeded by
/// `defaultRuleConditionParams`/[_DecisionNodeFormState._seedRuleState]), so
/// there's no unselected state to special-case. Renders inert (no
/// [SelectionMenu]) when [items] has one or fewer selectable alternatives —
/// [SelectionMenu] excludes [value] from its offered list, so a single-item
/// [items] would otherwise open onto an empty overlay; this is expected for
/// today's field picker, whose two contexts each expose exactly one field.
/// Added for `AIO-661`.
class _RulePicker<T> extends StatelessWidget {
  const _RulePicker({
    required this.items,
    required this.value,
    required this.itemLabel,
    required this.onSelected,
    required this.semanticsLabel,
  });

  final List<T> items;
  final T value;
  final String Function(T) itemLabel;
  final ValueChanged<T> onSelected;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final trigger = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceHover,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  itemLabel(value),
                  style: AionText.bodySm.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (items.length <= 1) return trigger;

    return SelectionMenu<T>(
      semanticsLabel: semanticsLabel,
      items: items,
      itemLabel: itemLabel,
      currentValue: value,
      onSelected: onSelected,
      trigger: trigger,
    );
  }
}

/// One matched/unmatched branch section: a labeled dot, the design.md
/// §3.3/§3.4 two-segment "End here / Continue to condition" mode toggle, and
/// either a terminal-outcome [SelectionMenu] ([DecisionBranchMode .endHere])
/// or a chaining condition picker/label
/// ([DecisionBranchMode.continueToCondition]). Added for `AIO-181` (`/verify`
/// fix pass — this control was previously missing entirely, so every branch
/// could only ever end in a terminal outcome).
class _BranchSection extends StatelessWidget {
  const _BranchSection({
    required this.label,
    required this.dotColor,
    required this.chainEyebrow,
    required this.mode,
    required this.onModeChanged,
    required this.outcome,
    required this.onOutcomeSelected,
    required this.catalog,
    required this.existingChildConditionLabel,
    required this.chainCondition,
    required this.onChainConditionSelected,
  });

  final String label;
  final Color dotColor;

  /// design.md §3.3/§3.4's "THEN CHECK"/"OTHERWISE CHECK" eyebrow,
  /// preceding the nested condition picker while in
  /// [DecisionBranchMode.continueToCondition] with no existing child yet.
  final String chainEyebrow;
  final DecisionBranchMode mode;
  final ValueChanged<DecisionBranchMode> onModeChanged;
  final DecisionOutcome outcome;
  final ValueChanged<DecisionOutcome> onOutcomeSelected;
  final List<DecisionConditionSpec> catalog;
  final String? existingChildConditionLabel;
  final DecisionConditionSpec? chainCondition;
  final ValueChanged<DecisionConditionSpec> onChainConditionSelected;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 7, height: 7),
            ),
            const SizedBox(width: 6),
            Text(label, style: AionText.label.copyWith(color: c.textSecondary)),
          ],
        ),
        const SizedBox(height: 7),
        _BranchModeToggle(
          mode: mode,
          onChanged: onModeChanged,
          // A branch that already continues to a child node can't be
          // switched back to picking a new chaining condition from a
          // catalog with nothing in it — but it can still be detached
          // back to "end here", so the toggle itself stays enabled
          // either way; only the picker below is catalog-gated.
        ),
        const SizedBox(height: 7),
        switch (mode) {
          DecisionBranchMode.endHere => SelectionMenu<DecisionOutcome>(
            semanticsLabel: label,
            items: DecisionOutcome.values,
            itemLabel: (o) => decisionOutcomeLabel(context, o),
            currentValue: outcome,
            onSelected: onOutcomeSelected,
            itemBuilder: (context, c, item) => _OutcomeMenuRow(outcome: item),
            trigger: _OutcomeChip(outcome: outcome),
          ),
          DecisionBranchMode.continueToCondition =>
            existingChildConditionLabel != null
                ? Text(
                    context.l10n.decisionGraphContinuesToLabel(
                      existingChildConditionLabel!,
                    ),
                    style: AionText.bodySm.copyWith(color: c.textSecondary),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chainEyebrow,
                        style: AionText.caption.copyWith(color: c.textMuted),
                      ),
                      const SizedBox(height: 7),
                      _ConditionPicker(
                        items: catalog,
                        value: chainCondition,
                        onSelected: onChainConditionSelected,
                      ),
                    ],
                  ),
        },
      ],
    );
  }
}

/// The design.md §3.3/§3.4 two-segment "End here / Continue to condition"
/// control. Added for `AIO-181` (`/verify` fix pass).
class _BranchModeToggle extends StatelessWidget {
  const _BranchModeToggle({required this.mode, required this.onChanged});

  final DecisionBranchMode mode;
  final ValueChanged<DecisionBranchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceHover,
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: _BranchModeSegment(
                label: context.l10n.decisionGraphEndHereOption,
                selected: mode == DecisionBranchMode.endHere,
                onTap: () => onChanged(DecisionBranchMode.endHere),
              ),
            ),
            Flexible(
              child: _BranchModeSegment(
                label: context.l10n.decisionGraphContinueOption,
                selected: mode == DecisionBranchMode.continueToCondition,
                onTap: () => onChanged(DecisionBranchMode.continueToCondition),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One segment of [_BranchModeToggle].
class _BranchModeSegment extends StatelessWidget {
  const _BranchModeSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? c.surface : const Color(0x00000000),
            border: selected ? Border.all(color: c.border, width: 1) : null,
            borderRadius: BorderRadius.all(AionRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: AionText.bodySm.copyWith(
                color: selected ? c.textPrimary : c.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// The [SelectionMenu]`<DecisionOutcome>` trigger — a small outcome chip.
class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.outcome});

  final DecisionOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final color = decisionOutcomeColor(c, outcome);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
        child: SizedBox(
          height: 34,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                decisionOutcomeLabel(context, outcome),
                style: AionText.badgeLabel.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One [SelectionMenu]`<DecisionOutcome>` menu row.
class _OutcomeMenuRow extends StatelessWidget {
  const _OutcomeMenuRow({required this.outcome});

  final DecisionOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final color = decisionOutcomeColor(c, outcome);
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox(width: 8, height: 8),
        ),
        const SizedBox(width: 11),
        Text(
          decisionOutcomeLabel(context, outcome),
          style: AionText.bodySm.copyWith(color: c.textPrimary),
        ),
      ],
    );
  }
}

/// Chrome around [DecisionNodeForm]'s popover mount (see
/// [DecisionNodeForm.showAsPopover]) — fill, border, radius, and shadow
/// matching design.md §3's popover-mount spec.
class _PopoverChrome extends StatelessWidget {
  const _PopoverChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.borderStrong, width: 1),
        borderRadius: BorderRadius.all(AionRadius.xl),
        boxShadow: AionShadows.card(c, t.isDark),
      ),
      child: SizedBox(width: 376, child: child),
    );
  }
}
