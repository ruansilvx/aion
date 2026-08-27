// presentation/widgets/decision_outline_list.dart — DecisionOutlineList nested-outline pane (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_state.dart';
import 'package:aion/features/providers/presentation/widgets/decision_node_form.dart';

/// The outline pane of `DecisionGraphEditorScreen`: one row per
/// `DecisionNode` (condition name, parameter chip, and its two branches'
/// outcome badges), plus a dashed "+ Add condition" affordance when the
/// graph has no root yet. Reads/writes through
/// [DecisionGraphConfigCubit] — the same source of truth `GraphCanvas`
/// renders from, so a selection or edit in either pane is reflected in
/// the other via the same [DecisionGraphConfigState].
///
/// This slice's shipped condition catalog has exactly one entry per
/// applicable [AutomationContext] and this form only ever authors
/// terminal outcomes (see [DecisionNodeForm]'s own dartdoc), so the tree
/// this pane renders is at most one level deep — the "nested, nested
/// outline" indentation design.md §2 describes for a multi-level tree
/// has no case to exercise yet in this shipped slice, but the row/indent
/// plumbing below is written generically so a future catalog with
/// chainable conditions doesn't need this file rewritten. Added for
/// `aion-arch/changes/automation-decision-graphs`; see that change's
/// design.md §2.
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
                onDelete: () => context
                    .read<DecisionGraphConfigCubit>()
                    .deleteNode(rootNode.id),
                onSave:
                    ({
                      required conditionId,
                      required conditionParams,
                      required matchedOutcome,
                      required unmatchedOutcome,
                    }) {
                      context.read<DecisionGraphConfigCubit>().updateNode(
                        rootNode.copyWith(
                          conditionId: conditionId,
                          conditionParams: conditionParams,
                          matchedBranch: DecisionBranch.terminal(
                            matchedOutcome,
                          ),
                          unmatchedBranch: DecisionBranch.terminal(
                            unmatchedOutcome,
                          ),
                        ),
                      );
                    },
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
                          required matchedOutcome,
                          required unmatchedOutcome,
                        }) async {
                          final cubit = context
                              .read<DecisionGraphConfigCubit>();
                          final newNodeId = await cubit.createNode(
                            conditionId: conditionId,
                            conditionParams: conditionParams,
                            matchedBranch: DecisionBranch.terminal(
                              matchedOutcome,
                            ),
                            unmatchedBranch: DecisionBranch.terminal(
                              unmatchedOutcome,
                            ),
                          );
                          if (newNodeId != null) {
                            await cubit.setRoot(newNodeId);
                          }
                        },
                    onCancel: () => setState(() => _formExpanded = false),
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
}

/// One row: condition title + parameter chip, trailing matched/unmatched
/// outcome badges, expand-in-place to a [DecisionNodeForm] on tap —
/// mirrors `WorkflowStatusSettingsScreen`'s `_AddStatusControl`
/// interaction shape.
class _NodeRow extends StatefulWidget {
  const _NodeRow({
    required this.node,
    required this.depth,
    required this.automationContext,
    required this.onSave,
    required this.onDelete,
  });

  final DecisionNode node;
  final int depth;
  final AutomationContext automationContext;
  final void Function({
    required String conditionId,
    required Map<String, dynamic> conditionParams,
    required DecisionOutcome matchedOutcome,
    required DecisionOutcome unmatchedOutcome,
  })
  onSave;
  final VoidCallback onDelete;

  @override
  State<_NodeRow> createState() => _NodeRowState();
}

class _NodeRowState extends State<_NodeRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final spec = decisionConditionCatalog
        .where((s) => s.id == widget.node.conditionId)
        .firstOrNull;
    final matchedOutcome = _outcomeOf(widget.node.matchedBranch);
    final unmatchedOutcome = _outcomeOf(widget.node.unmatchedBranch);

    return Padding(
      padding: EdgeInsets.only(left: 24.0 * widget.depth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _expanded ? c.primarySubtle : const Color(0x00000000),
          borderRadius: BorderRadius.all(AionRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AionSpacing.sp12,
                  AionSpacing.sp8,
                  AionSpacing.sp12,
                  AionSpacing.sp8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        spec?.displayName ?? widget.node.conditionId,
                        style: AionText.cardTitle.copyWith(
                          color: c.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (matchedOutcome != null)
                      _OutcomeBadge(outcome: matchedOutcome),
                    const SizedBox(width: AionSpacing.sp8),
                    if (unmatchedOutcome != null)
                      _OutcomeBadge(outcome: unmatchedOutcome),
                  ],
                ),
              ),
            ),
            if (_expanded)
              DecisionNodeForm(
                automationContext: widget.automationContext,
                initialConditionId: widget.node.conditionId,
                initialConditionParams: widget.node.conditionParams,
                initialMatchedOutcome: matchedOutcome ?? DecisionOutcome.gated,
                initialUnmatchedOutcome:
                    unmatchedOutcome ?? DecisionOutcome.proceed,
                onSave: widget.onSave,
                onCancel: () => setState(() => _expanded = false),
                onDelete: widget.onDelete,
              ),
          ],
        ),
      ),
    );
  }

  DecisionOutcome? _outcomeOf(DecisionBranch branch) =>
      branch is TerminalBranch ? branch.outcome : null;
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
