// presentation/widgets/transition_node_form.dart — TransitionNodeForm field-check-editing form (presentation layer).

import 'dart:async' show unawaited;

import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';

/// Localized display label for [outcome] — module-private since
/// [TransitionNodeForm]/`TransitionOutlineList`/
/// `SddStagePreconditionEditorScreen` are its only consumers.
String transitionOutcomeLabel(
  BuildContext context,
  TransitionOutcome outcome,
) => switch (outcome) {
  TransitionOutcome.allowed =>
    context.l10n.transitionPreconditionOutcomeAllowedLabel,
  TransitionOutcome.blocked =>
    context.l10n.transitionPreconditionOutcomeBlockedLabel,
};

/// The color token associated with [outcome] — `success`/`danger`, per
/// `AIO-1936` §0.1's
/// outcome color map. Distinct from `decisionOutcomeColor`'s 4-value map
/// (`success`/`warning`/`danger`/`secondary`) — `warning`/`secondary` are
/// deliberately unused here, since there's no "ask" or "defer" state.
Color transitionOutcomeColor(AionColors c, TransitionOutcome outcome) =>
    switch (outcome) {
      TransitionOutcome.allowed => c.success,
      TransitionOutcome.blocked => c.danger,
    };

/// The `CustomPaint` check/cross glyph every outcome indicator renders,
/// per `AIO-1936`
/// §0.1 — no icon font, so the two outcomes stay distinguishable by
/// silhouette alone, not by hue: a closed check (`allowed`) versus an
/// open cross (`blocked`). Shared by the canvas terminal pill (§1.3), the
/// outline badge (§2.2), and this form's own outcome chip (§3.3) — the
/// "one table, three consumers" pattern §0.1 itself calls out. Public
/// (not module-private) since `transition_outline_list.dart` and
/// `sddstage_precondition_editor_screen.dart` both render it too. Added
/// for `AIO-1936`'s round-2
/// `/verify` follow-up — the glyph was specified but never built in the
/// original `/apply` pass.
class TransitionOutcomeGlyph extends StatelessWidget {
  /// Creates a [TransitionOutcomeGlyph] painting [outcome] in [color] at
  /// [size] (a square box — §0.1's baseline is `12`, §2.2's outline
  /// badge uses `10`, §3.3's form chip uses `11`). [checkStrokeWidth]/
  /// [crossStrokeWidth] default to §0.1's `12×12` values (`2.0`/`1.6`)
  /// scaled by `size / 12`; pass §2.2's literal `1.8`/`1.4` at the
  /// `10×10` outline-badge call site, where the spec gives non-scaled
  /// values explicitly.
  const TransitionOutcomeGlyph({
    super.key,
    required this.outcome,
    required this.color,
    this.size = 12,
    this.checkStrokeWidth,
    this.crossStrokeWidth,
  });

  /// Which glyph to paint — a check for [TransitionOutcome.allowed], a
  /// cross for [TransitionOutcome.blocked].
  final TransitionOutcome outcome;

  /// The glyph's stroke color — always [transitionOutcomeColor] at the
  /// call site, per §0.1.
  final Color color;

  /// The square box (width and height) the glyph is painted in.
  final double size;

  /// Overrides §0.1's `12×12`-scaled default check-stroke width (`2.0 *
  /// size / 12`) — pass §2.2's literal `1.8` at the `10×10` outline-badge
  /// call site, where the spec gives a non-scaled value explicitly.
  final double? checkStrokeWidth;

  /// Same override shape as [checkStrokeWidth], for the cross stroke
  /// (default `1.6 * size / 12`; §2.2's literal outline-badge value is
  /// `1.4`).
  final double? crossStrokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TransitionOutcomeGlyphPainter(
          outcome: outcome,
          color: color,
          size: size,
          checkStrokeWidth: checkStrokeWidth ?? 2.0 * size / 12,
          crossStrokeWidth: crossStrokeWidth ?? 1.6 * size / 12,
        ),
      ),
    );
  }
}

/// [TransitionOutcomeGlyph]'s painter. Draws within a `size × size` box,
/// scaled from §0.1's `12×12` reference geometry.
class _TransitionOutcomeGlyphPainter extends CustomPainter {
  _TransitionOutcomeGlyphPainter({
    required this.outcome,
    required this.color,
    required this.size,
    required this.checkStrokeWidth,
    required this.crossStrokeWidth,
  });

  final TransitionOutcome outcome;
  final Color color;
  final double size;
  final double checkStrokeWidth;
  final double crossStrokeWidth;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final scale = size / 12;
    switch (outcome) {
      case TransitionOutcome.allowed:
        // Two strokes, ~11 long × 7 tall (§0.1's check), StrokeCap.round
        // + StrokeJoin.round at the joint.
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = checkStrokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final path = Path()
          ..moveTo(0.5 * scale, 6.3 * scale)
          ..lineTo(4.5 * scale, 9.7 * scale)
          ..lineTo(11.5 * scale, 2.3 * scale);
        canvas.drawPath(path, paint);
      case TransitionOutcome.blocked:
        // Two ~10-long strokes at ±45° through the box's center (§0.1's
        // cross), StrokeCap.round.
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = crossStrokeWidth
          ..strokeCap = StrokeCap.round;
        final center = size / 2;
        final half = 3.5355 * scale; // half of a 10-long diagonal
        canvas
          ..drawLine(
            Offset(center - half, center - half),
            Offset(center + half, center + half),
            paint,
          )
          ..drawLine(
            Offset(center + half, center - half),
            Offset(center - half, center + half),
            paint,
          );
    }
  }

  @override
  bool shouldRepaint(covariant _TransitionOutcomeGlyphPainter oldDelegate) =>
      oldDelegate.outcome != outcome ||
      oldDelegate.color != color ||
      oldDelegate.size != size ||
      oldDelegate.checkStrokeWidth != checkStrokeWidth ||
      oldDelegate.crossStrokeWidth != crossStrokeWidth;
}

/// [branch]'s chained child's field display name, resolved from
/// [nodesById] — feeds [TransitionNodeForm]'s `...ChildFieldLabel`
/// parameters. `null` for a terminal branch, or for a
/// [TransitionBranch.toNode] whose target is missing from [nodesById] (a
/// dangling reference — the same defensive treatment
/// `evaluate_transition_graph.dart` gives it at evaluation time). Shared
/// by `TransitionOutlineList` and `SddStagePreconditionEditorScreen`'s
/// canvas pane so the two panes can't resolve this differently. Mirrors
/// `chainedChildConditionLabel` (`decision_node_form.dart`).
String? chainedChildFieldLabel(
  TransitionBranch branch,
  Map<String, TransitionNode> nodesById,
) {
  if (branch is! ToTransitionNodeBranch) return null;
  final child = nodesById[branch.nodeId];
  if (child == null) return null;
  return transitionFieldById(child.fieldId)?.displayName ?? child.fieldId;
}

/// Whether a [TransitionNodeForm] branch (matched or unmatched) currently
/// terminates in an outcome, or continues the strict tree into another
/// field check — the form-local mirror of [TransitionBranch]'s two
/// variants. Mirrors `DecisionBranchMode` (`decision_node_form.dart`).
enum TransitionBranchMode {
  /// The branch resolves to a terminal [TransitionOutcome] — "End here".
  endHere,

  /// The branch continues into another [TransitionNode] — "Continue to
  /// field check".
  continueToField,
}

/// One field-check-editing form: a field picker (over
/// `transitionFieldsFor(stage)`) and a matched/unmatched branch picker
/// pair — each branch independently either ends in a terminal
/// [TransitionOutcome] or continues to another field check (a chained
/// child [TransitionNode], created via [onCreateChainedChild] the first
/// time a branch switches into [TransitionBranchMode.continueToField]).
/// Shared by both `TransitionOutlineList`'s inline expand-in-place row
/// and `GraphCanvas`'s popover mount (via [TransitionNodeForm.showAsPopover]).
/// Simpler than `DecisionNodeForm` by design — no condition-kind picker
/// (there's only one kind), no parameter field (every field is a plain
/// boolean). Added for `AIO-1936`.
class TransitionNodeForm extends StatefulWidget {
  /// Creates a [TransitionNodeForm]. Pass [initialFieldId]/
  /// [initialMatchedBranch]/[initialUnmatchedBranch] when editing an
  /// existing node; omit them (field unset, both branches terminal
  /// `blocked`) when authoring a brand-new one. [matchedChildFieldLabel]/
  /// [unmatchedChildFieldLabel] must be supplied whenever the
  /// corresponding initial branch is a [TransitionBranch.toNode] — the
  /// form has no repository access of its own to resolve one.
  /// [onDelete] is omitted entirely for a not-yet-saved new node.
  /// [descendantCount] is the number of nodes [onDelete] would
  /// cascade-delete along with this one.
  const TransitionNodeForm({
    super.key,
    required this.stage,
    this.initialFieldId,
    this.initialMatchedBranch = const TransitionBranch.terminal(
      TransitionOutcome.allowed,
    ),
    this.initialUnmatchedBranch = const TransitionBranch.terminal(
      TransitionOutcome.blocked,
    ),
    this.matchedChildFieldLabel,
    this.unmatchedChildFieldLabel,
    this.forceMatchedContinue = false,
    this.forceUnmatchedContinue = false,
    this.descendantCount = 0,
    required this.onSave,
    required this.onCreateChainedChild,
    required this.onCancel,
    this.onDelete,
    this.onDirtyChanged,
  });

  /// Which [SddStage] this form's field picker is scoped to.
  final SddStage stage;

  /// The field id to preselect, or `null` for "no field chosen yet."
  final String? initialFieldId;

  /// The matched branch's preselected shape — terminal or chained.
  final TransitionBranch initialMatchedBranch;

  /// The unmatched branch's preselected shape — terminal or chained.
  final TransitionBranch initialUnmatchedBranch;

  /// Display name of the matched branch's existing chained child's
  /// field, when [initialMatchedBranch] is a [TransitionBranch.toNode].
  /// Ignored otherwise.
  final String? matchedChildFieldLabel;

  /// Same as [matchedChildFieldLabel], for the unmatched branch.
  final String? unmatchedChildFieldLabel;

  /// Starts the matched branch's mode in
  /// [TransitionBranchMode.continueToField] regardless of
  /// [initialMatchedBranch] — used by `TransitionOutlineList`'s
  /// per-branch "+ Add field check" shortcut.
  final bool forceMatchedContinue;

  /// Same as [forceMatchedContinue], for the unmatched branch.
  final bool forceUnmatchedContinue;

  /// The number of descendant nodes [onDelete] would cascade-delete along
  /// with this one. `0` for a leaf node (or a not-yet-saved new node,
  /// which hides [onDelete] entirely).
  final int descendantCount;

  /// Called with the form's committed values when Save is pressed (only
  /// enabled once a field is chosen and every branch in
  /// [TransitionBranchMode.continueToField] mode has picked a field to
  /// chain to).
  final void Function({
    required String fieldId,
    required TransitionBranch matchedBranch,
    required TransitionBranch unmatchedBranch,
  })
  onSave;

  /// Called when a branch is switched into
  /// [TransitionBranchMode.continueToField] for the first time (no
  /// existing chained child yet) and a chaining field is picked — must
  /// create a fresh [TransitionNode] for [fieldId] and return its id, or
  /// `null` if the write was rejected. Never called for a branch that
  /// already has a chained child — that id is reused as-is.
  final Future<String?> Function(String fieldId) onCreateChainedChild;

  /// Called when Cancel/Escape/click-outside dismisses the form without
  /// saving.
  final VoidCallback onCancel;

  /// Called when Delete is pressed. `null` hides the Delete action
  /// entirely — used for a not-yet-saved new node.
  final VoidCallback? onDelete;

  /// Called with `true` the moment the form's picks first diverge from
  /// [initialFieldId]/[initialMatchedBranch]/[initialUnmatchedBranch], and
  /// with `false` whenever they revert to matching, or when the form is
  /// disposed (dismissed, saved, or unmounted for any other reason).
  /// Backs `SddStagePreconditionEditorScreen`'s "N UNSAVED CHANGE" header
  /// indicator (design.md §4.1). `null` if the caller doesn't care. Added
  /// for `AIO-1936`'s
  /// post-`/verify` follow-up.
  final ValueChanged<bool>? onDirtyChanged;

  /// Mounts a [TransitionNodeForm] as a popover: an [OverlayEntry] +
  /// [CompositedTransformFollower] anchored below [link]'s target,
  /// dismissed on outside-tap or Escape. Used by
  /// `PreconditionGraphCanvas`'s node-tap-to-edit interaction. Mirrors
  /// `DecisionNodeForm.showAsPopover` — [onSave]/[onCreateChainedChild]/
  /// [onDelete] must already be bound to the caller's
  /// `TransitionPreconditionConfigCubit` *before* this is called.
  static void showAsPopover(
    BuildContext context, {
    required LayerLink link,
    required SddStage stage,
    String? initialFieldId,
    TransitionBranch initialMatchedBranch = const TransitionBranch.terminal(
      TransitionOutcome.allowed,
    ),
    TransitionBranch initialUnmatchedBranch = const TransitionBranch.terminal(
      TransitionOutcome.blocked,
    ),
    String? matchedChildFieldLabel,
    String? unmatchedChildFieldLabel,
    int descendantCount = 0,
    required void Function({
      required String fieldId,
      required TransitionBranch matchedBranch,
      required TransitionBranch unmatchedBranch,
    })
    onSave,
    required Future<String?> Function(String fieldId) onCreateChainedChild,
    VoidCallback? onDelete,
    ValueChanged<bool>? onDirtyChanged,
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
                child: TransitionNodeForm(
                  stage: stage,
                  initialFieldId: initialFieldId,
                  initialMatchedBranch: initialMatchedBranch,
                  initialUnmatchedBranch: initialUnmatchedBranch,
                  matchedChildFieldLabel: matchedChildFieldLabel,
                  unmatchedChildFieldLabel: unmatchedChildFieldLabel,
                  descendantCount: descendantCount,
                  onSave:
                      ({
                        required fieldId,
                        required matchedBranch,
                        required unmatchedBranch,
                      }) {
                        onSave(
                          fieldId: fieldId,
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
                  onDirtyChanged: onDirtyChanged,
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
  State<TransitionNodeForm> createState() => _TransitionNodeFormState();
}

class _TransitionNodeFormState extends State<TransitionNodeForm> {
  TransitionFieldSpec? _field;

  late TransitionBranchMode _matchedMode;
  late TransitionOutcome _matchedOutcome;
  String? _matchedExistingChildId;
  TransitionFieldSpec? _matchedChainField;

  late TransitionBranchMode _unmatchedMode;
  late TransitionOutcome _unmatchedOutcome;
  String? _unmatchedExistingChildId;
  TransitionFieldSpec? _unmatchedChainField;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final catalog = transitionFieldsFor(widget.stage);
    _field = catalog
        .where((spec) => spec.id == widget.initialFieldId)
        .firstOrNull;

    switch (widget.initialMatchedBranch) {
      case TerminalTransitionBranch(:final outcome):
        _matchedMode = widget.forceMatchedContinue
            ? TransitionBranchMode.continueToField
            : TransitionBranchMode.endHere;
        _matchedOutcome = outcome;
      case ToTransitionNodeBranch(:final nodeId):
        _matchedMode = TransitionBranchMode.continueToField;
        _matchedOutcome = TransitionOutcome.allowed;
        _matchedExistingChildId = nodeId;
    }
    switch (widget.initialUnmatchedBranch) {
      case TerminalTransitionBranch(:final outcome):
        _unmatchedMode = widget.forceUnmatchedContinue
            ? TransitionBranchMode.continueToField
            : TransitionBranchMode.endHere;
        _unmatchedOutcome = outcome;
      case ToTransitionNodeBranch(:final nodeId):
        _unmatchedMode = TransitionBranchMode.continueToField;
        _unmatchedOutcome = TransitionOutcome.blocked;
        _unmatchedExistingChildId = nodeId;
    }
    widget.onDirtyChanged?.call(_isDirty);
  }

  @override
  void dispose() {
    widget.onDirtyChanged?.call(false);
    super.dispose();
  }

  /// `setState(fn)`, then re-derives [_isDirty] and notifies
  /// [TransitionNodeForm.onDirtyChanged] — the shared wrapper every
  /// mutating callback below uses in place of a bare `setState`, so no
  /// pick can change without the header's "N UNSAVED CHANGE" indicator
  /// staying in sync.
  void _setAndNotify(VoidCallback fn) {
    setState(fn);
    widget.onDirtyChanged?.call(_isDirty);
  }

  /// Whether the form's current picks diverge from
  /// [TransitionNodeForm.initialFieldId]/`.initialMatchedBranch`/
  /// `.initialUnmatchedBranch`.
  bool get _isDirty {
    if (_field?.id != widget.initialFieldId) return true;
    if (_branchDirty(
      initial: widget.initialMatchedBranch,
      mode: _matchedMode,
      outcome: _matchedOutcome,
      existingChildId: _matchedExistingChildId,
    )) {
      return true;
    }
    if (_branchDirty(
      initial: widget.initialUnmatchedBranch,
      mode: _unmatchedMode,
      outcome: _unmatchedOutcome,
      existingChildId: _unmatchedExistingChildId,
    )) {
      return true;
    }
    return false;
  }

  /// Whether one branch's current [mode]/[outcome]/[existingChildId]
  /// diverges from [initial] — a mode switch (terminal ↔ chained) is
  /// always dirty; within [TransitionBranchMode.endHere], only an
  /// [outcome] flip is; within [TransitionBranchMode.continueToField], a
  /// still-unpicked or newly-different chain target is (an existing
  /// chain reused as-is, the common case, is never dirty on its own).
  bool _branchDirty({
    required TransitionBranch initial,
    required TransitionBranchMode mode,
    required TransitionOutcome outcome,
    required String? existingChildId,
  }) {
    switch (mode) {
      case TransitionBranchMode.endHere:
        return switch (initial) {
          TerminalTransitionBranch(outcome: final initialOutcome) =>
            initialOutcome != outcome,
          ToTransitionNodeBranch() => true,
        };
      case TransitionBranchMode.continueToField:
        return switch (initial) {
          ToTransitionNodeBranch(nodeId: final initialNodeId) =>
            existingChildId == null || existingChildId != initialNodeId,
          TerminalTransitionBranch() => true,
        };
    }
  }

  /// A branch in [TransitionBranchMode.continueToField] is valid once it
  /// either already has a chained child, or a chaining field has been
  /// picked for a brand-new chain — mirrors [_save]'s own resolution
  /// logic.
  bool _branchValid({
    required TransitionBranchMode mode,
    required String? existingChildId,
    required TransitionFieldSpec? chainField,
  }) => switch (mode) {
    TransitionBranchMode.endHere => true,
    TransitionBranchMode.continueToField =>
      existingChildId != null || chainField != null,
  };

  bool get _isValid {
    if (_field == null) return false;
    return _branchValid(
          mode: _matchedMode,
          existingChildId: _matchedExistingChildId,
          chainField: _matchedChainField,
        ) &&
        _branchValid(
          mode: _unmatchedMode,
          existingChildId: _unmatchedExistingChildId,
          chainField: _unmatchedChainField,
        );
  }

  /// Resolves one branch to its committed [TransitionBranch], creating a
  /// fresh chained child via [TransitionNodeForm.onCreateChainedChild]
  /// the first time a branch enters [TransitionBranchMode.continueToField]
  /// (an existing chained child's id is reused untouched). Returns `null`
  /// if resolution isn't possible — the caller aborts the whole save in
  /// that case.
  Future<TransitionBranch?> _resolveBranch({
    required TransitionBranchMode mode,
    required TransitionOutcome outcome,
    required String? existingChildId,
    required TransitionFieldSpec? chainField,
  }) async {
    switch (mode) {
      case TransitionBranchMode.endHere:
        return TransitionBranch.terminal(outcome);
      case TransitionBranchMode.continueToField:
        if (existingChildId != null) {
          return TransitionBranch.toNode(existingChildId);
        }
        final field = chainField;
        if (field == null) return null;
        final childId = await widget.onCreateChainedChild(field.id);
        return childId == null ? null : TransitionBranch.toNode(childId);
    }
  }

  Future<void> _save() async {
    final field = _field;
    if (field == null || !_isValid) return;
    if (_saving) return;
    setState(() => _saving = true);
    final matchedBranch = await _resolveBranch(
      mode: _matchedMode,
      outcome: _matchedOutcome,
      existingChildId: _matchedExistingChildId,
      chainField: _matchedChainField,
    );
    final unmatchedBranch = await _resolveBranch(
      mode: _unmatchedMode,
      outcome: _unmatchedOutcome,
      existingChildId: _unmatchedExistingChildId,
      chainField: _unmatchedChainField,
    );
    if (!mounted) return;
    if (matchedBranch == null || unmatchedBranch == null) {
      setState(() => _saving = false);
      return;
    }
    widget.onSave(
      fieldId: field.id,
      matchedBranch: matchedBranch,
      unmatchedBranch: unmatchedBranch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final catalog = transitionFieldsFor(widget.stage);

    return Padding(
      padding: const EdgeInsets.all(AionSpacing.sp16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.transitionPreconditionFieldPickerLabel,
            style: AionText.label.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: 7),
          _FieldPicker(
            items: catalog,
            value: _field,
            onSelected: (spec) => _setAndNotify(() => _field = spec),
          ),
          const SizedBox(height: AionSpacing.sp16),
          _BranchSection(
            label: context.l10n.transitionPreconditionMatchedLabel,
            dotColor: c.primary,
            chainEyebrow: context.l10n.transitionPreconditionThenCheck,
            mode: _matchedMode,
            onModeChanged: (m) => _setAndNotify(() => _matchedMode = m),
            outcome: _matchedOutcome,
            onOutcomeSelected: (o) => _setAndNotify(() => _matchedOutcome = o),
            catalog: catalog,
            existingChildFieldLabel: widget.matchedChildFieldLabel,
            chainField: _matchedChainField,
            onChainFieldSelected: (spec) =>
                _setAndNotify(() => _matchedChainField = spec),
          ),
          const SizedBox(height: AionSpacing.sp16),
          _BranchSection(
            label: context.l10n.transitionPreconditionUnmatchedLabel,
            dotColor: c.borderStrong,
            chainEyebrow: context.l10n.transitionPreconditionOtherwiseCheck,
            mode: _unmatchedMode,
            onModeChanged: (m) => _setAndNotify(() => _unmatchedMode = m),
            outcome: _unmatchedOutcome,
            onOutcomeSelected: (o) =>
                _setAndNotify(() => _unmatchedOutcome = o),
            catalog: catalog,
            existingChildFieldLabel: widget.unmatchedChildFieldLabel,
            chainField: _unmatchedChainField,
            onChainFieldSelected: (spec) =>
                _setAndNotify(() => _unmatchedChainField = spec),
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
                      label: context.l10n.transitionPreconditionDeleteButton,
                      variant: AppButtonVariant.destructive,
                      onPressed: () async {
                        final descendantCount = widget.descendantCount;
                        final confirmed = await showAppConfirmDialog(
                          context,
                          title: descendantCount > 0
                              ? context.l10n
                                    .transitionPreconditionDeleteConfirmTitleWithDescendants(
                                      descendantCount,
                                    )
                              : context
                                    .l10n
                                    .transitionPreconditionDeleteConfirmTitle,
                          message: context
                              .l10n
                              .transitionPreconditionDeleteConfirmMessage,
                          confirmLabel:
                              context.l10n.transitionPreconditionDeleteButton,
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

/// A [TransitionFieldSpec] never equal (by identity — the class has no
/// overridden `==`) to any real [transitionFieldCatalog] entry,
/// deliberately constructed with `TransitionFieldSpec(...)` rather than
/// `const TransitionFieldSpec(...)` so it can never be canonicalized into
/// the same instance as a real spec. Used as [_FieldPicker]'s
/// `SelectionMenu.currentValue` when nothing is chosen yet — passing
/// `items.first` there would otherwise hide that item from the offered
/// list (`SelectionMenu` excludes `currentValue` from what it offers),
/// mirroring `_unselectedConditionSentinel`'s exact fix
/// (`decision_node_form.dart`).
final _unselectedFieldSentinel = TransitionFieldSpec(
  id: '__unselected__',
  displayName: '',
  stages: const [],
);

/// The field-picker trigger + [SelectionMenu] for [TransitionNodeForm].
class _FieldPicker extends StatelessWidget {
  const _FieldPicker({
    required this.items,
    required this.value,
    required this.onSelected,
  });

  final List<TransitionFieldSpec> items;
  final TransitionFieldSpec? value;
  final ValueChanged<TransitionFieldSpec> onSelected;

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
                  current == null
                      ? context
                            .l10n
                            .transitionPreconditionFieldPickerPlaceholder
                      : current.displayName,
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

    return SelectionMenu<TransitionFieldSpec>(
      semanticsLabel: context.l10n.transitionPreconditionFieldPickerLabel,
      items: items,
      itemLabel: (spec) => spec.displayName,
      currentValue: current ?? _unselectedFieldSentinel,
      onSelected: onSelected,
      trigger: trigger,
    );
  }
}

/// One matched/unmatched branch section: a labeled dot, a two-segment
/// "End here / Continue to field check" mode toggle, and either a
/// terminal-outcome chip pair ([TransitionBranchMode.endHere]) or a
/// chaining field picker/label ([TransitionBranchMode.continueToField]).
/// Mirrors `_BranchSection` (`decision_node_form.dart`).
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
    required this.existingChildFieldLabel,
    required this.chainField,
    required this.onChainFieldSelected,
  });

  final String label;
  final Color dotColor;
  final String chainEyebrow;
  final TransitionBranchMode mode;
  final ValueChanged<TransitionBranchMode> onModeChanged;
  final TransitionOutcome outcome;
  final ValueChanged<TransitionOutcome> onOutcomeSelected;
  final List<TransitionFieldSpec> catalog;
  final String? existingChildFieldLabel;
  final TransitionFieldSpec? chainField;
  final ValueChanged<TransitionFieldSpec> onChainFieldSelected;

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
        _BranchModeToggle(mode: mode, onChanged: onModeChanged),
        const SizedBox(height: 7),
        switch (mode) {
          TransitionBranchMode.endHere => Row(
            children: [
              Expanded(
                child: _OutcomeChip(
                  outcome: TransitionOutcome.allowed,
                  selected: outcome == TransitionOutcome.allowed,
                  onTap: () => onOutcomeSelected(TransitionOutcome.allowed),
                ),
              ),
              const SizedBox(width: AionSpacing.sp8),
              Expanded(
                child: _OutcomeChip(
                  outcome: TransitionOutcome.blocked,
                  selected: outcome == TransitionOutcome.blocked,
                  onTap: () => onOutcomeSelected(TransitionOutcome.blocked),
                ),
              ),
            ],
          ),
          TransitionBranchMode.continueToField =>
            existingChildFieldLabel != null
                ? Text(
                    context.l10n.transitionPreconditionContinuesToLabel(
                      existingChildFieldLabel!,
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
                      _FieldPicker(
                        items: catalog,
                        value: chainField,
                        onSelected: onChainFieldSelected,
                      ),
                    ],
                  ),
        },
      ],
    );
  }
}

/// The two-segment "End here / Continue to field check" control. Mirrors
/// `_BranchModeToggle` (`decision_node_form.dart`).
class _BranchModeToggle extends StatelessWidget {
  const _BranchModeToggle({required this.mode, required this.onChanged});

  final TransitionBranchMode mode;
  final ValueChanged<TransitionBranchMode> onChanged;

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
                label: context.l10n.transitionPreconditionEndHereOption,
                selected: mode == TransitionBranchMode.endHere,
                onTap: () => onChanged(TransitionBranchMode.endHere),
              ),
            ),
            Flexible(
              child: _BranchModeSegment(
                label: context.l10n.transitionPreconditionContinueOption,
                selected: mode == TransitionBranchMode.continueToField,
                onTap: () => onChanged(TransitionBranchMode.continueToField),
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

/// One of §3.3's "End here" outcome chips — a single row of two
/// (`allowed`/`blocked`), not `DecisionNodeForm`'s 2×2 grid.
class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({
    required this.outcome,
    required this.selected,
    required this.onTap,
  });

  final TransitionOutcome outcome;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final color = transitionOutcomeColor(c, outcome);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.14 : 0.07),
            border: Border.all(
              color: selected ? color : c.border,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.all(AionRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
            child: SizedBox(
              height: 34,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // §3.3: glyph §0.1 at 11×11, glyph → label gap 7.
                  TransitionOutcomeGlyph(
                    outcome: outcome,
                    color: selected ? color : c.textSecondary,
                    size: 11,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    transitionOutcomeLabel(context, outcome),
                    style: AionText.badgeLabel.copyWith(
                      color: selected ? color : c.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chrome around [TransitionNodeForm]'s popover mount. Mirrors
/// `_PopoverChrome` (`decision_node_form.dart`).
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
