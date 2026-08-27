// presentation/widgets/decision_node_form.dart — DecisionNodeForm condition-editing form (presentation layer).

import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputType;
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

/// One condition-editing form: a condition picker (over
/// `decisionConditionsFor(automationContext)`), that condition's typed
/// parameter fields, and a matched/unmatched terminal-outcome picker
/// pair. Shared by both `DecisionOutlineList`'s inline expand-in-place
/// row and `GraphCanvas`'s popover mount (via
/// [DecisionNodeForm.showAsPopover]) — one widget, so the two panes can
/// never render divergent editing UI for the same node.
///
/// This slice's shipped condition catalog has exactly one entry per
/// applicable [AutomationContext] (see `decision_condition_catalog.dart`),
/// so both branches here resolve directly to a terminal
/// [DecisionOutcome] — "continue to another condition" (chaining a
/// second node onto a branch) is not yet reachable from this form; the
/// engine (`DecisionNode.matchedBranch`/`.unmatchedBranch` as
/// `DecisionBranch.toNode`) supports it, but authoring a multi-level tree
/// through this UI is left for a follow-up once the catalog has more than
/// one condition per context to chain. Added for
/// `aion-arch/changes/automation-decision-graphs`; see that change's
/// design.md §3.
class DecisionNodeForm extends StatefulWidget {
  /// Creates a [DecisionNodeForm]. Pass [initialConditionId]/
  /// [initialConditionParams]/[initialMatchedOutcome]/
  /// [initialUnmatchedOutcome] when editing an existing node; omit them
  /// (all default to a not-yet-chosen condition and
  /// [DecisionOutcome.gated]/[DecisionOutcome.proceed]) when authoring a
  /// brand-new one. [onDelete] is omitted entirely for a not-yet-saved
  /// new node — see design.md §3.5.
  const DecisionNodeForm({
    super.key,
    required this.automationContext,
    this.initialConditionId,
    this.initialConditionParams = const {},
    this.initialMatchedOutcome = DecisionOutcome.gated,
    this.initialUnmatchedOutcome = DecisionOutcome.proceed,
    required this.onSave,
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

  /// The matched branch's preselected terminal outcome.
  final DecisionOutcome initialMatchedOutcome;

  /// The unmatched branch's preselected terminal outcome.
  final DecisionOutcome initialUnmatchedOutcome;

  /// Called with the form's committed values when Save is pressed (only
  /// enabled once a condition is chosen and every required parameter is
  /// valid).
  final void Function({
    required String conditionId,
    required Map<String, dynamic> conditionParams,
    required DecisionOutcome matchedOutcome,
    required DecisionOutcome unmatchedOutcome,
  })
  onSave;

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
  /// design.md §3's "popover mount".
  static void showAsPopover(
    BuildContext context, {
    required LayerLink link,
    required AutomationContext automationContext,
    String? initialConditionId,
    Map<String, dynamic> initialConditionParams = const {},
    DecisionOutcome initialMatchedOutcome = DecisionOutcome.gated,
    DecisionOutcome initialUnmatchedOutcome = DecisionOutcome.proceed,
    required void Function({
      required String conditionId,
      required Map<String, dynamic> conditionParams,
      required DecisionOutcome matchedOutcome,
      required DecisionOutcome unmatchedOutcome,
    })
    onSave,
    VoidCallback? onDelete,
  }) {
    late OverlayEntry entry;
    void dismiss() => entry.remove();
    entry = OverlayEntry(
      builder: (context) => Stack(
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
                initialMatchedOutcome: initialMatchedOutcome,
                initialUnmatchedOutcome: initialUnmatchedOutcome,
                onSave:
                    ({
                      required conditionId,
                      required conditionParams,
                      required matchedOutcome,
                      required unmatchedOutcome,
                    }) {
                      onSave(
                        conditionId: conditionId,
                        conditionParams: conditionParams,
                        matchedOutcome: matchedOutcome,
                        unmatchedOutcome: unmatchedOutcome,
                      );
                      dismiss();
                    },
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
    );
    Overlay.of(context).insert(entry);
  }

  @override
  State<DecisionNodeForm> createState() => _DecisionNodeFormState();
}

class _DecisionNodeFormState extends State<DecisionNodeForm> {
  DecisionConditionSpec? _condition;
  final Map<String, TextEditingController> _paramControllers = {};
  late DecisionOutcome _matchedOutcome;
  late DecisionOutcome _unmatchedOutcome;

  @override
  void initState() {
    super.initState();
    final catalog = decisionConditionsFor(widget.automationContext);
    _condition = catalog
        .where((spec) => spec.id == widget.initialConditionId)
        .firstOrNull;
    _matchedOutcome = widget.initialMatchedOutcome;
    _unmatchedOutcome = widget.initialUnmatchedOutcome;
    _seedParamControllers();
  }

  @override
  void dispose() {
    for (final controller in _paramControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

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
      );
    }
  }

  bool get _isValid {
    final condition = _condition;
    if (condition == null) return false;
    for (final spec in condition.parameterSpecs) {
      final text = _paramControllers[spec.name]?.text.trim() ?? '';
      if (int.tryParse(text) == null) return false;
    }
    return true;
  }

  void _save() {
    final condition = _condition;
    if (condition == null || !_isValid) return;
    final params = <String, dynamic>{
      for (final spec in condition.parameterSpecs)
        spec.name: int.parse(_paramControllers[spec.name]!.text.trim()),
    };
    widget.onSave(
      conditionId: condition.id,
      conditionParams: params,
      matchedOutcome: _matchedOutcome,
      unmatchedOutcome: _unmatchedOutcome,
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
          _BranchPicker(
            label: context.l10n.decisionGraphMatchedLabel,
            dotColor: c.primary,
            value: _matchedOutcome,
            onSelected: (o) => setState(() => _matchedOutcome = o),
          ),
          const SizedBox(height: AionSpacing.sp16),
          _BranchPicker(
            label: context.l10n.decisionGraphUnmatchedLabel,
            dotColor: c.borderStrong,
            value: _unmatchedOutcome,
            onSelected: (o) => setState(() => _unmatchedOutcome = o),
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
                        onPressed: _isValid ? _save : null,
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
      currentValue: current ?? items.first,
      onSelected: onSelected,
      trigger: trigger,
    );
  }
}

/// One matched/unmatched terminal-outcome picker row: a labeled dot plus
/// a [SelectionMenu]`<DecisionOutcome>` — simplified from design.md §3.3/
/// §3.4's two-segment "end here / continue to condition" control, since
/// this form only ever authors a terminal outcome (see
/// [DecisionNodeForm]'s own dartdoc).
class _BranchPicker extends StatelessWidget {
  const _BranchPicker({
    required this.label,
    required this.dotColor,
    required this.value,
    required this.onSelected,
  });

  final String label;
  final Color dotColor;
  final DecisionOutcome value;
  final ValueChanged<DecisionOutcome> onSelected;

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
        SelectionMenu<DecisionOutcome>(
          semanticsLabel: label,
          items: DecisionOutcome.values,
          itemLabel: (o) => decisionOutcomeLabel(context, o),
          currentValue: value,
          onSelected: onSelected,
          itemBuilder: (context, c, item) => _OutcomeMenuRow(outcome: item),
          trigger: _OutcomeChip(outcome: value),
        ),
      ],
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
