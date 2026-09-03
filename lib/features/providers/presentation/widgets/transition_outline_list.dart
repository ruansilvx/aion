// presentation/widgets/transition_outline_list.dart — TransitionOutlineList nested-outline pane (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/presentation/cubit/transition_precondition_config_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/transition_precondition_config_state.dart';
import 'package:aion/features/providers/presentation/widgets/transition_node_form.dart';
import 'package:aion/features/tickets/tickets.dart';

/// The outline pane of `SddStagePreconditionEditorScreen`: one row per
/// `TransitionNode` (field name only — no parameter chip, since no field
/// this proposal ships takes one), children of a chained branch rendered
/// as their own indented row beneath it (recursively, no depth cap), plus
/// a dashed "+ Add field check" affordance when the graph has no root
/// yet. Reads/writes through [TransitionPreconditionConfigCubit] — the
/// same source of truth `GraphCanvas` renders from, so a selection or
/// edit in either pane is reflected in the other via the same
/// [TransitionPreconditionConfigState]. Simpler than `DecisionOutlineList`
/// — see that file's own dartdoc for the shape this mirrors. Added for
/// `AIO-1936`.
class TransitionOutlineList extends StatefulWidget {
  /// Creates a [TransitionOutlineList] for [stage].
  const TransitionOutlineList({
    super.key,
    required this.stage,
    this.onDirtyChanged,
  });

  /// Which [SddStage] this pane edits.
  final SddStage stage;

  /// Forwarded to every [TransitionNodeForm] this pane mounts inline —
  /// see [TransitionNodeForm.onDirtyChanged]. Added for
  /// `AIO-1936`'s post-
  /// `/verify` follow-up.
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<TransitionOutlineList> createState() => _TransitionOutlineListState();
}

class _TransitionOutlineListState extends State<TransitionOutlineList> {
  bool _formExpanded = false;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return BlocConsumer<
      TransitionPreconditionConfigCubit,
      TransitionPreconditionConfigState
    >(
      listener: (context, state) {
        if (state is TransitionPreconditionConfigLoaded) {
          setState(() => _formExpanded = false);
        }
      },
      builder: (context, state) {
        final loaded = switch (state) {
          TransitionPreconditionConfigLoaded loaded => loaded,
          TransitionPreconditionConfigError(:final previous) => previous,
          TransitionPreconditionConfigInitial() => null,
        };
        if (loaded == null) {
          return const Center(child: AppSpinner());
        }

        final rootId = loaded.graph.rootNodeId;
        final rootNode = rootId == null ? null : loaded.nodesById[rootId];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.transitionPreconditionOutlineHeader(
                      rootNode == null ? 0 : 1,
                    ),
                    style: AionText.caption.copyWith(color: c.textMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AionSpacing.sp8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state is TransitionPreconditionConfigError)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AionSpacing.sp12,
                        ),
                        child: Text(
                          state.message,
                          style: AionText.bodySm.copyWith(color: c.danger),
                        ),
                      ),
                    if (rootNode != null)
                      _NodeRow(
                        node: rootNode,
                        depth: 0,
                        nodesById: loaded.nodesById,
                        stage: widget.stage,
                        onDirtyChanged: widget.onDirtyChanged,
                        onDelete: () => context
                            .read<TransitionPreconditionConfigCubit>()
                            .deleteNode(rootNode.id),
                        onSave:
                            ({
                              required fieldId,
                              required matchedBranch,
                              required unmatchedBranch,
                            }) {
                              context
                                  .read<TransitionPreconditionConfigCubit>()
                                  .updateNode(
                                    rootNode.copyWith(
                                      fieldId: fieldId,
                                      matchedBranch: matchedBranch,
                                      unmatchedBranch: unmatchedBranch,
                                    ),
                                  );
                            },
                        onCreateChainedChild: _createChainedChild,
                      )
                    else if (_formExpanded)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AionSpacing.sp12,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.surface,
                            border: Border.all(color: c.border, width: 1),
                            borderRadius: BorderRadius.all(AionRadius.lg),
                          ),
                          child: TransitionNodeForm(
                            stage: widget.stage,
                            onDirtyChanged: widget.onDirtyChanged,
                            onSave:
                                ({
                                  required fieldId,
                                  required matchedBranch,
                                  required unmatchedBranch,
                                }) async {
                                  final cubit = context
                                      .read<
                                        TransitionPreconditionConfigCubit
                                      >();
                                  final newNodeId = await cubit.createNode(
                                    fieldId: fieldId,
                                    matchedBranch: matchedBranch,
                                    unmatchedBranch: unmatchedBranch,
                                  );
                                  if (newNodeId != null) {
                                    await cubit.setRoot(newNodeId);
                                  }
                                },
                            onCreateChainedChild: _createChainedChild,
                            onCancel: () =>
                                setState(() => _formExpanded = false),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AionSpacing.sp12,
                        ),
                        child: _AddFieldCheckAffordance(
                          onTap: () => setState(() => _formExpanded = true),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// [TransitionNodeForm.onCreateChainedChild]'s implementation for this
  /// pane: creates a fresh [TransitionNode] for [fieldId], with both
  /// branches defaulting to terminal `blocked` — the same shape
  /// [TransitionPreconditionConfigCubit.createNode] already defaults a
  /// brand-new node to.
  Future<String?> _createChainedChild(String fieldId) {
    return context.read<TransitionPreconditionConfigCubit>().createNode(
      fieldId: fieldId,
    );
  }
}

/// One row: field name (no parameter chip — no field here has a
/// parameter), trailing matched/unmatched outcome badges (for whichever
/// branches currently terminate), expand-in-place to a
/// [TransitionNodeForm] on tap. A branch that instead continues to a
/// chained child node renders that child as its own indented [_NodeRow]
/// beneath this one (recursively, via [_BranchChild]) — no depth cap.
/// Mirrors `_NodeRow` (`decision_outline_list.dart`).
class _NodeRow extends StatefulWidget {
  const _NodeRow({
    required this.node,
    required this.depth,
    required this.nodesById,
    required this.stage,
    required this.onSave,
    required this.onDelete,
    required this.onCreateChainedChild,
    this.onDirtyChanged,
  });

  final TransitionNode node;
  final int depth;

  /// Every node reachable from the graph's root — used to resolve a
  /// chained branch's child (for the recursive [_BranchChild] rows and
  /// [TransitionNodeForm]'s `...ChildFieldLabel`).
  final Map<String, TransitionNode> nodesById;
  final SddStage stage;
  final void Function({
    required String fieldId,
    required TransitionBranch matchedBranch,
    required TransitionBranch unmatchedBranch,
  })
  onSave;
  final VoidCallback onDelete;
  final Future<String?> Function(String fieldId) onCreateChainedChild;

  /// Forwarded to this row's inline [TransitionNodeForm] (when expanded)
  /// and to every descendant [_NodeRow] — see
  /// [TransitionOutlineList.onDirtyChanged].
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<_NodeRow> createState() => _NodeRowState();
}

class _NodeRowState extends State<_NodeRow> {
  bool _expanded = false;
  bool _hovered = false;

  /// Set (and consumed once) when a per-branch "+ Add field check"
  /// affordance is tapped, forcing that branch's mode straight to
  /// "Continue to field check" when the form expands — see
  /// [TransitionNodeForm.forceMatchedContinue]/`.forceUnmatchedContinue`.
  bool _forceMatchedContinue = false;
  bool _forceUnmatchedContinue = false;

  void _expandFor({bool forceMatched = false, bool forceUnmatched = false}) {
    setState(() {
      _expanded = true;
      _forceMatchedContinue = forceMatched;
      _forceUnmatchedContinue = forceUnmatched;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final title =
        transitionFieldById(widget.node.fieldId)?.displayName ??
        widget.node.fieldId;
    final matchedOutcome = _outcomeOf(widget.node.matchedBranch);
    final unmatchedOutcome = _outcomeOf(widget.node.unmatchedBranch);
    final matchedChild = _childOf(widget.node.matchedBranch);
    final unmatchedChild = _childOf(widget.node.unmatchedBranch);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GuideRailIndent(
          depth: widget.depth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _expanded
                  ? c.primarySubtle
                  : _hovered
                  ? c.surfaceHover
                  : const Color(0x00000000),
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hovered = true),
                  onExit: (_) => setState(() => _hovered = false),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _expanded
                        ? setState(() => _expanded = false)
                        : _expandFor(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AionSpacing.sp12,
                        AionSpacing.sp8,
                        AionSpacing.sp12,
                        AionSpacing.sp8,
                      ),
                      // §2.2's branch-word prefix abbreviates (`M`/`U`)
                      // below 360px of *pane* width — measured here via
                      // `LayoutBuilder`, the row's own available width,
                      // since that's what's actually cramped when the
                      // prefix needs to shrink.
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 360;
                          return Row(
                            children: [
                              AnimatedRotation(
                                turns: _expanded ? 0.25 : 0,
                                duration: const Duration(milliseconds: 140),
                                curve: Curves.easeOut,
                                child: PhosphorIcon(
                                  PhosphorIcons.caretRightLight,
                                  size: 14,
                                  color: _hovered
                                      ? c.textSecondary
                                      : c.textMuted,
                                ),
                              ),
                              const SizedBox(width: AionSpacing.sp8),
                              Flexible(
                                child: Text(
                                  title,
                                  style: AionText.cardTitle.copyWith(
                                    color: c.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Spacer(),
                              if (matchedOutcome != null)
                                _OutcomeBadge(
                                  outcome: matchedOutcome,
                                  matched: true,
                                  narrow: narrow,
                                ),
                              const SizedBox(width: AionSpacing.sp8),
                              if (unmatchedOutcome != null)
                                _OutcomeBadge(
                                  outcome: unmatchedOutcome,
                                  matched: false,
                                  narrow: narrow,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (_expanded)
                  TransitionNodeForm(
                    stage: widget.stage,
                    onDirtyChanged: widget.onDirtyChanged,
                    initialFieldId: widget.node.fieldId,
                    initialMatchedBranch: widget.node.matchedBranch,
                    initialUnmatchedBranch: widget.node.unmatchedBranch,
                    matchedChildFieldLabel: chainedChildFieldLabel(
                      widget.node.matchedBranch,
                      widget.nodesById,
                    ),
                    unmatchedChildFieldLabel: chainedChildFieldLabel(
                      widget.node.unmatchedBranch,
                      widget.nodesById,
                    ),
                    forceMatchedContinue: _forceMatchedContinue,
                    forceUnmatchedContinue: _forceUnmatchedContinue,
                    descendantCount:
                        descendantIdsOf(
                          widget.node.id,
                          widget.nodesById,
                        ).length -
                        1,
                    onSave: widget.onSave,
                    onCreateChainedChild: widget.onCreateChainedChild,
                    onCancel: () => setState(() => _expanded = false),
                    onDelete: widget.onDelete,
                  ),
              ],
            ),
          ),
        ),
        if (matchedChild != null)
          _BranchChild(
            matched: true,
            child: matchedChild,
            depth: widget.depth + 1,
            nodesById: widget.nodesById,
            stage: widget.stage,
            onCreateChainedChild: widget.onCreateChainedChild,
            onDirtyChanged: widget.onDirtyChanged,
          )
        else if (widget.node.matchedBranch is TerminalTransitionBranch)
          _GuideRailIndent(
            depth: widget.depth + 1,
            child: _AddFieldCheckAffordance(
              onTap: () => _expandFor(forceMatched: true),
            ),
          ),
        if (unmatchedChild != null)
          _BranchChild(
            matched: false,
            child: unmatchedChild,
            depth: widget.depth + 1,
            nodesById: widget.nodesById,
            stage: widget.stage,
            onCreateChainedChild: widget.onCreateChainedChild,
            onDirtyChanged: widget.onDirtyChanged,
          )
        else if (widget.node.unmatchedBranch is TerminalTransitionBranch)
          _GuideRailIndent(
            depth: widget.depth + 1,
            child: _AddFieldCheckAffordance(
              onTap: () => _expandFor(forceUnmatched: true),
            ),
          ),
      ],
    );
  }

  TransitionOutcome? _outcomeOf(TransitionBranch branch) =>
      branch is TerminalTransitionBranch ? branch.outcome : null;

  /// The branch's chained child node, or `null` if it's terminal — or if
  /// it's a [ToTransitionNodeBranch] whose target is missing from
  /// [_NodeRow.nodesById] (a dangling reference; rendered as nothing
  /// here, the same defensive treatment `evaluate_transition_graph.dart`
  /// gives it at evaluation time).
  TransitionNode? _childOf(TransitionBranch branch) => switch (branch) {
    ToTransitionNodeBranch(:final nodeId) => widget.nodesById[nodeId],
    TerminalTransitionBranch() => null,
  };
}

/// One chained child beneath a [_NodeRow] — a `MATCHED`/`UNMATCHED` branch
/// label preceding the child's own recursive [_NodeRow]. Mirrors
/// `_BranchChild` (`decision_outline_list.dart`).
class _BranchChild extends StatelessWidget {
  const _BranchChild({
    required this.matched,
    required this.child,
    required this.depth,
    required this.nodesById,
    required this.stage,
    required this.onCreateChainedChild,
    this.onDirtyChanged,
  });

  final bool matched;
  final TransitionNode child;
  final int depth;
  final Map<String, TransitionNode> nodesById;
  final SddStage stage;
  final Future<String?> Function(String fieldId) onCreateChainedChild;

  /// Forwarded to this child's own recursive [_NodeRow] — see
  /// [TransitionOutlineList.onDirtyChanged].
  final ValueChanged<bool>? onDirtyChanged;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GuideRailIndent(
          depth: depth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              matched
                  ? context.l10n.transitionPreconditionMatchedLabel
                        .toUpperCase()
                  : context.l10n.transitionPreconditionUnmatchedLabel
                        .toUpperCase(),
              style: AionText.caption.copyWith(
                color: matched ? c.primary : c.textMuted,
              ),
            ),
          ),
        ),
        _NodeRow(
          node: child,
          depth: depth,
          nodesById: nodesById,
          stage: stage,
          onDirtyChanged: onDirtyChanged,
          onDelete: () => context
              .read<TransitionPreconditionConfigCubit>()
              .deleteNode(child.id),
          onSave:
              ({
                required fieldId,
                required matchedBranch,
                required unmatchedBranch,
              }) {
                context.read<TransitionPreconditionConfigCubit>().updateNode(
                  child.copyWith(
                    fieldId: fieldId,
                    matchedBranch: matchedBranch,
                    unmatchedBranch: unmatchedBranch,
                  ),
                );
              },
          onCreateChainedChild: onCreateChainedChild,
        ),
      ],
    );
  }
}

/// The terminal-outcome badge trailing a [_NodeRow]. Mirrors
/// `_OutcomeBadge` (`decision_outline_list.dart`), plus design.md §2.2's
/// [TransitionOutcomeGlyph] and branch-word prefix (added for this
/// change's round-2 `/verify` follow-up — both were missing from the
/// original `/apply` pass).
class _OutcomeBadge extends StatelessWidget {
  const _OutcomeBadge({
    required this.outcome,
    required this.matched,
    required this.narrow,
  });

  final TransitionOutcome outcome;

  /// Whether this badge sits on the `matched` (vs. `unmatched`) branch —
  /// which branch-word prefix (§2.2) to show.
  final bool matched;

  /// Whether the pane is narrower than §2.2's `360`px threshold —
  /// abbreviates the branch-word prefix to `M`/`U`.
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final color = transitionOutcomeColor(c, outcome);
    final prefixColor = matched ? c.primary : c.textMuted;
    final prefixText = narrow
        ? (matched
              ? context.l10n.transitionPreconditionMatchedLabel[0]
              : context.l10n.transitionPreconditionUnmatchedLabel[0])
              .toUpperCase()
        : (matched
                  ? context.l10n.transitionPreconditionMatchedLabel
                  : context.l10n.transitionPreconditionUnmatchedLabel)
              .toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 1),
        borderRadius: BorderRadius.all(AionRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 9, 0),
        child: SizedBox(
          height: 24,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                prefixText,
                style: AionText.caption.copyWith(color: prefixColor),
              ),
              const SizedBox(width: 5),
              TransitionOutcomeGlyph(
                outcome: outcome,
                color: color,
                size: 10,
                checkStrokeWidth: 1.8,
                crossStrokeWidth: 1.4,
              ),
              const SizedBox(width: 5),
              Text(
                transitionOutcomeLabel(context, outcome),
                style: AionText.badgeLabel.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dashed "+ Add field check" affordance shown when a branch (or the
/// whole graph, when empty) currently terminates. Mirrors
/// `_AddConditionAffordance` (`decision_outline_list.dart`).
class _AddFieldCheckAffordance extends StatelessWidget {
  const _AddFieldCheckAffordance({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Semantics(
      button: true,
      label: context.l10n.transitionPreconditionAddFieldCheck,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: c.border, width: 1),
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                height: 32,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '+',
                      style: AionText.bodySm.copyWith(color: c.textMuted),
                    ),
                    const SizedBox(width: AionSpacing.sp8),
                    Text(
                      context.l10n.transitionPreconditionAddFieldCheck,
                      style: AionText.bodySm.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indents [child] by `24 * depth` and paints a 1px ancestor guide-rail
/// line at each intervening depth. Mirrors `_GuideRailIndent`
/// (`decision_outline_list.dart`).
class _GuideRailIndent extends StatelessWidget {
  const _GuideRailIndent({required this.depth, required this.child});

  final int depth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (depth == 0) return child;
    final c = ThemeScope.of(context).colors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var d = 0; d < depth; d++)
            SizedBox(
              width: 24,
              child: Center(child: Container(width: 1, color: c.border)),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
