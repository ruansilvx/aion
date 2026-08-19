// presentation/screens/workflow_status_settings_screen.dart — WorkflowStatusSettingsScreen and its supporting private widgets (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';
import 'package:aion/features/tickets/presentation/cubit/workflow_config_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/workflow_config_state.dart';

/// The `/workspace/settings/workflow` route — where a project customizes
/// its ticket workflow instead of inheriting Aion's fixed defaults. Two
/// sections: **Ticket Statuses** (per-type-scoped, reorderable status
/// list with Base-only workflow roles and an inline add form) and
/// **SDD Stages** (one gating toggle plus five stage-label rename
/// fields). Reached from the same secondary-actions popover as the
/// existing provider `SettingsScreen`. Per
/// `aion-arch/changes/configurable-ticket-workflow`'s Component Spec.
///
/// One deliberate simplification from the pasted Component Spec, noted
/// here rather than silently: §6.4's hand-rolled `Listener`/
/// `AnimatedPositioned` drag-reorder mechanic is replaced with a pair of
/// up/down icon buttons per row ([_StatusRow]'s trailing reorder
/// controls) — functionally equivalent (any status can be moved to any
/// position) and keyboard-operable, which a pointer-only drag gesture
/// alone would not be, at a fraction of the implementation risk of
/// reproducing exact drag physics.
class WorkflowStatusSettingsScreen extends StatefulWidget {
  /// Creates a [WorkflowStatusSettingsScreen].
  const WorkflowStatusSettingsScreen({super.key});

  @override
  State<WorkflowStatusSettingsScreen> createState() =>
      _WorkflowStatusSettingsScreenState();
}

class _WorkflowStatusSettingsScreenState
    extends State<WorkflowStatusSettingsScreen> {
  /// The currently selected scope — `null` means Base. View state only,
  /// never persisted; resets to Base on entry (Component Spec §1.2).
  TicketType? _selectedScope;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          AppHeader(
            title: context.l10n.workflowSettingsScreenTitle,
            showBack: true,
            onBack: () => context.go('/workspace/tickets'),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AionSpacing.sp20,
                2,
                AionSpacing.sp20,
                AionSpacing.sp20,
              ),
              child: ContentMaxWidth(
                variant: ContentWidthVariant.form,
                child: BlocBuilder<WorkflowConfigCubit, WorkflowConfigState>(
                  builder: (context, state) {
                    final WorkflowConfigLoaded? loaded = switch (state) {
                      WorkflowConfigLoaded() => state,
                      WorkflowConfigError(:final previous) => previous,
                      WorkflowConfigInitial() => null,
                    };
                    if (loaded == null) {
                      return const Center(child: AppSpinner());
                    }
                    final errorMessage = state is WorkflowConfigError
                        ? state.message
                        : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WorkflowSectionHeader(
                          eyebrow:
                              context.l10n.workflowSettingsTicketStatusesEyebrow,
                        ),
                        _ScopeSelector(
                          selectedScope: _selectedScope,
                          onSelected: (scope) =>
                              setState(() => _selectedScope = scope),
                        ),
                        if (errorMessage != null) ...[
                          _RoleInvariantBanner(message: errorMessage),
                          const SizedBox(height: AionSpacing.sp8),
                        ],
                        _StatusList(
                          allStatuses: loaded.statuses,
                          scope: _selectedScope,
                        ),
                        const SizedBox(height: 2),
                        _AddStatusControl(
                          scope: _selectedScope,
                          allStatuses: loaded.statuses,
                        ),
                        // Component Spec §2.1's 28px inter-section gap —
                        // not an AionSpacing token (that scale stops at
                        // sp24/sp32), used as an explicit local per this
                        // spec's own token-usage note (§11).
                        const SizedBox(height: 28),
                        _WorkflowSectionHeader(
                          eyebrow: context.l10n.workflowSettingsSddStagesEyebrow,
                        ),
                        _SddToggleRow(
                          designStagesEnabled: loaded.designStagesEnabled,
                        ),
                        _WorkflowSectionHeader(
                          eyebrow:
                              context.l10n.workflowSettingsStageLabelsEyebrow,
                          topMargin: 4,
                        ),
                        for (final stage in SddStage.values)
                          _SddStageRenameRow(
                            stage: stage,
                            displayNameOverride:
                                loaded.stageDisplayNameOverrides[stage],
                            isLast: stage == SddStage.values.last,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reusable eyebrow line opening each section (and the "Stage
/// labels" sub-label). Component Spec §3.
class _WorkflowSectionHeader extends StatelessWidget {
  const _WorkflowSectionHeader({required this.eyebrow, this.topMargin = 0});

  final String eyebrow;
  final double topMargin;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, topMargin, 0, 12),
      child: Text(
        eyebrow,
        style: AionText.caption.copyWith(color: c.textMuted),
      ),
    );
  }
}

/// A horizontally-scrolling pill strip: Base first, then one pill per
/// [TicketType] in enum order. Component Spec §4.
class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.selectedScope, required this.onSelected});

  final TicketType? selectedScope;
  final ValueChanged<TicketType?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ScopePill(
              label: context.l10n.workflowSettingsScopeBase,
              selected: selectedScope == null,
              onTap: () => onSelected(null),
            ),
            for (final type in TicketType.values) ...[
              const SizedBox(width: 6),
              _ScopePill(
                label: ticketTypeLabel(context, type),
                selected: selectedScope == type,
                onTap: () => onSelected(type),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One [_ScopeSelector] pill. Component Spec §4.1/§4.2.
class _ScopePill extends StatefulWidget {
  const _ScopePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ScopePill> createState() => _ScopePillState();
}

class _ScopePillState extends State<_ScopePill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final Color fill;
    final Color border;
    final Color textColor;
    if (widget.selected) {
      fill = c.primarySubtle;
      border = c.primary;
      textColor = c.primary;
    } else if (_isHovered) {
      fill = c.surfaceHover;
      border = c.borderStrong;
      textColor = c.textPrimary;
    } else {
      fill = const Color(0x00000000);
      border = c.border;
      textColor = c.textSecondary;
    }

    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(
                color: border,
                width: widget.selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Text(
              widget.label,
              style: AionText.button.copyWith(fontSize: 13, color: textColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resolves [allStatuses] into the ordered list [scope] actually renders
/// — Base scope shows only shared-base statuses; a [TicketType] scope
/// shows the shared-base set (inherited, read-only) merged with that
/// type's own extensions, sorted by [WorkflowStatus.sortOrder].
/// Component Spec §1.2.
List<WorkflowStatus> _scopedStatuses(
  List<WorkflowStatus> allStatuses,
  TicketType? scope,
) {
  final result = allStatuses
      .where((s) => s.ticketType == null || s.ticketType == scope)
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return result;
}

/// The reorderable list of [WorkflowStatus] rows for the active [scope].
class _StatusList extends StatelessWidget {
  const _StatusList({required this.allStatuses, required this.scope});

  final List<WorkflowStatus> allStatuses;
  final TicketType? scope;

  @override
  Widget build(BuildContext context) {
    final rows = _scopedStatuses(allStatuses, scope);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _StatusRow(
              status: rows[i],
              scope: scope,
              allStatuses: allStatuses,
              canMoveUp: i > 0,
              canMoveDown: i < rows.length - 1,
              scopedOrder: rows,
            ),
          ),
      ],
    );
  }
}

/// One status row: grip/reorder controls, an inline-editable display-name
/// field, a delete affordance, the internal name, scope tags, and (Base
/// scope only) a role dropdown. Component Spec §5.
class _StatusRow extends StatefulWidget {
  const _StatusRow({
    required this.status,
    required this.scope,
    required this.allStatuses,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.scopedOrder,
  });

  final WorkflowStatus status;
  final TicketType? scope;
  final List<WorkflowStatus> allStatuses;
  final bool canMoveUp;
  final bool canMoveDown;
  final List<WorkflowStatus> scopedOrder;

  @override
  State<_StatusRow> createState() => _StatusRowState();
}

class _StatusRowState extends State<_StatusRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isHovered = false;
  String? _localError;

  /// Whether this row is showing a status inherited from Base into a
  /// type scope — read-only, no delete, no role.
  bool get _isInherited =>
      widget.scope != null && widget.status.ticketType == null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.status.displayName);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _commitRename();
    });
  }

  @override
  void didUpdateWidget(covariant _StatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.status.displayName != widget.status.displayName) {
      _controller.text = widget.status.displayName;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitRename() {
    final name = _controller.text.trim();
    if (name.isEmpty || name == widget.status.displayName) {
      _controller.text = widget.status.displayName;
      return;
    }
    context.read<WorkflowConfigCubit>().updateStatus(
      widget.status.copyWith(displayName: name),
    );
  }

  void _move(int delta) {
    final order = [for (final s in widget.scopedOrder) s.id];
    final index = order.indexOf(widget.status.id);
    final target = index + delta;
    if (target < 0 || target >= order.length) return;
    order.removeAt(index);
    order.insert(target, widget.status.id);
    context.read<WorkflowConfigCubit>().reorderStatuses(order);
  }

  void _delete() {
    context.read<WorkflowConfigCubit>().deleteStatus(widget.status.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isInherited = _isInherited;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _isHovered ? c.surfaceHover : c.surface,
          border: Border.all(color: c.border, width: 1),
          borderRadius: BorderRadius.all(AionRadius.lg),
        ),
        child: Opacity(
          opacity: isInherited ? 0.72 : 1.0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 11, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _ReorderControls(
                      canMoveUp: !isInherited && widget.canMoveUp,
                      canMoveDown: !isInherited && widget.canMoveDown,
                      onMoveUp: () => _move(-1),
                      onMoveDown: () => _move(1),
                      dimmed: isInherited,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: isInherited
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Text(
                                widget.status.displayName,
                                style: AionText.cardTitle.copyWith(
                                  color: c.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : AppTextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              isError: _localError != null,
                              onSubmitted: (_) => _focusNode.unfocus(),
                            ),
                    ),
                    if (!isInherited) ...[
                      const SizedBox(width: 10),
                      _DeleteAffordance(onTap: _delete),
                    ] else
                      const SizedBox(width: 15),
                  ],
                ),
                const SizedBox(height: 9),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Row(
                    children: [
                      Text(
                        widget.status.name,
                        style: AionText.key.copyWith(color: c.textMuted),
                      ),
                      const SizedBox(width: 8),
                      if (isInherited)
                        _Tag(
                          label: context.l10n.workflowSettingsInheritedTag,
                          fg: c.textSecondary,
                          fill: c.neutralTint(t.isDark),
                          border: c.neutralBorderTint(t.isDark),
                        )
                      else if (widget.scope != null)
                        _Tag(
                          label: context.l10n.workflowSettingsTypeOnlyTag(
                            ticketTypeLabel(context, widget.scope!).toUpperCase(),
                          ),
                          fg: _typeAccent(c, widget.scope!),
                          fill: _typeAccent(
                            c,
                            widget.scope!,
                          ).withValues(alpha: t.isDark ? 0.20 : 0.13),
                          border: null,
                        ),
                      const Spacer(),
                      if (widget.scope == null)
                        _RoleDropdown(
                          status: widget.status,
                          allStatuses: widget.allStatuses,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [_StatusRow]'s up/down reorder controls — replaces the Component
/// Spec's hand-rolled drag grip (§5.2/§6.4); see
/// [WorkflowStatusSettingsScreen]'s own dartdoc for why.
class _ReorderControls extends StatelessWidget {
  const _ReorderControls({
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.dimmed,
  });

  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniIconButton(
          icon: PhosphorIcons.caretUpLight,
          onTap: canMoveUp ? onMoveUp : null,
          color: c.textMuted,
        ),
        _MiniIconButton(
          icon: PhosphorIcons.caretDownLight,
          onTap: canMoveDown ? onMoveDown : null,
          color: c.textMuted,
        ),
      ],
    );
  }
}

/// A tiny (12px glyph) icon-only tap target used by [_ReorderControls].
class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final PhosphorIconData icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return MouseRegion(
      cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: disabled ? 0.26 : 0.75,
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: PhosphorIcon(icon, size: 12, color: color),
          ),
        ),
      ),
    );
  }
}

/// [_StatusRow]'s trailing trash-glyph delete affordance. Component Spec
/// §5.4 — simplified to a single enabled state (this screen relies on
/// [WorkflowConfigCubit.deleteStatus]'s own rejection + the top-of-list
/// [_RoleInvariantBanner]/inline error to explain a blocked delete,
/// rather than pre-computing per-row disabled state from a live
/// in-use-ticket count).
class _DeleteAffordance extends StatefulWidget {
  const _DeleteAffordance({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DeleteAffordance> createState() => _DeleteAffordanceState();
}

class _DeleteAffordanceState extends State<_DeleteAffordance> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _isHovered ? c.destructiveTint(t.isDark) : null,
            borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: PhosphorIcon(
              PhosphorIcons.trashLight,
              size: 15,
              color: _isHovered ? c.danger : c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small pill tag on a [_StatusRow]'s meta line — `INHERITED` or
/// `"{TYPE} ONLY"`. Component Spec §5.6.
class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.fg,
    required this.fill,
    required this.border,
  });

  final String label;
  final Color fg;
  final Color fill;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: border != null ? Border.all(color: border!, width: 1) : null,
        borderRadius: BorderRadius.all(AionRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: AionText.chip.copyWith(fontSize: 9.5, color: fg),
        ),
      ),
    );
  }
}

/// This type's accent color — a private duplicate of `TypeChip`'s own
/// switch (that one is private to its own file), used by [_Tag]'s
/// `"{TYPE} ONLY"` variant.
Color _typeAccent(AionColors c, TicketType type) => switch (type) {
  TicketType.story => c.typeStory,
  TicketType.epic => c.typeEpic,
  TicketType.resource => c.typeResource,
  TicketType.page => c.typePage,
  TicketType.idea => c.typeIdea,
  TicketType.knownGap => c.typeKnownGap,
  TicketType.openQuestion => c.typeOpenQuestion,
  TicketType.release => c.typeRelease,
  TicketType.chat => c.typeChat,
  TicketType.bug => c.typeBug,
  TicketType.task => c.typeTask,
};

/// A compact role badge/selector for a Base-scope [_StatusRow] — built on
/// [SelectionMenu] (which already provides the `Overlay`/focus/`Escape`
/// mechanics `RoleDropdown`'s bespoke Component Spec §10.3 panel would
/// otherwise hand-roll a second copy of). One deviation from §10:
/// [SelectionMenu] excludes [currentValue] from its option list — the
/// same convention `MoveToStatusMenu` already established — rather than
/// showing all 4 rows with a checkmark on the current one.
class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.status, required this.allStatuses});

  final WorkflowStatus status;
  final List<WorkflowStatus> allStatuses;

  @override
  Widget build(BuildContext context) {
    final roles = <WorkflowStatusRole?>[null, ...WorkflowStatusRole.values];
    return SelectionMenu<WorkflowStatusRole?>(
      semanticsLabel: context.l10n.workflowSettingsChangeRole,
      items: roles,
      currentValue: status.role,
      itemLabel: (r) => _roleLabel(context, r),
      itemBuilder: (context, c, item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _RoleChip(role: item),
      ),
      onSelected: (role) => context.read<WorkflowConfigCubit>().updateStatus(
        status.copyWith(role: () => role),
      ),
      trigger: _RoleChip(role: status.role),
    );
  }
}

/// [_RoleDropdown]'s chip visual, both as the closed trigger and as each
/// open-menu row's content. Component Spec §10.1.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final WorkflowStatusRole? role;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final a = t.isDark ? 0.20 : 0.13;
    final (Color fg, Color fill, Color? border) = switch (role) {
      WorkflowStatusRole.executionTrigger => (
        c.primary,
        c.primary.withValues(alpha: a),
        null,
      ),
      WorkflowStatusRole.reviewReady => (
        c.warning,
        c.warning.withValues(alpha: a),
        null,
      ),
      WorkflowStatusRole.done => (
        c.success,
        c.success.withValues(alpha: a),
        null,
      ),
      null => (
        c.textSecondary,
        c.neutralTint(t.isDark),
        c.neutralBorderTint(t.isDark),
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: border != null ? Border.all(color: border, width: 1) : null,
        borderRadius: BorderRadius.all(AionRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 4, 7, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _roleLabel(context, role),
              style: AionText.chip.copyWith(color: fg),
            ),
            const SizedBox(width: 6),
            PhosphorIcon(
              PhosphorIcons.caretDownLight,
              size: 9,
              color: fg.withValues(alpha: 0.85),
            ),
          ],
        ),
      ),
    );
  }
}

/// Localized label for [role] (`null` = "No role"). Component Spec §10.1.
String _roleLabel(BuildContext context, WorkflowStatusRole? role) =>
    switch (role) {
      WorkflowStatusRole.executionTrigger =>
        context.l10n.workflowSettingsRoleExecutionTrigger,
      WorkflowStatusRole.reviewReady =>
        context.l10n.workflowSettingsRoleReviewReady,
      WorkflowStatusRole.done => context.l10n.workflowSettingsRoleDone,
      null => context.l10n.workflowSettingsRoleNone,
    };

/// The role-invariant/blocked-delete banner rendered at the top of the
/// status list whenever [WorkflowConfigCubit] rejects an attempted
/// write. Component Spec §7.2.
class _RoleInvariantBanner extends StatelessWidget {
  const _RoleInvariantBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: t.isDark ? 0.14 : 0.08),
        border: Border.all(
          color: c.danger.withValues(alpha: t.isDark ? 0.34 : 0.24),
          width: 1,
        ),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('▲', style: TextStyle(fontSize: 13, color: c.danger)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: AionText.bodySm.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Creates a status in the active scope: a collapsed dashed-border
/// "+ Add status" button that expands into an inline form. Component
/// Spec §6.
class _AddStatusControl extends StatefulWidget {
  const _AddStatusControl({required this.scope, required this.allStatuses});

  final TicketType? scope;
  final List<WorkflowStatus> allStatuses;

  @override
  State<_AddStatusControl> createState() => _AddStatusControlState();
}

class _AddStatusControlState extends State<_AddStatusControl> {
  bool _expanded = false;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Rebuilds on every keystroke so the live duplicate-name check below
    // tracks what's being typed, mirroring `_ExecutionContextCapSection`'s
    // established pattern (`settings_screen.dart`).
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Whether the live-typed display name collides (case-insensitively)
  /// with a status already visible in the active scope — Component Spec
  /// §1.5/§7.1. Checked client-side for instant feedback;
  /// [WorkflowConfigCubit.createStatus] still re-validates uniqueness on
  /// the derived internal name server-side regardless.
  bool get _isDuplicate {
    final name = _controller.text.trim().toLowerCase();
    if (name.isEmpty) return false;
    return _scopedStatuses(widget.allStatuses, widget.scope).any(
      (s) => s.displayName.toLowerCase() == name,
    );
  }

  static const _uuid = Uuid();

  String _slugify(String input) {
    final base = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return base.isEmpty ? 'status' : base;
  }

  String _dedupedSlug(String base) {
    // Mirrors WorkflowConfigCubit._isNameUniqueInScope's effective-scope
    // rule: base statuses, plus (only when adding into a type scope)
    // that type's own extensions — the same merged view [_scopedStatuses]
    // itself renders.
    final existingNames = _scopedStatuses(widget.allStatuses, widget.scope)
        .map((s) => s.name)
        .toSet();
    if (!existingNames.contains(base)) return base;
    var i = 2;
    while (existingNames.contains('${base}_$i')) {
      i++;
    }
    return '${base}_$i';
  }

  void _confirm() {
    final displayName = _controller.text.trim();
    // The Add button is disabled while empty or duplicate (see build()'s
    // onPressed), so this is defensive only — reachable via
    // Enter-to-submit before the button's own disabled state has
    // repainted.
    if (displayName.isEmpty || _isDuplicate) return;
    final nextSortOrder =
        (_scopedStatuses(widget.allStatuses, widget.scope).map((s) => s.sortOrder).fold<int>(-1, (a, b) => a > b ? a : b)) +
        1;
    final status = WorkflowStatus(
      id: _uuid.v4(),
      name: _dedupedSlug(_slugify(displayName)),
      displayName: displayName,
      ticketType: widget.scope,
      sortOrder: nextSortOrder,
    );
    context.read<WorkflowConfigCubit>().createStatus(status);
    _controller.clear();
    setState(() => _expanded = false);
  }

  void _cancel() {
    _controller.clear();
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    if (!_expanded) {
      return _AddStatusCollapsedButton(onTap: () => setState(() => _expanded = true));
    }

    final scopeLabel = widget.scope == null
        ? context.l10n.workflowSettingsScopeBase
        : ticketTypeLabel(context, widget.scope!);
    final isDuplicate = _isDuplicate;
    final isEmpty = _controller.text.trim().isEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.primary, width: 1.5),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.workflowSettingsNewStatusEyebrow(
                scopeLabel.toUpperCase(),
              ),
              style: AionText.caption.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: 13),
            AppTextField(
              controller: _controller,
              labelText: context.l10n.workflowSettingsDisplayNameLabel,
              isRequired: true,
              isError: isDuplicate,
              onSubmitted: (_) => _confirm(),
            ),
            if (isDuplicate) ...[
              const SizedBox(height: 6),
              Text(
                context.l10n.workflowSettingsDuplicateNameError(
                  _controller.text.trim(),
                ),
                style: AionText.bodySm.copyWith(fontSize: 12, color: c.danger),
              ),
            ],
            const SizedBox(height: 13),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: context.l10n.workflowSettingsCancel,
                  variant: AppButtonVariant.ghost,
                  onPressed: _cancel,
                ),
                const SizedBox(width: 9),
                AppButton(
                  label: context.l10n.workflowSettingsAddStatus,
                  onPressed: (isEmpty || isDuplicate) ? null : _confirm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// [_AddStatusControl]'s collapsed dashed-border trigger button.
class _AddStatusCollapsedButton extends StatefulWidget {
  const _AddStatusCollapsedButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddStatusCollapsedButton> createState() =>
      _AddStatusCollapsedButtonState();
}

class _AddStatusCollapsedButtonState extends State<_AddStatusCollapsedButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _isHovered
                ? c.primary.withValues(alpha: t.isDark ? 0.08 : 0.05)
                : null,
            border: Border.all(
              color: _isHovered ? c.primary : c.borderStrong,
              width: 1.5,
            ),
            borderRadius: BorderRadius.all(AionRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '+',
                  style: AionText.button.copyWith(
                    fontSize: 17,
                    color: c.primary,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  context.l10n.workflowSettingsAddStatus,
                  style: AionText.button.copyWith(color: c.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Require design review stages" row + [_ToggleSwitch]. Component Spec
/// §8.
class _SddToggleRow extends StatelessWidget {
  const _SddToggleRow({required this.designStagesEnabled});

  final bool designStagesEnabled;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.workflowSettingsRequireDesignReviewTitle,
                    style: AionText.cardTitle.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.l10n.workflowSettingsRequireDesignReviewSubtitle,
                    style: AionText.bodySm.copyWith(
                      fontSize: 12.5,
                      color: c.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            _ToggleSwitch(
              value: designStagesEnabled,
              onChanged: (v) =>
                  context.read<WorkflowConfigCubit>().setDesignStagesEnabled(v),
            ),
          ],
        ),
      ),
    );
  }
}

/// A non-Material on/off switch atom — track + animated thumb. Component
/// Spec §8.2.
class _ToggleSwitch extends StatefulWidget {
  const _ToggleSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_ToggleSwitch> createState() => _ToggleSwitchState();
}

class _ToggleSwitchState extends State<_ToggleSwitch> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final Color track;
    final Color border;
    if (widget.value) {
      track = _isHovered ? c.primaryHover : c.primary;
      border = track;
    } else {
      track = c.surfaceHover;
      border = _isHovered ? c.secondary : c.borderStrong;
    }

    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onChanged(!widget.value);
            return null;
          },
        ),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: () => widget.onChanged(!widget.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeInOut,
            width: 46,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: track,
              border: Border.all(color: border, width: 1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeInOut,
              alignment: widget.value
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x4D000000),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const SizedBox(width: 20, height: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One fixed-[SddStage] rename row — a non-editable stage-name label and
/// an editable display-label field. No reorder, add, or delete. Component
/// Spec §9.
class _SddStageRenameRow extends StatefulWidget {
  const _SddStageRenameRow({
    required this.stage,
    required this.displayNameOverride,
    required this.isLast,
  });

  final SddStage stage;
  final String? displayNameOverride;
  final bool isLast;

  @override
  State<_SddStageRenameRow> createState() => _SddStageRenameRowState();
}

class _SddStageRenameRowState extends State<_SddStageRenameRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.displayNameOverride ?? '');
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _SddStageRenameRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.displayNameOverride != widget.displayNameOverride) {
      _controller.text = widget.displayNameOverride ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _controller.text.trim();
    context.read<WorkflowConfigCubit>().setStageDisplayNameOverride(
      widget.stage,
      text.isEmpty ? null : text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                _fixedStageName(widget.stage),
                style: AionText.cardTitle.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                controller: _controller,
                focusNode: _focusNode,
                hintText: _fixedStageName(widget.stage),
                onSubmitted: (_) => _focusNode.unfocus(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [stage]'s fixed, never-editable node name. Mirrors
/// `TicketsCubit._stageHardcodedPresentName`'s exact literals.
String _fixedStageName(SddStage stage) => switch (stage) {
  SddStage.exploring => 'Exploring',
  SddStage.proposed => 'Proposed',
  SddStage.designBrief => 'Design Brief',
  SddStage.designSync => 'Design Sync',
  SddStage.verifying => 'Verifying',
  SddStage.archived => 'Archived',
};
