// presentation/screens/decision_graph_editor_screen.dart — DecisionGraphEditorScreen dual-pane editor (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_state.dart';
import 'package:aion/features/providers/presentation/widgets/decision_node_form.dart';
import 'package:aion/features/providers/presentation/widgets/decision_outline_list.dart';

/// Localized per-[AutomationContext] title for [DecisionGraphEditorScreen]'s
/// header — module-private since this screen is its only consumer.
String decisionGraphContextTitle(
  BuildContext context,
  AutomationContext automationContext,
) => switch (automationContext) {
  AutomationContext.sddStage => context.l10n.decisionGraphContextTitleSddStage,
  AutomationContext.codingExecution =>
    context.l10n.decisionGraphContextTitleCodingExecution,
  AutomationContext.codingExecutionRetry =>
    context.l10n.decisionGraphContextTitleCodingExecutionRetry,
  AutomationContext.chatBranching =>
    context.l10n.decisionGraphContextTitleChatBranching,
  AutomationContext.codingExecutionResume =>
    context.l10n.decisionGraphContextTitleCodingExecutionResume,
  AutomationContext.ticketCreation =>
    context.l10n.decisionGraphContextTitleTicketCreation,
  AutomationContext.ticketLinking =>
    context.l10n.decisionGraphContextTitleTicketLinking,
  AutomationContext.specAutoLink =>
    context.l10n.decisionGraphContextTitleSpecAutoLink,
};

/// One node datum rendered by this screen's [GraphCanvas] instance —
/// either the graph's single condition node, or one of its two terminal
/// outcome pills. `GraphCanvas` itself has no knowledge of either shape;
/// this type exists purely so [_CanvasNodeContent] can switch on it.
sealed class _CanvasNode {
  const _CanvasNode();
}

class _ConditionCanvasNode extends _CanvasNode {
  const _ConditionCanvasNode(this.node, this.spec);
  final DecisionNode node;
  final DecisionConditionSpec? spec;
}

class _TerminalCanvasNode extends _CanvasNode {
  const _TerminalCanvasNode(this.outcome);
  final DecisionOutcome outcome;
}

/// Route `/workspace/settings/automation/:context/graph` — the dual-pane
/// decision-graph editor for one [AutomationContext]: `GraphCanvas`
/// (default/left) and [DecisionOutlineList] (right), both bound to the
/// same [DecisionGraphConfigCubit] so a selection or edit in either pane
/// is reflected in the other. Reached from `SettingsScreen`'s
/// `_AutomationSection` "Configure decision graph" affordance. Added for
/// `aion-arch/changes/automation-decision-graphs`; see that change's
/// design.md §4/§5. (`/verify` fix pass — the canvas pane previously only
/// ever rendered the root node plus its two direct terminal branches, and
/// node-tap only selected rather than opening `DecisionNodeForm
/// .showAsPopover`; see `_CanvasPane`'s own dartdoc.)
class DecisionGraphEditorScreen extends StatefulWidget {
  /// Creates a [DecisionGraphEditorScreen] for [automationContext].
  const DecisionGraphEditorScreen({super.key, required this.automationContext});

  /// Which [AutomationContext] this screen edits.
  final AutomationContext automationContext;

  @override
  State<DecisionGraphEditorScreen> createState() =>
      _DecisionGraphEditorScreenState();
}

class _DecisionGraphEditorScreenState extends State<DecisionGraphEditorScreen> {
  String? _selectedCanvasId;

  @override
  void initState() {
    super.initState();
    context.read<DecisionGraphConfigCubit>().load(widget.automationContext);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          _Header(automationContext: widget.automationContext),
          Expanded(
            child:
                BlocBuilder<DecisionGraphConfigCubit, DecisionGraphConfigState>(
                  builder: (context, state) {
                    final loaded = switch (state) {
                      DecisionGraphConfigLoaded loaded => loaded,
                      DecisionGraphConfigError(:final previous) => previous,
                      DecisionGraphConfigInitial() => null,
                    };
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: loaded == null
                              ? const Center(child: AppSpinner())
                              : _CanvasPane(
                                  automationContext: widget.automationContext,
                                  loaded: loaded,
                                  selectedId: _selectedCanvasId,
                                  onSelect: (id) =>
                                      setState(() => _selectedCanvasId = id),
                                ),
                        ),
                        SizedBox(width: 1, child: ColoredBox(color: c.border)),
                        SizedBox(
                          width: 420,
                          child: ColoredBox(
                            color: c.surface,
                            child: DecisionOutlineList(
                              automationContext: widget.automationContext,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

/// The 72px header: back button, eyebrow + title, and a "reset to always
/// proceed" action. Per design.md §4.1.
class _Header extends StatelessWidget {
  const _Header({required this.automationContext});

  final AutomationContext automationContext;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AionSpacing.sp20),
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Semantics(
                button: true,
                label: context.l10n.commonBack,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surfaceHover,
                        border: Border.all(color: c.border, width: 1),
                        borderRadius: BorderRadius.all(AionRadius.iconBtn),
                      ),
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: Center(
                          child: PhosphorIcon(
                            PhosphorIcons.caretLeftLight,
                            size: 16,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AionSpacing.sp12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.settingsAutomationEyebrow,
                      style: AionText.caption.copyWith(color: c.textMuted),
                    ),
                    Text(
                      decisionGraphContextTitle(context, automationContext),
                      style: AionText.h2.copyWith(color: c.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppButton(
                label: context.l10n.decisionGraphResetButton,
                variant: AppButtonVariant.ghost,
                onPressed: () =>
                    context.read<DecisionGraphConfigCubit>().setRoot(null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The canvas pane's content: converts [loaded]'s whole reachable graph
/// (not just its root) into [GraphCanvas] nodes/edges — recursively
/// walking every [ToNodeBranch], auto-laid-out per design.md §1.1
/// (depth → y, in-order index → x) — or [GraphCanvas.emptyState] when
/// there's no root yet. Tapping a condition node opens it for editing via
/// [DecisionNodeForm.showAsPopover], anchored to a per-node [LayerLink]
/// this widget owns (so the link survives rebuilds while a popover is
/// open) and bound to [DecisionGraphConfigCubit] at tap time, from a
/// context that's still safely inside the route's `BlocProvider` — the
/// popover's own [OverlayEntry] renders from the app's root `Overlay`,
/// outside that subtree, so it can't safely `context.read` the cubit
/// itself (see [DecisionNodeForm.showAsPopover]'s own dartdoc). Added for
/// `aion-arch/changes/automation-decision-graphs`; `/verify` fix pass —
/// previously this only ever positioned the root node plus its two direct
/// terminal branches, and node-tap only selected rather than editing.
class _CanvasPane extends StatefulWidget {
  const _CanvasPane({
    required this.automationContext,
    required this.loaded,
    required this.selectedId,
    required this.onSelect,
  });

  final AutomationContext automationContext;
  final DecisionGraphConfigLoaded loaded;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<_CanvasPane> createState() => _CanvasPaneState();
}

class _CanvasPaneState extends State<_CanvasPane> {
  final Map<String, LayerLink> _links = {};

  LayerLink _linkFor(String nodeId) =>
      _links.putIfAbsent(nodeId, LayerLink.new);

  @override
  Widget build(BuildContext context) {
    final rootId = widget.loaded.graph.rootNodeId;
    final rootNode = rootId == null ? null : widget.loaded.nodesById[rootId];

    if (rootNode == null) {
      return GraphCanvas<_CanvasNode>(
        nodes: const [],
        edges: const [],
        nodeBuilder: (context, data, selected) => const SizedBox.shrink(),
        emptyState: const _EmptyGraphState(),
      );
    }

    final layout = _TreeLayout(widget.loaded.nodesById)
      ..layout(rootNode, 0);

    return GraphCanvas<_CanvasNode>(
      nodes: layout.nodes,
      edges: layout.edges,
      selectedId: widget.selectedId,
      onNodeTap: (id) => _handleTap(context, id),
      nodeBuilder: (context, data, selected) => switch (data) {
        _ConditionCanvasNode(:final node) => CompositedTransformTarget(
          link: _linkFor(node.id),
          child: _CanvasNodeContent(data: data, selected: selected),
        ),
        _TerminalCanvasNode() => _CanvasNodeContent(
          data: data,
          selected: selected,
        ),
      },
    );
  }

  /// Selects [id]; additionally opens [DecisionNodeForm.showAsPopover]
  /// when [id] resolves to a condition node (a terminal pill tap only
  /// selects — the owning condition node's own row/canvas box is still
  /// reachable to edit that branch).
  void _handleTap(BuildContext context, String id) {
    widget.onSelect(id);
    final node = widget.loaded.nodesById[id];
    if (node == null) return;

    final cubit = context.read<DecisionGraphConfigCubit>();
    DecisionNodeForm.showAsPopover(
      context,
      link: _linkFor(id),
      automationContext: widget.automationContext,
      initialConditionId: node.conditionId,
      initialConditionParams: node.conditionParams,
      initialMatchedBranch: node.matchedBranch,
      initialUnmatchedBranch: node.unmatchedBranch,
      matchedChildConditionLabel: chainedChildConditionLabel(
        node.matchedBranch,
        widget.loaded.nodesById,
      ),
      unmatchedChildConditionLabel: chainedChildConditionLabel(
        node.unmatchedBranch,
        widget.loaded.nodesById,
      ),
      onSave:
          ({
            required conditionId,
            required conditionParams,
            required matchedBranch,
            required unmatchedBranch,
          }) {
            cubit.updateNode(
              node.copyWith(
                conditionId: conditionId,
                conditionParams: conditionParams,
                matchedBranch: matchedBranch,
                unmatchedBranch: unmatchedBranch,
              ),
            );
          },
      onCreateChainedChild: (conditionId) {
        final spec = decisionConditionSpecById(conditionId);
        return cubit.createNode(
          conditionId: conditionId,
          conditionParams: spec == null
              ? const {}
              : defaultConditionParams(spec),
        );
      },
      onDelete: () => cubit.deleteNode(node.id),
    );
  }
}

/// Lays out one [DecisionGraphConfigLoaded] graph's whole reachable tree
/// for [GraphCanvas], per design.md §1.1: depth → y (152px per level),
/// an in-order traversal (matched subtree, self, unmatched subtree) → x
/// (296px per slot) for condition nodes. A branch's terminal pill (when
/// it doesn't continue to another condition) is positioned directly
/// beneath its parent's own anchor rather than consuming its own
/// in-order slot, per design.md §1.3 ("terminals are positioned by their
/// parent's branch anchor"). A dangling [ToNodeBranch] (target missing
/// from `nodesById`) renders nothing for that branch — the same
/// defensive treatment `decision_graph_evaluator.dart` gives it at
/// evaluation time. Added for `aion-arch/changes/automation-decision-graphs`
/// (`/verify` fix pass).
class _TreeLayout {
  _TreeLayout(this._nodesById);

  final Map<String, DecisionNode> _nodesById;
  final List<GraphCanvasNode<_CanvasNode>> nodes = [];
  final List<GraphCanvasEdge> edges = [];
  int _slot = 0;

  static const double _slotWidth = 296;
  static const double _levelHeight = 152;
  static const double _terminalWidth = 150;

  /// Lays out [node] and its whole reachable subtree rooted at [depth],
  /// returning the x-coordinate [node] itself was placed at (so a caller
  /// one level up can route an edge into it).
  double layout(DecisionNode node, int depth) {
    double? matchedChildX;
    if (node.matchedBranch case ToNodeBranch(:final nodeId)) {
      final child = _nodesById[nodeId];
      if (child != null) matchedChildX = layout(child, depth + 1);
    }

    final x = (_slot * _slotWidth) + 40;
    _slot++;
    final y = (depth * _levelHeight) + 40;
    final spec = decisionConditionSpecById(node.conditionId);
    nodes.add(
      GraphCanvasNode(
        id: node.id,
        position: Offset(x, y),
        data: _ConditionCanvasNode(node, spec),
      ),
    );

    _layoutBranch(
      matched: true,
      parentId: node.id,
      parentX: x,
      parentY: y,
      branch: node.matchedBranch,
      childX: matchedChildX,
    );

    double? unmatchedChildX;
    if (node.unmatchedBranch case ToNodeBranch(:final nodeId)) {
      final child = _nodesById[nodeId];
      if (child != null) unmatchedChildX = layout(child, depth + 1);
    }
    _layoutBranch(
      matched: false,
      parentId: node.id,
      parentX: x,
      parentY: y,
      branch: node.unmatchedBranch,
      childX: unmatchedChildX,
    );

    return x;
  }

  void _layoutBranch({
    required bool matched,
    required String parentId,
    required double parentX,
    required double parentY,
    required DecisionBranch branch,
    required double? childX,
  }) {
    switch (branch) {
      case ToNodeBranch(:final nodeId):
        // Only route the edge if the child actually got laid out —
        // `childX` is null for a dangling reference (target missing
        // from `_nodesById`), which this defensively renders as nothing.
        if (childX != null) {
          edges.add(
            GraphCanvasEdge(
              fromId: parentId,
              toId: nodeId,
              dashed: !matched,
              muted: !matched,
            ),
          );
        }
      case TerminalBranch(:final outcome):
        final terminalId = '$parentId-${matched ? 'matched' : 'unmatched'}';
        nodes.add(
          GraphCanvasNode(
            id: terminalId,
            position: Offset(
              matched ? parentX - 72 : parentX + 132,
              parentY + 152,
            ),
            size: const Size(_terminalWidth, 36),
            data: _TerminalCanvasNode(outcome),
          ),
        );
        edges.add(
          GraphCanvasEdge(
            fromId: parentId,
            toId: terminalId,
            dashed: !matched,
            muted: !matched,
          ),
        );
    }
  }
}

/// Renders one [_CanvasNode]'s content — a condition box (design.md
/// §1.2) or a terminal outcome pill (§1.3).
class _CanvasNodeContent extends StatelessWidget {
  const _CanvasNodeContent({required this.data, required this.selected});

  final _CanvasNode data;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return switch (data) {
      _ConditionCanvasNode(:final spec) => DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(
            color: selected ? c.primary : c.border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.all(AionRadius.lg),
          boxShadow: AionShadows.card(c, ThemeScope.of(context).isDark),
        ),
        child: SizedBox(
          width: 264,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.decisionGraphConditionPickerLabel.toUpperCase(),
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: 5),
                Text(
                  spec?.displayName ?? '',
                  style: AionText.cardTitle.copyWith(color: c.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
      _TerminalCanvasNode(:final outcome) => DecoratedBox(
        decoration: BoxDecoration(
          color: decisionOutcomeColor(c, outcome).withValues(alpha: 0.14),
          border: Border.all(
            color: decisionOutcomeColor(c, outcome).withValues(alpha: 0.32),
            width: 1,
          ),
          borderRadius: BorderRadius.all(AionRadius.pill),
        ),
        child: SizedBox(
          width: 150,
          height: 36,
          child: Center(
            child: Text(
              decisionOutcomeLabel(context, outcome),
              style: AionText.badgeLabel.copyWith(
                color: decisionOutcomeColor(c, outcome),
              ),
            ),
          ),
        ),
      ),
    };
  }
}

/// The canvas's empty-graph placeholder, shown when the context has no
/// configured decision graph. Per design.md §1.7.
class _EmptyGraphState extends StatelessWidget {
  const _EmptyGraphState();

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.all(AionRadius.xl),
        border: Border.all(color: c.borderStrong, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AionSpacing.sp24),
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.decisionGraphEmptyStateEyebrow,
                style: AionText.caption.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.decisionGraphEmptyStateHeadline,
                style: AionText.dialogTitle.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.decisionGraphEmptyStateBody,
                style: AionText.bodySm.copyWith(
                  color: c.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
