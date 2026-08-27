// presentation/widgets/decision_node_form.dart — DecisionNodeForm condition-editing form (presentation layer).

import 'dart:async' show unawaited;

import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        KeyDownEvent,
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

/// [branch]'s chained child's condition display name, resolved from
/// [nodesById] — feeds [DecisionNodeForm]'s `...ChildConditionLabel`
/// parameters. `null` for a terminal branch, or for a [DecisionBranch
/// .toNode] whose target is missing from [nodesById] (a dangling
/// reference — the same defensive treatment
/// `decision_graph_evaluator.dart` gives it at evaluation time). Shared
/// by `DecisionOutlineList` and `DecisionGraphEditorScreen`'s canvas pane
/// so the two panes can't resolve this differently. Added for
/// `aion-arch/changes/automation-decision-graphs` (`/verify` fix pass).
String? chainedChildConditionLabel(
  DecisionBranch branch,
  Map<String, DecisionNode> nodesById,
) {
  if (branch is! ToNodeBranch) return null;
  final child = nodesById[branch.nodeId];
  if (child == null) return null;
  return decisionConditionSpecById(child.conditionId)?.displayName ??
      child.conditionId;
}

/// Whether a [DecisionNodeForm] branch (matched or unmatched) currently
/// terminates in an outcome, or continues the strict tree into another
/// condition — the form-local mirror of [DecisionBranch]'s two variants,
/// driving the two-segment control design.md §3.3/§3.4 specifies. Added
/// for `aion-arch/changes/automation-decision-graphs` (`/verify` fix
/// pass — this mode was previously unreachable from the form, capping
/// every graph at one node).
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
/// Editing an *existing* chained branch's own condition/parameters isn't
/// done from here — once a branch continues to a child node, that child
/// renders as its own row/canvas node (see `DecisionOutlineList`'s
/// recursive rendering) with its own [DecisionNodeForm] mount; this form
/// only ever creates the chain or detaches it (switching a
/// [DecisionBranchMode.continueToCondition] branch back to
/// [DecisionBranchMode.endHere] leaves the child node orphaned rather
/// than deleting it, the same dangling-reference tolerance
/// `decision_graph_evaluator.dart` and `DecisionGraphConfigCubit
/// .deleteNode` already document). Added for
/// `aion-arch/changes/automation-decision-graphs`; see that change's
/// design.md §3.
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
  /// omitted entirely for a not-yet-saved new node — see design.md §3.5.
  /// [forceMatchedContinue]/[forceUnmatchedContinue] start that branch's
  /// mode in [DecisionBranchMode.continueToCondition] even though
  /// [initialMatchedBranch]/[initialUnmatchedBranch] is still a
  /// [DecisionBranch.terminal] — used by `DecisionOutlineList`'s
  /// per-branch "+ Add condition" shortcut (design.md §2.3) so tapping it
  /// opens this form with that branch already on the "continue to
  /// condition" segment, rather than requiring the user to find and
  /// toggle it themselves.
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
    final catalog = decisionConditionsFor(widget.automationContext);
    _condition = catalog
        .where((spec) => spec.id == widget.initialConditionId)
        .firstOrNull;
    _seedParamControllers();

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
    for (final spec in condition.parameterSpecs) {
      final text = _paramControllers[spec.name]?.text.trim() ?? '';
      if (int.tryParse(text) == null) return false;
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
    if (condition == null || !_isValid || _saving) return;
    setState(() => _saving = true);
    final params = <String, dynamic>{
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
    final catalog = decisionConditionsFor(widget.automationContext);

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
            }),
          ),
          if (_condition != null)
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
                      int.tryParse(_paramControllers[spec.name]!.text.trim()) ==
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
                        final confirmed = await showAppConfirmDialog(
                          context,
                          title: context.l10n.decisionGraphDeleteConfirmTitle,
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
}

/// A `DecisionConditionSpec` never equal (by identity — the class has no
/// overridden `==`) to any real [decisionConditionCatalog] entry,
/// deliberately constructed with `DecisionConditionSpec(...)` rather than
/// `const DecisionConditionSpec(...)` so it can never be canonicalized
/// into the same instance as a real spec. Used as [_ConditionPicker]'s
/// `SelectionMenu.currentValue` when nothing is chosen yet — see that
/// picker's own comment for why. Added for
/// `aion-arch/changes/automation-decision-graphs` (`/verify` fix pass 2).
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
                  current?.displayName ??
                      context.l10n.decisionGraphConditionPickerPlaceholder,
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
      itemLabel: (spec) => spec.displayName,
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

/// One matched/unmatched branch section: a labeled dot, the design.md
/// §3.3/§3.4 two-segment "End here / Continue to condition" mode toggle,
/// and either a terminal-outcome [SelectionMenu] ([DecisionBranchMode
/// .endHere]) or a chaining condition picker/label
/// ([DecisionBranchMode.continueToCondition]). Added for
/// `aion-arch/changes/automation-decision-graphs` (`/verify` fix pass —
/// this control was previously missing entirely, so every branch could
/// only ever end in a terminal outcome).
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

/// The design.md §3.3/§3.4 two-segment "End here / Continue to
/// condition" control. Added for
/// `aion-arch/changes/automation-decision-graphs` (`/verify` fix pass).
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
