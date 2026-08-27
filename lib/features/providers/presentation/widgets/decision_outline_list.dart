// presentation/widgets/decision_outline_list.dart — DecisionOutlineList nested-outline pane (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_state.dart';
import 'package:aion/features/providers/presentation/widgets/decision_node_form.dart';

/// The outline pane of `DecisionGraphEditorScreen`: one row per
/// `DecisionNode` (condition name, parameter chip, and its two branches'
/// outcome badges), children of a chained branch rendered as their own
/// indented row beneath it (recursively, no depth cap), plus a dashed
/// "+ Add condition" affordance when the graph has no root yet.
/// Reads/writes through [DecisionGraphConfigCubit] — the same source of
/// truth `GraphCanvas` renders from, so a selection or edit in either
/// pane is reflected in the other via the same [DecisionGraphConfigState].
/// Added for `aion-arch/changes/automation-decision-graphs`; see that
/// change's design.md §2. (`/verify` fix pass — this pane previously only
/// ever rendered the graph's root node, since `DecisionNodeForm` had no
/// way to author a chained branch; see that form's own dartdoc.)
class DecisionOutlineList extends StatefulWidget {
  /// Creates a [DecisionOutlineList] for [automationContext].
  const DecisionOutlineList({super.key, required this.automationContext});

  /// Which [AutomationContext] this pane edits.
  final AutomationContext automationContext;

  @override
  State<DecisionOutlineList> createState() => _DecisionOutlineListState();
}

class _DecisionOutlineListState extends State<DecisionOutlineList> {
  bool _formExpanded = false;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return BlocConsumer<DecisionGraphConfigCubit, DecisionGraphConfigState>(
      listener: (context, state) {
        if (state is DecisionGraphConfigLoaded) {
          setState(() => _formExpanded = false);
        }
      },
      builder: (context, state) {
        final loaded = switch (state) {
          DecisionGraphConfigLoaded loaded => loaded,
          DecisionGraphConfigError(:final previous) => previous,
          DecisionGraphConfigInitial() => null,
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
                    context.l10n.decisionGraphOutlineHeader(
                      rootNode == null ? 0 : 1,
                    ),
                    style: AionText.caption.copyWith(color: c.textMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AionSpacing.sp8),
            // The header above stays pinned; only the tree body scrolls —
            // design.md §2's "Column inside a scroll view" (this pane has
            // no fixed row height/lazy-building need, so a
            // `SingleChildScrollView` is a plain equivalent to the spec's
            // `CustomScrollView` + `SliverList`). Missing entirely before
            // `/verify` fix pass 2 — a graph tall enough to exceed the
            // pane's height had no way to see the rest of the tree.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state is DecisionGraphConfigError)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AionSpacing.sp12,
                        ),
                        child: Text(
                          _errorMessage(context, state.reason),
                          style: AionText.bodySm.copyWith(color: c.danger),
                        ),
                      ),
                    if (rootNode != null)
                      _NodeRow(
                        node: rootNode,
                        depth: 0,
                        nodesById: loaded.nodesById,
                        onDelete: () => context
                            .read<DecisionGraphConfigCubit>()
                            .deleteNode(rootNode.id),
                        onSave:
                            ({
                              required conditionId,
                              required conditionParams,
                              required matchedBranch,
                              required unmatchedBranch,
                            }) {
                              context
                                  .read<DecisionGraphConfigCubit>()
                                  .updateNode(
                                    rootNode.copyWith(
                                      conditionId: conditionId,
                                      conditionParams: conditionParams,
                                      matchedBranch: matchedBranch,
                                      unmatchedBranch: unmatchedBranch,
                                    ),
                                  );
                            },
                        onCreateChainedChild: _createChainedChild,
                        automationContext: widget.automationContext,
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
                          child: DecisionNodeForm(
                            automationContext: widget.automationContext,
                            onSave:
                                ({
                                  required conditionId,
                                  required conditionParams,
                                  required matchedBranch,
                                  required unmatchedBranch,
                                }) async {
                                  final cubit = context
                                      .read<DecisionGraphConfigCubit>();
                                  final newNodeId = await cubit.createNode(
                                    conditionId: conditionId,
                                    conditionParams: conditionParams,
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
                        child: _AddConditionAffordance(
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

  String _errorMessage(
    BuildContext context,
    DecisionGraphConfigErrorReason reason,
  ) => switch (reason) {
    DecisionGraphConfigErrorReason.nodeNotFound =>
      context.l10n.decisionGraphErrorNodeNotFound,
    DecisionGraphConfigErrorReason.danglingBranchTarget =>
      context.l10n.decisionGraphErrorDanglingBranchTarget,
    DecisionGraphConfigErrorReason.duplicateChildReference =>
      context.l10n.decisionGraphErrorDuplicateChildReference,
    DecisionGraphConfigErrorReason.cycleDetected =>
      context.l10n.decisionGraphErrorCycleDetected,
  };

  /// [DecisionNodeForm.onCreateChainedChild]'s implementation for this
  /// pane: creates a fresh [DecisionNode] for [conditionId], its
  /// parameters seeded via `defaultConditionParams`, and its own two
  /// branches defaulting to terminal `gated`/`proceed` — the same shape
  /// [DecisionGraphConfigCubit.createNode] already defaults a brand-new
  /// node to.
  Future<String?> _createChainedChild(String conditionId) {
    final spec = decisionConditionSpecById(conditionId);
    return context.read<DecisionGraphConfigCubit>().createNode(
      conditionId: conditionId,
      conditionParams: spec == null ? const {} : defaultConditionParams(spec),
    );
  }
}

/// One row: condition title + parameter chip, trailing matched/unmatched
/// outcome badges (for whichever branches currently terminate),
/// expand-in-place to a [DecisionNodeForm] on tap — mirrors
/// `WorkflowStatusSettingsScreen`'s `_AddStatusControl` interaction
/// shape. A branch that instead continues to a chained child node
/// renders that child as its own indented [_NodeRow] beneath this one
/// (recursively, via [_BranchChild]) — no depth cap, matching design.md
/// §2's nested-outline shape.
class _NodeRow extends StatefulWidget {
  const _NodeRow({
    required this.node,
    required this.depth,
    required this.nodesById,
    required this.automationContext,
    required this.onSave,
    required this.onDelete,
    required this.onCreateChainedChild,
  });

  final DecisionNode node;
  final int depth;

  /// Every node reachable from the graph's root — used to resolve a
  /// chained branch's child (for the recursive [_BranchChild] rows and
  /// [DecisionNodeForm]'s `...ChildConditionLabel`).
  final Map<String, DecisionNode> nodesById;
  final AutomationContext automationContext;
  final void Function({
    required String conditionId,
    required Map<String, dynamic> conditionParams,
    required DecisionBranch matchedBranch,
    required DecisionBranch unmatchedBranch,
  })
  onSave;
  final VoidCallback onDelete;
  final Future<String?> Function(String conditionId) onCreateChainedChild;

  @override
  State<_NodeRow> createState() => _NodeRowState();
}

class _NodeRowState extends State<_NodeRow> {
  bool _expanded = false;
  bool _hovered = false;

  /// Set (and consumed once) when a per-branch "+ Add condition"
  /// affordance (design.md §2.3) is tapped, forcing that branch's mode
  /// straight to "Continue to condition" when the form expands — see
  /// [DecisionNodeForm.forceMatchedContinue]/`.forceUnmatchedContinue`.
  /// Added for `aion-arch/changes/automation-decision-graphs` (`/verify`
  /// fix pass 2).
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
    final spec = decisionConditionSpecById(widget.node.conditionId);
    final parameterSummary = spec == null
        ? null
        : conditionParameterSummary(spec, widget.node.conditionParams);
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
                      child: Row(
                        children: [
                          AnimatedRotation(
                            turns: _expanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOut,
                            child: PhosphorIcon(
                              PhosphorIcons.caretRightLight,
                              size: 14,
                              color: _hovered ? c.textSecondary : c.textMuted,
                            ),
                          ),
                          const SizedBox(width: AionSpacing.sp8),
                          Flexible(
                            child: Text(
                              spec?.displayName ?? widget.node.conditionId,
                              style: AionText.cardTitle.copyWith(
                                color: c.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (parameterSummary != null) ...[
                            const SizedBox(width: AionSpacing.sp8),
                            _ParameterChip(text: parameterSummary),
                          ],
                          const Spacer(),
                          if (matchedOutcome != null)
                            _OutcomeBadge(outcome: matchedOutcome),
                          const SizedBox(width: AionSpacing.sp8),
                          if (unmatchedOutcome != null)
                            _OutcomeBadge(outcome: unmatchedOutcome),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_expanded)
                  DecisionNodeForm(
                    automationContext: widget.automationContext,
                    initialConditionId: widget.node.conditionId,
                    initialConditionParams: widget.node.conditionParams,
                    initialMatchedBranch: widget.node.matchedBranch,
                    initialUnmatchedBranch: widget.node.unmatchedBranch,
                    matchedChildConditionLabel: chainedChildConditionLabel(
                      widget.node.matchedBranch,
                      widget.nodesById,
                    ),
                    unmatchedChildConditionLabel: chainedChildConditionLabel(
                      widget.node.unmatchedBranch,
                      widget.nodesById,
                    ),
                    forceMatchedContinue: _forceMatchedContinue,
                    forceUnmatchedContinue: _forceUnmatchedContinue,
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
            automationContext: widget.automationContext,
            onCreateChainedChild: widget.onCreateChainedChild,
          )
        else if (widget.node.matchedBranch is TerminalBranch)
          _GuideRailIndent(
            depth: widget.depth + 1,
            child: _AddConditionAffordance(
              onTap: () => _expandFor(forceMatched: true),
            ),
          ),
        if (unmatchedChild != null)
          _BranchChild(
            matched: false,
            child: unmatchedChild,
            depth: widget.depth + 1,
            nodesById: widget.nodesById,
            automationContext: widget.automationContext,
            onCreateChainedChild: widget.onCreateChainedChild,
          )
        else if (widget.node.unmatchedBranch is TerminalBranch)
          _GuideRailIndent(
            depth: widget.depth + 1,
            child: _AddConditionAffordance(
              onTap: () => _expandFor(forceUnmatched: true),
            ),
          ),
      ],
    );
  }

  DecisionOutcome? _outcomeOf(DecisionBranch branch) =>
      branch is TerminalBranch ? branch.outcome : null;

  /// The branch's chained child node, or `null` if it's terminal — or if
  /// it's a [ToNodeBranch] whose target is missing from [_NodeRow
  /// .nodesById] (a dangling reference; rendered as nothing here, the
  /// same defensive treatment `decision_graph_evaluator.dart` gives it at
  /// evaluation time).
  DecisionNode? _childOf(DecisionBranch branch) => switch (branch) {
    ToNodeBranch(:final nodeId) => widget.nodesById[nodeId],
    TerminalBranch() => null,
  };
}

/// One chained child beneath a [_NodeRow] — the design.md §2.1 "Branch
/// label" (`MATCHED`/`UNMATCHED`) preceding the child's own recursive
/// [_NodeRow]. The child row owns its own save/delete wiring (via
/// `context.read<DecisionGraphConfigCubit>()`), since — unlike its
/// parent — nothing above it already built those closures.
class _BranchChild extends StatelessWidget {
  const _BranchChild({
    required this.matched,
    required this.child,
    required this.depth,
    required this.nodesById,
    required this.automationContext,
    required this.onCreateChainedChild,
  });

  final bool matched;
  final DecisionNode child;
  final int depth;
  final Map<String, DecisionNode> nodesById;
  final AutomationContext automationContext;
  final Future<String?> Function(String conditionId) onCreateChainedChild;

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
                  ? context.l10n.decisionGraphMatchedLabel.toUpperCase()
                  : context.l10n.decisionGraphUnmatchedLabel.toUpperCase(),
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
          automationContext: automationContext,
          onDelete: () =>
              context.read<DecisionGraphConfigCubit>().deleteNode(child.id),
          onSave:
              ({
                required conditionId,
                required conditionParams,
                required matchedBranch,
                required unmatchedBranch,
              }) {
                context.read<DecisionGraphConfigCubit>().updateNode(
                  child.copyWith(
                    conditionId: conditionId,
                    conditionParams: conditionParams,
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

/// The terminal-outcome badge trailing a [_NodeRow] — per design.md §2.2.
class _OutcomeBadge extends StatelessWidget {
  const _OutcomeBadge({required this.outcome});

  final DecisionOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final color = decisionOutcomeColor(c, outcome);
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
                decisionOutcomeLabel(context, outcome),
                style: AionText.badgeLabel.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dashed "+ Add condition" affordance shown when a branch (or the
/// whole graph, when empty) currently terminates. Per design.md §2.3.
class _AddConditionAffordance extends StatelessWidget {
  const _AddConditionAffordance({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Semantics(
      button: true,
      label: context.l10n.decisionGraphAddCondition,
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
                      context.l10n.decisionGraphAddCondition,
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

/// Indents [child] by `24 * depth` (design.md §2.1's per-level indent) and
/// paints a 1px ancestor guide-rail line at each intervening depth —
/// `x = 24 * d + 19` relative to this row's own left edge, full row
/// height. Shared by [_NodeRow] and [_BranchChild] so the rail lines up
/// identically for a row's own content and its `MATCHED`/`UNMATCHED`
/// label. Added for `aion-arch/changes/automation-decision-graphs`
/// (`/verify` fix pass 2).
class _GuideRailIndent extends StatelessWidget {
  const _GuideRailIndent({required this.depth, required this.child});

  final int depth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (depth == 0) return child;
    final c = ThemeScope.of(context).colors;
    // `CrossAxisAlignment.stretch` needs a bounded height to stretch the
    // rail lines into — this row sits inside an unconstrained-height
    // `Column`, so without `IntrinsicHeight` the incoming height
    // constraint is infinite and `stretch` throws
    // ("BoxConstraints forces an infinite height").
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

/// The row chrome's parameter-summary chip (design.md §1.2/§2.1
/// "Parameter chip") — e.g. `> 3`. Mirrors
/// `DecisionGraphEditorScreen`'s own private `_ParameterChip` (not
/// shared across files, consistent with this codebase's existing
/// per-file small-private-widget convention). Added for
/// `aion-arch/changes/automation-decision-graphs` (`/verify` fix pass 2).
class _ParameterChip extends StatelessWidget {
  const _ParameterChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceHover,
        borderRadius: BorderRadius.all(AionRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
        child: Text(text, style: AionText.key.copyWith(color: c.textSecondary)),
      ),
    );
  }
}
