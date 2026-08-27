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
/// (default/left, read-only visualization in this slice — see this
/// file's own limitations note below) and [DecisionOutlineList]
/// (right, does all authoring), both bound to the same
/// [DecisionGraphConfigCubit]. Reached from `SettingsScreen`'s
/// `_AutomationSection` "Configure decision graph" affordance.
///
/// **Known limitation of this slice:** `GraphCanvas`'s node-tap
/// interaction only highlights a node (no popover edit form yet) — every
/// authoring action (add/edit/delete a condition, set the root) happens
/// through [DecisionOutlineList]. The two panes still can't diverge, since
/// both render from the one [DecisionGraphConfigCubit] state; canvas-side
/// editing is a reasonable follow-up once `DecisionNodeForm.showAsPopover`
/// is wired to a per-node `LayerLink`. Added for
/// `aion-arch/changes/automation-decision-graphs`; see that change's
/// design.md §4/§5.
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

/// The canvas pane's content: converts [loaded]'s graph into
/// [GraphCanvas] nodes/edges (a condition node plus its two terminal
/// outcome pills, or [GraphCanvas.emptyState] when there's no root yet).
class _CanvasPane extends StatelessWidget {
  const _CanvasPane({
    required this.loaded,
    required this.selectedId,
    required this.onSelect,
  });

  final DecisionGraphConfigLoaded loaded;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final rootId = loaded.graph.rootNodeId;
    final rootNode = rootId == null ? null : loaded.nodesById[rootId];

    if (rootNode == null) {
      return GraphCanvas<_CanvasNode>(
        nodes: const [],
        edges: const [],
        nodeBuilder: (context, data, selected) => const SizedBox.shrink(),
        emptyState: const _EmptyGraphState(),
      );
    }

    final spec = decisionConditionCatalog
        .where((s) => s.id == rootNode.conditionId)
        .firstOrNull;
    final matchedOutcome = rootNode.matchedBranch is TerminalBranch
        ? (rootNode.matchedBranch as TerminalBranch).outcome
        : null;
    final unmatchedOutcome = rootNode.unmatchedBranch is TerminalBranch
        ? (rootNode.unmatchedBranch as TerminalBranch).outcome
        : null;

    final nodes = <GraphCanvasNode<_CanvasNode>>[
      GraphCanvasNode(
        id: rootNode.id,
        position: const Offset(120, 80),
        data: _ConditionCanvasNode(rootNode, spec),
      ),
      if (matchedOutcome != null)
        GraphCanvasNode(
          id: '${rootNode.id}-matched',
          position: const Offset(48, 240),
          size: const Size(150, 36),
          data: _TerminalCanvasNode(matchedOutcome),
        ),
      if (unmatchedOutcome != null)
        GraphCanvasNode(
          id: '${rootNode.id}-unmatched',
          position: const Offset(320, 240),
          size: const Size(150, 36),
          data: _TerminalCanvasNode(unmatchedOutcome),
        ),
    ];
    final edges = <GraphCanvasEdge>[
      if (matchedOutcome != null)
        GraphCanvasEdge(fromId: rootNode.id, toId: '${rootNode.id}-matched'),
      if (unmatchedOutcome != null)
        GraphCanvasEdge(
          fromId: rootNode.id,
          toId: '${rootNode.id}-unmatched',
          dashed: true,
          muted: true,
        ),
    ];

    return GraphCanvas<_CanvasNode>(
      nodes: nodes,
      edges: edges,
      selectedId: selectedId,
      onNodeTap: onSelect,
      nodeBuilder: (context, data, selected) =>
          _CanvasNodeContent(data: data, selected: selected),
    );
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
