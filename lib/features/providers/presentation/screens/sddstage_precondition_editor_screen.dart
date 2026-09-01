// presentation/screens/sddstage_precondition_editor_screen.dart — SddStagePreconditionEditorScreen dual-pane editor (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/presentation/cubit/transition_precondition_config_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/transition_precondition_config_state.dart';
import 'package:aion/features/providers/presentation/widgets/transition_node_form.dart';
import 'package:aion/features/providers/presentation/widgets/transition_outline_list.dart';
import 'package:aion/features/tickets/tickets.dart';

/// [stage]'s display label for this screen's header/root-marker/empty
/// state — reuses `_SddStageSection`'s own tracker-node wording
/// (`ticket_metadata_section.dart`) so the two surfaces never disagree.
/// Module-private since this screen is its only consumer here.
String sddStagePreconditionStageLabel(BuildContext context, SddStage stage) =>
    switch (stage) {
      SddStage.exploring => context.l10n.ticketDetailSddStageExplore,
      SddStage.proposed => context.l10n.ticketDetailSddStageProposed,
      SddStage.designBrief => context.l10n.ticketDetailSddStageDesignBrief,
      SddStage.designSync => context.l10n.ticketDetailSddStageDesignSync,
      SddStage.verifying => context.l10n.ticketDetailSddStageVerify,
      SddStage.archived => context.l10n.ticketDetailSddStageArchive,
    };

/// One node datum rendered by this screen's [GraphCanvas] instance —
/// either a field-check node, or one of its two terminal outcome pills.
/// `GraphCanvas` itself has no knowledge of either shape; this type
/// exists purely so [_CanvasNodeContent] can switch on it. Mirrors
/// `_CanvasNode` (`decision_graph_editor_screen.dart`).
sealed class _CanvasNode {
  const _CanvasNode();
}

class _FieldCheckCanvasNode extends _CanvasNode {
  const _FieldCheckCanvasNode(
    this.node, {
    required this.isRoot,
    required this.isError,
  });
  final TransitionNode node;

  /// Whether this node is the graph's `rootNodeId` — drives the root-
  /// marker chip.
  final bool isRoot;

  /// Whether this node is invalid: `node.fieldId` doesn't resolve via
  /// `transitionFieldById`, or either branch is a dangling
  /// [ToTransitionNodeBranch] whose target is missing from the loaded
  /// node set.
  final bool isError;
}

class _TerminalCanvasNode extends _CanvasNode {
  const _TerminalCanvasNode(this.outcome);
  final TransitionOutcome outcome;
}

/// Route `/workspace/settings/workflow/sdd/:stage/precondition` — the
/// dual-pane transition-precondition editor for one [SddStage]:
/// `GraphCanvas` (default/left) and [TransitionOutlineList] (right), both
/// bound to the same [TransitionPreconditionConfigCubit] so a selection
/// or edit in either pane is reflected in the other. Reached from
/// `WorkflowStatusSettingsScreen`'s "Configure precondition" affordance.
/// Mirrors `DecisionGraphEditorScreen`'s exact dual-pane shape — see that
/// screen's own dartdoc — with a `PreconditionGraphCanvas`-configured
/// canvas (no parameter chip, 2-value terminal) in place of DG's
/// condition/4-outcome canvas. Added for
/// `aion-arch/changes/sddstage-transition-preconditions`.
class SddStagePreconditionEditorScreen extends StatefulWidget {
  /// Creates a [SddStagePreconditionEditorScreen] for [stage].
  const SddStagePreconditionEditorScreen({super.key, required this.stage});

  /// Which [SddStage] this screen edits.
  final SddStage stage;

  @override
  State<SddStagePreconditionEditorScreen> createState() =>
      _SddStagePreconditionEditorScreenState();
}

class _SddStagePreconditionEditorScreenState
    extends State<SddStagePreconditionEditorScreen> {
  String? _selectedCanvasId;

  @override
  void initState() {
    super.initState();
    context.read<TransitionPreconditionConfigCubit>().load(widget.stage);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          _Header(stage: widget.stage),
          Expanded(
            child:
                BlocBuilder<
                  TransitionPreconditionConfigCubit,
                  TransitionPreconditionConfigState
                >(
                  builder: (context, state) {
                    final loaded = switch (state) {
                      TransitionPreconditionConfigLoaded loaded => loaded,
                      TransitionPreconditionConfigError(:final previous) =>
                        previous,
                      TransitionPreconditionConfigInitial() => null,
                    };
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: loaded == null
                              ? const Center(child: AppSpinner())
                              : _CanvasPane(
                                  stage: widget.stage,
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
                            child: TransitionOutlineList(stage: widget.stage),
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
/// allowed" action.
class _Header extends StatelessWidget {
  const _Header({required this.stage});

  final SddStage stage;

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
                      context.l10n.transitionPreconditionEyebrow,
                      style: AionText.caption.copyWith(color: c.textMuted),
                    ),
                    Text(
                      sddStagePreconditionStageLabel(context, stage),
                      style: AionText.h2.copyWith(color: c.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppButton(
                label: context.l10n.transitionPreconditionResetButton,
                variant: AppButtonVariant.ghost,
                onPressed: () => context
                    .read<TransitionPreconditionConfigCubit>()
                    .setRoot(null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The canvas pane's content: converts [loaded]'s whole reachable graph
/// into [GraphCanvas] nodes/edges, or [GraphCanvas.emptyState] when
/// there's no root yet. Tapping a field-check node opens it for editing
/// via [TransitionNodeForm.showAsPopover]. Mirrors `_CanvasPane`
/// (`decision_graph_editor_screen.dart`).
class _CanvasPane extends StatefulWidget {
  const _CanvasPane({
    required this.stage,
    required this.loaded,
    required this.selectedId,
    required this.onSelect,
  });

  final SddStage stage;
  final TransitionPreconditionConfigLoaded loaded;
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
        nodeBuilder: (context, data, selected, hovered, dragging) =>
            const SizedBox.shrink(),
        emptyState: _EmptyGraphState(stage: widget.stage),
      );
    }

    final layout = _TreeLayout(widget.loaded.nodesById, rootId: rootId)
      ..layout(rootNode, 0);

    return GraphCanvas<_CanvasNode>(
      nodes: layout.nodes,
      edges: layout.edges,
      selectedId: widget.selectedId,
      onNodeTap: (id) => _handleTap(context, id),
      nodeBuilder: (context, data, selected, hovered, dragging) =>
          switch (data) {
            _FieldCheckCanvasNode(:final node) => CompositedTransformTarget(
              link: _linkFor(node.id),
              child: _CanvasNodeContent(
                stage: widget.stage,
                data: data,
                selected: selected,
                hovered: hovered,
                dragging: dragging,
              ),
            ),
            _TerminalCanvasNode() => _CanvasNodeContent(
              stage: widget.stage,
              data: data,
              selected: selected,
              hovered: hovered,
              dragging: dragging,
            ),
          },
    );
  }

  /// Selects [id]; additionally opens [TransitionNodeForm.showAsPopover]
  /// when [id] resolves to a field-check node.
  void _handleTap(BuildContext context, String id) {
    widget.onSelect(id);
    final node = widget.loaded.nodesById[id];
    if (node == null) return;

    final cubit = context.read<TransitionPreconditionConfigCubit>();
    TransitionNodeForm.showAsPopover(
      context,
      link: _linkFor(id),
      stage: widget.stage,
      initialFieldId: node.fieldId,
      initialMatchedBranch: node.matchedBranch,
      initialUnmatchedBranch: node.unmatchedBranch,
      matchedChildFieldLabel: chainedChildFieldLabel(
        node.matchedBranch,
        widget.loaded.nodesById,
      ),
      unmatchedChildFieldLabel: chainedChildFieldLabel(
        node.unmatchedBranch,
        widget.loaded.nodesById,
      ),
      descendantCount:
          descendantIdsOf(node.id, widget.loaded.nodesById).length - 1,
      onSave:
          ({
            required fieldId,
            required matchedBranch,
            required unmatchedBranch,
          }) {
            cubit.updateNode(
              node.copyWith(
                fieldId: fieldId,
                matchedBranch: matchedBranch,
                unmatchedBranch: unmatchedBranch,
              ),
            );
          },
      onCreateChainedChild: (fieldId) => cubit.createNode(fieldId: fieldId),
      onDelete: () => cubit.deleteNode(node.id),
    );
  }
}

/// Lays out one [TransitionPreconditionConfigLoaded] graph's whole
/// reachable tree for [GraphCanvas]: depth → y (`152px` per level), an
/// in-order traversal (matched subtree, self, unmatched subtree) → x
/// (`296px` per slot) for field-check nodes. A branch's terminal pill
/// (when it doesn't continue to another field check) is positioned
/// directly beneath its parent's own anchor. Mirrors `_TreeLayout`
/// (`decision_graph_editor_screen.dart`).
class _TreeLayout {
  _TreeLayout(this._nodesById, {required this._rootId});

  final Map<String, TransitionNode> _nodesById;
  final String? _rootId;
  final List<GraphCanvasNode<_CanvasNode>> nodes = [];
  final List<GraphCanvasEdge> edges = [];
  int _slot = 0;

  static const double _slotWidth = 296;
  static const double _levelHeight = 152;
  static const double _terminalWidth = 150;

  double layout(TransitionNode node, int depth) {
    double? matchedChildX;
    if (node.matchedBranch case ToTransitionNodeBranch(:final nodeId)) {
      final child = _nodesById[nodeId];
      if (child != null) matchedChildX = layout(child, depth + 1);
    }

    final x = (_slot * _slotWidth) + 40;
    _slot++;
    final y = (depth * _levelHeight) + 40;
    final isError =
        transitionFieldById(node.fieldId) == null ||
        [node.matchedBranch, node.unmatchedBranch].any(
          (branch) =>
              branch is ToTransitionNodeBranch &&
              !_nodesById.containsKey(branch.nodeId),
        );
    nodes.add(
      GraphCanvasNode(
        id: node.id,
        position: Offset(x, y),
        data: _FieldCheckCanvasNode(
          node,
          isRoot: node.id == _rootId,
          isError: isError,
        ),
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
    if (node.unmatchedBranch case ToTransitionNodeBranch(:final nodeId)) {
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
    required TransitionBranch branch,
    required double? childX,
  }) {
    switch (branch) {
      case ToTransitionNodeBranch(:final nodeId):
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
      case TerminalTransitionBranch(:final outcome):
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

/// Renders one [_CanvasNode]'s content — a field-check box or a terminal
/// outcome pill. Mirrors `_CanvasNodeContent`
/// (`decision_graph_editor_screen.dart`), simpler: no parameter chip, no
/// `agentJudgment`-shaped rendering.
class _CanvasNodeContent extends StatelessWidget {
  const _CanvasNodeContent({
    required this.stage,
    required this.data,
    required this.selected,
    required this.hovered,
    required this.dragging,
  });

  final SddStage stage;
  final _CanvasNode data;
  final bool selected;
  final bool hovered;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final isDark = ThemeScope.of(context).isDark;

    return switch (data) {
      _FieldCheckCanvasNode(:final node, :final isRoot, :final isError) =>
        _buildFieldCheckNode(context, c, isDark, node, isRoot, isError),
      _TerminalCanvasNode(:final outcome) => DecoratedBox(
        decoration: BoxDecoration(
          color: transitionOutcomeColor(c, outcome).withValues(alpha: 0.14),
          border: Border.all(
            color: transitionOutcomeColor(c, outcome).withValues(alpha: 0.32),
            width: 1,
          ),
          borderRadius: BorderRadius.all(AionRadius.pill),
        ),
        child: SizedBox(
          width: 150,
          height: 36,
          child: Center(
            child: Text(
              transitionOutcomeLabel(context, outcome),
              style: AionText.badgeLabel.copyWith(
                color: transitionOutcomeColor(c, outcome),
              ),
            ),
          ),
        ),
      ),
    };
  }

  Widget _buildFieldCheckNode(
    BuildContext context,
    AionColors c,
    bool isDark,
    TransitionNode node,
    bool isRoot,
    bool isError,
  ) {
    final Color borderColor;
    final double borderWidth;
    if (isError) {
      borderColor = c.danger;
      borderWidth = 1.5;
    } else if (dragging) {
      borderColor = c.primary.withValues(alpha: 0.6);
      borderWidth = 1.5;
    } else if (selected) {
      borderColor = c.primary;
      borderWidth = 1.5;
    } else if (hovered) {
      borderColor = c.borderStrong;
      borderWidth = 1;
    } else {
      borderColor = c.border;
      borderWidth = 1;
    }
    final fill = hovered && !dragging ? c.surfaceHover : c.surface;
    final eyebrowColor = isError ? c.danger : c.textMuted;
    final title =
        transitionFieldById(node.fieldId)?.displayName ?? node.fieldId;

    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: borderColor, width: borderWidth),
        borderRadius: BorderRadius.all(AionRadius.lg),
        boxShadow: AionShadows.card(c, isDark),
      ),
      child: SizedBox(
        width: 240,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isError ? 'IF · INCOMPLETE' : 'IF · ${title.toUpperCase()}',
                style: AionText.caption.copyWith(color: eyebrowColor),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: AionText.cardTitle.copyWith(color: c.textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        if (isRoot)
          Positioned(top: -30, left: 0, child: _RootMarker(stage: stage)),
        Positioned(
          bottom: -3.5,
          left: 68 - 3.5,
          child: _AnchorDot(color: c.primary),
        ),
        Positioned(
          bottom: -3.5,
          left: 172 - 3.5,
          child: _AnchorDot(color: c.borderStrong),
        ),
      ],
    );
  }
}

/// The root-node marker chip pinned above the graph's entry-point node,
/// naming the stage transition rather than an automation context.
/// Mirrors `_RootMarker` (`decision_graph_editor_screen.dart`).
class _RootMarker extends StatelessWidget {
  const _RootMarker({required this.stage});

  final SddStage stage;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final label = sddStagePreconditionStageLabel(context, stage);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.primarySubtle,
        borderRadius: BorderRadius.all(AionRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 20,
          child: Center(
            child: Text(
              context.l10n.transitionPreconditionRootMarker(
                label.toUpperCase(),
              ),
              style: AionText.caption.copyWith(color: c.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// One matched/unmatched anchor dot on a field-check node's bottom edge.
/// Mirrors `_AnchorDot` (`decision_graph_editor_screen.dart`).
class _AnchorDot extends StatelessWidget {
  const _AnchorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox(width: 7, height: 7),
    );
  }
}

/// The canvas's empty-graph placeholder, shown when [stage] has no
/// configured precondition. Mirrors `_EmptyGraphState`
/// (`decision_graph_editor_screen.dart`).
class _EmptyGraphState extends StatelessWidget {
  const _EmptyGraphState({required this.stage});

  final SddStage stage;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final label = sddStagePreconditionStageLabel(context, stage);
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
                context.l10n.transitionPreconditionEmptyStateEyebrow,
                style: AionText.caption.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.transitionPreconditionEmptyStateHeadline(label),
                style: AionText.dialogTitle.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.transitionPreconditionEmptyStateBody,
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
