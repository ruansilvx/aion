// presentation/screens/workflow_status_settings_screen.dart — WorkflowStatusSettingsScreen and its supporting private widgets (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/skill_attachment.dart';
import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/skill_attachment_kind.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';
import 'package:aion/features/tickets/presentation/cubit/workflow_config_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/workflow_config_state.dart';

/// The `/workspace/settings/workflow` route — where a project customizes its
/// ticket workflow instead of inheriting Aion's fixed defaults. Two sections:
/// **Ticket Statuses** (per-type-scoped, reorderable status list with
/// Base-only workflow roles and an inline add form) and **SDD Stages** (one
/// gating toggle plus five stage-label rename fields). Reached from the same
/// secondary-actions popover as the existing provider `SettingsScreen`. Per
/// `AIO-549`'s Component Spec.
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
            // Secondary entry point into WorkflowPromptTemplatesScreen,
            // alongside _AttachmentForm's own "Manage templates" link. Added
            // for `AIO-2650`.
            trailing: _ManageTemplatesLink(
              label: context.l10n.workflowSettingsManageTemplates,
            ),
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
                          eyebrow: context
                              .l10n
                              .workflowSettingsTicketStatusesEyebrow,
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
                          attachments: loaded.attachments,
                          templates: loaded.templates,
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
                          eyebrow:
                              context.l10n.workflowSettingsSddStagesEyebrow,
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
                            attachment: loaded.attachments
                                .where((a) => a.sddStage == stage)
                                .firstOrNull,
                            templates: loaded.templates,
                            preconditionNodeCount:
                                loaded.transitionPreconditionNodeCounts[stage],
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
  bool _isFocused = false;

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
      onShowFocusHighlight: (value) => setState(() => _isFocused = value),
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
              boxShadow: _isFocused ? AionShadows.focus(c, t.isDark) : null,
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
  final result =
      allStatuses
          .where((s) => s.ticketType == null || s.ticketType == scope)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return result;
}

/// The reorderable list of [WorkflowStatus] rows for the active [scope].
class _StatusList extends StatelessWidget {
  const _StatusList({
    required this.allStatuses,
    required this.scope,
    required this.attachments,
    required this.templates,
  });

  final List<WorkflowStatus> allStatuses;
  final TicketType? scope;
  final List<SkillAttachment> attachments;
  final List<WorkflowPromptTemplate> templates;

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
              attachment: attachments
                  .where((a) => a.workflowStatusId == rows[i].id)
                  .firstOrNull,
              templates: templates,
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
    required this.attachment,
    required this.templates,
  });

  final WorkflowStatus status;
  final TicketType? scope;
  final List<WorkflowStatus> allStatuses;
  final bool canMoveUp;
  final bool canMoveDown;
  final List<WorkflowStatus> scopedOrder;

  /// This status's configured [SkillAttachment], or `null`. Added for
  /// `AIO-2650`.
  final SkillAttachment? attachment;

  /// Every project-configured [WorkflowPromptTemplate], threaded down to
  /// [_AttachmentForm]'s template picker. Added for `AIO-2650`.
  final List<WorkflowPromptTemplate> templates;

  @override
  State<_StatusRow> createState() => _StatusRowState();
}

class _StatusRowState extends State<_StatusRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isHovered = false;
  String? _localError;

  /// Whether [_AttachmentForm] is currently expanded below this row's meta
  /// line. Added for `AIO-2650`.
  bool _attachmentFormOpen = false;

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
                      Flexible(
                        child: Text(
                          widget.status.name,
                          style: AionText.key.copyWith(color: c.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                            ticketTypeLabel(
                              context,
                              widget.scope!,
                            ).toUpperCase(),
                          ),
                          fg: _typeAccent(c, widget.scope!),
                          fill: _typeAccent(
                            c,
                            widget.scope!,
                          ).withValues(alpha: t.isDark ? 0.20 : 0.13),
                          border: null,
                        ),
                      const Spacer(),
                      // Skill attachment indicator — hidden on inherited rows
                      // (attachments live on the Base/owning status only),
                      // shown normally otherwise. Added for AIO-2650;
                      // Component Spec §4.
                      if (!isInherited) ...[
                        _AttachmentBadge(
                          attachment: widget.attachment,
                          onTap: () => setState(
                            () => _attachmentFormOpen = !_attachmentFormOpen,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (widget.scope == null)
                        _RoleDropdown(
                          status: widget.status,
                          allStatuses: widget.allStatuses,
                        ),
                    ],
                  ),
                ),
                if (_attachmentFormOpen) ...[
                  const SizedBox(height: 10),
                  _AttachmentForm(
                    existing: widget.attachment,
                    targetLabel: widget.status.displayName,
                    templates: widget.templates,
                    workflowStatusId: widget.status.id,
                    onDone: () => setState(() => _attachmentFormOpen = false),
                  ),
                ],
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
  TicketType.spec => c.typeSpec,
};

/// A compact role badge/selector for a Base-scope [_StatusRow] — built on
/// [SelectionMenu] (which already provides the `Overlay`/focus/`Escape`
/// mechanics `RoleDropdown`'s bespoke Component Spec §10.3 panel would
/// otherwise hand-roll a second copy of). One deviation from §10:
/// [SelectionMenu] excludes [currentValue] from its option list — the
/// same convention `MoveToStatusMenu` already established — rather than
/// showing all 4 rows with a checkmark on the current one.
class _RoleDropdown extends StatefulWidget {
  const _RoleDropdown({required this.status, required this.allStatuses});

  final WorkflowStatus status;
  final List<WorkflowStatus> allStatuses;

  @override
  State<_RoleDropdown> createState() => _RoleDropdownState();
}

class _RoleDropdownState extends State<_RoleDropdown> {
  // Component Spec §10.2 treats "Pressed / Open" the same as "Focused"
  // (both show the chip's ring) — mirrors `_LinkTypeSelectorRow`'s own
  // `isEmphasized = _isFocused || _isOpen` precedent
  // (`ticket_link_picker.dart`).
  bool _isFocused = false;
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final roles = <WorkflowStatusRole?>[null, ...WorkflowStatusRole.values];
    return SelectionMenu<WorkflowStatusRole?>(
      semanticsLabel: context.l10n.workflowSettingsChangeRole,
      items: roles,
      currentValue: widget.status.role,
      itemLabel: (r) => _roleLabel(context, r),
      itemBuilder: (context, c, item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _RoleChip(role: item),
      ),
      onSelected: (role) => context.read<WorkflowConfigCubit>().updateStatus(
        widget.status.copyWith(role: () => role),
      ),
      onOpenChanged: (open) => setState(() => _isOpen = open),
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      trigger: _RoleChip(
        role: widget.status.role,
        emphasized: _isFocused || _isOpen,
      ),
    );
  }
}

/// [_RoleDropdown]'s chip visual, both as the closed trigger and as each
/// open-menu row's content. Component Spec §10.1. [emphasized] (the
/// trigger's focused-or-open state, §10.2) adds the chip's focus ring —
/// always `false` for the plain rows an open menu renders.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role, this.emphasized = false});

  final WorkflowStatusRole? role;
  final bool emphasized;

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
        boxShadow: emphasized ? AionShadows.focus(c, t.isDark) : null,
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
    return _scopedStatuses(
      widget.allStatuses,
      widget.scope,
    ).any((s) => s.displayName.toLowerCase() == name);
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
    final existingNames = _scopedStatuses(
      widget.allStatuses,
      widget.scope,
    ).map((s) => s.name).toSet();
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
        (_scopedStatuses(
          widget.allStatuses,
          widget.scope,
        ).map((s) => s.sortOrder).fold<int>(-1, (a, b) => a > b ? a : b)) +
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
      return _AddStatusCollapsedButton(
        onTap: () => setState(() => _expanded = true),
      );
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
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (value) => setState(() => _isFocused = value),
      child: MouseRegion(
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
                color: _isHovered || _isFocused ? c.primary : c.borderStrong,
                width: 1.5,
              ),
              borderRadius: BorderRadius.all(AionRadius.lg),
              boxShadow: _isFocused ? AionShadows.focus(c, t.isDark) : null,
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
  bool _isFocused = false;

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
      onShowFocusHighlight: (value) => setState(() => _isFocused = value),
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
              boxShadow: _isFocused ? AionShadows.focus(c, t.isDark) : null,
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
    required this.attachment,
    required this.templates,
    required this.preconditionNodeCount,
  });

  final SddStage stage;
  final String? displayNameOverride;
  final bool isLast;

  /// This stage's configured [SkillAttachment], or `null`. Added for
  /// `AIO-2650`.
  final SkillAttachment? attachment;

  /// Every project-configured [WorkflowPromptTemplate], threaded down to
  /// [_AttachmentForm]'s template picker. Added for `AIO-2650`.
  final List<WorkflowPromptTemplate> templates;

  /// This stage's current transition-precondition field-check count, or `null`
  /// if unconfigured — [WorkflowConfigLoaded
  /// .transitionPreconditionNodeCounts]`[stage]`. Threaded down to
  /// [_PreconditionAffordance]'s count badge. Added for `AIO-1936`'s
  /// post-`/verify` follow-up.
  final int? preconditionNodeCount;

  @override
  State<_SddStageRenameRow> createState() => _SddStageRenameRowState();
}

class _SddStageRenameRowState extends State<_SddStageRenameRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// Whether [_AttachmentForm] is currently expanded below this row. Added for
  /// `AIO-2650`.
  bool _attachmentFormOpen = false;

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
    if (!_focusNode.hasFocus &&
        oldWidget.displayNameOverride != widget.displayNameOverride) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                // Skill attachment indicator, appended to the display-label
                // field's line, gap 10 (Component Spec §4). Added for
                // AIO-2650.
                const SizedBox(width: 10),
                _AttachmentBadge(
                  attachment: widget.attachment,
                  onTap: () => setState(
                    () => _attachmentFormOpen = !_attachmentFormOpen,
                  ),
                ),
                // "Configure precondition" affordance, appended after the
                // skill-attachment indicator — every precondition-bearing
                // stage (all of `SddStage.values` except `archived`, which has
                // no precondition and stays untouched — design.md §7/§5) gets
                // one. Added for AIO-1936; see its linked Documentation page,
                // §5. Excluding `archived` here was missed in the original
                // `/apply` pass and fixed in a follow-up `/verify` round (see
                // tasks.md's "Verify follow-ups (round 2)").
                if (widget.stage != SddStage.archived) ...[
                  const SizedBox(width: 10),
                  // Flexible (not a fixed size): the affordance itself
                  // decides compact (§5.1) vs. labeled (§5.2) from
                  // whatever width this leaves it — see its own
                  // dartdoc — rather than this row guessing from its
                  // own gross width, which the AttachmentBadge's
                  // variable width (short "+ Attach skill" vs. a long
                  // "KIND · CONFIDENCE" label) makes unreliable.
                  Flexible(
                    child: _PreconditionAffordance(
                      stage: widget.stage,
                      count: widget.preconditionNodeCount,
                    ),
                  ),
                ],
              ],
            ),
            if (_attachmentFormOpen) ...[
              const SizedBox(height: 10),
              _AttachmentForm(
                existing: widget.attachment,
                targetLabel: _fixedStageName(widget.stage),
                templates: widget.templates,
                sddStage: widget.stage,
                onDone: () => setState(() => _attachmentFormOpen = false),
              ),
            ],
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

/// The "Configure precondition" affordance appended to every
/// [_SddStageRenameRow] — tapping it pushes
/// `SddStagePreconditionEditorScreen(stage: ...)`, then (once that route pops)
/// reloads [WorkflowConfigCubit] so [count] reflects whatever was just edited.
/// Renders the compact §5.1 icon-only treatment or the labeled §5.2 treatment
/// depending on how much width its own `LayoutBuilder` gets — decided locally
/// rather than by `_SddStageRenameRow` guessing from its own gross row width,
/// since a wide `AttachmentBadge` (a long "KIND · CONFIDENCE" label) can leave
/// this affordance far less room than the row's total width would suggest.
/// Originally shipped always-compact, with no count wiring at all; both gaps
/// were closed for AIO-1936's post-`/verify` follow-up.
class _PreconditionAffordance extends StatefulWidget {
  const _PreconditionAffordance({required this.stage, required this.count});

  final SddStage stage;

  /// This stage's current field-check count, or `null`/`0` if
  /// unconfigured — [_SddStageRenameRow.preconditionNodeCount].
  final int? count;

  @override
  State<_PreconditionAffordance> createState() =>
      _PreconditionAffordanceState();
}

class _PreconditionAffordanceState extends State<_PreconditionAffordance> {
  bool _isHovered = false;
  bool _isFocused = false;

  /// Below this available width, render §5.1's icon-only treatment
  /// instead of §5.2's labeled one — chosen as the labeled treatment's
  /// own comfortable minimum (icon + a few characters of ellipsized
  /// label + count slot + caret, per this widget's own padding/gaps),
  /// not design.md §5.2's `420`px *row*-width figure, which described
  /// the outer row, not this affordance's own slot.
  static const _labeledMinWidth = 170.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _labeledMinWidth;
        return _build(context, compact);
      },
    );
  }

  Widget _build(BuildContext context, bool compact) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final hasCount = widget.count != null && widget.count! > 0;

    final decoration = BoxDecoration(
      color: _isHovered ? c.surfaceHover : const Color(0x00000000),
      border: Border.all(
        color: _isFocused ? c.primary : c.border,
        width: _isFocused ? 1.5 : 1,
      ),
      borderRadius: BorderRadius.all(
        compact ? AionRadius.iconBtnSm : AionRadius.md,
      ),
      boxShadow: _isFocused ? AionShadows.focus(c, t.isDark) : null,
    );
    final glyphColor = _isHovered ? c.primary : c.textSecondary;

    final child = compact
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              DecoratedBox(
                decoration: decoration,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.treeStructureLight,
                      size: 13,
                      color: glyphColor,
                    ),
                  ),
                ),
              ),
              if (hasCount)
                Positioned(
                  top: -4,
                  right: -4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.primarySubtle,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: Center(
                        child: Text(
                          '${widget.count}',
                          style: AionText.key.copyWith(
                            fontSize: 9,
                            height: 1,
                            color: c.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          )
        : DecoratedBox(
            decoration: decoration,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
              child: SizedBox(
                height: 30,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      PhosphorIcons.treeStructureLight,
                      size: 13,
                      color: glyphColor,
                    ),
                    const SizedBox(width: AionSpacing.sp8),
                    // Flexible+ellipsis, not a bare Text — the most
                    // compressible element in this row, so a tight
                    // Flexible allotment (a long AttachmentBadge label
                    // next to it) truncates here instead of forcing a
                    // hard RenderFlex overflow.
                    Flexible(
                      child: Text(
                        context.l10n.transitionPreconditionConfigureAffordance,
                        style: AionText.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasCount) ...[
                      const SizedBox(width: 6),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.primarySubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 1, 5, 1),
                          child: Text(
                            '${widget.count}',
                            style: AionText.key.copyWith(color: c.primary),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          context.l10n.transitionPreconditionCountNone,
                          style: AionText.bodySm.copyWith(color: c.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(width: AionSpacing.sp8),
                    PhosphorIcon(
                      PhosphorIcons.caretRightLight,
                      size: 6,
                      color: c.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          );

    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _open(context);
            return null;
          },
        ),
      },
      onShowFocusHighlight: (value) => setState(() => _isFocused = value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Semantics(
          button: true,
          label: context.l10n.transitionPreconditionConfigureAffordanceForStage(
            _fixedStageName(widget.stage),
          ),
          child: GestureDetector(onTap: () => _open(context), child: child),
        ),
      ),
    );
  }

  /// Pushes the precondition editor for [_PreconditionAffordance.stage]
  /// and, once it pops, reloads [WorkflowConfigCubit] so this row's count
  /// reflects whatever was just edited there.
  Future<void> _open(BuildContext context) async {
    final cubit = context.read<WorkflowConfigCubit>();
    await context.push(
      '/workspace/settings/workflow/sdd/${widget.stage.name}/precondition',
    );
    if (!mounted) return;
    cubit.load();
  }
}

// --------------------------------------------------------------------- Skill
// attachments (Phase 2) — `_AttachmentBadge`/`_AttachmentForm`, wired onto
// both `_StatusRow` (any scope) and `_SddStageRenameRow`. See `AIO-2650`'s
// Component Spec §2–§4.
//
// Deliberate simplifications from the pasted Component Spec, noted here
// rather than silently (mirrors this file's own existing precedent for
// the reorder-controls simplification above): the kind/confidence
// `SegmentedControl` atom (§3.1) is built as a plain row of toggle
// buttons ([_SegmentedChoice]) rather than a `GestureDetector` +
// `AnimatedAlign`-driven sliding thumb — same selectable behavior, far
// less animation-state machinery. The no-templates empty state's
// `1.5px dashed` border (§3.4) renders as a solid border — Aion's widget
// layer has no existing dashed-border primitive and hand-rolling a
// `CustomPainter` for one dashed rectangle isn't worth it for this single
// use. The kind glyph (§2.2) omits the template mark's two inset
// horizontal strokes — the outline alone already reads as "document" at
// 9×11px.
// ---------------------------------------------------------------------

/// A human-readable name for [attachment] — the delegated skill's literal
/// name, or the referenced [WorkflowPromptTemplate]'s name (falling back
/// to a defensive placeholder if it no longer resolves in [templates]).
/// Used by [_AttachmentForm]'s "EDIT SKILL · {name}" eyebrow.
String _attachmentDisplayName(
  SkillAttachment attachment,
  List<WorkflowPromptTemplate> templates,
) {
  if (attachment.kind == SkillAttachmentKind.delegatedSkill) {
    return attachment.skillName ?? '';
  }
  return templates
          .where((t) => t.id == attachment.templateId)
          .firstOrNull
          ?.name ??
      '(deleted template)';
}

/// A localized label for [kind] (segmented-control option / eyebrow use —
/// not pre-uppercased). Component Spec §3.1.
String _kindOptionLabel(BuildContext context, SkillAttachmentKind kind) =>
    switch (kind) {
      SkillAttachmentKind.aionNativeTemplate =>
        context.l10n.workflowSettingsKindTemplate,
      SkillAttachmentKind.delegatedSkill =>
        context.l10n.workflowSettingsKindDelegatedSkill,
    };

/// A localized, pre-uppercased label for [confidence] (segmented-control
/// option / badge use). Component Spec §1.2/§3.5.
String _confidenceOptionLabel(
  BuildContext context,
  AutomationConfidence confidence,
) => switch (confidence) {
  AutomationConfidence.auto => context.l10n.workflowSettingsConfidenceAuto,
  AutomationConfidence.gated => context.l10n.workflowSettingsConfidenceGated,
  AutomationConfidence.manual => context.l10n.workflowSettingsConfidenceManual,
};

/// The help line under [_AttachmentForm]'s confidence selector, describing
/// what the currently-selected [confidence] does. Component Spec §3.5.
String _confidenceHelpText(
  BuildContext context,
  AutomationConfidence confidence,
) => switch (confidence) {
  AutomationConfidence.auto => context.l10n.workflowSettingsConfidenceAutoHelp,
  AutomationConfidence.gated =>
    context.l10n.workflowSettingsConfidenceGatedHelp,
  AutomationConfidence.manual =>
    context.l10n.workflowSettingsConfidenceManualHelp,
};

/// [confidence]'s identity color, per Component Spec §1.2's "strongest →
/// quietest" mapping — `auto` reads as live/active, `gated` as a pending
/// decision, `manual` as quiet/opt-in.
Color _confidenceColor(AionColors c, AutomationConfidence confidence) =>
    switch (confidence) {
      AutomationConfidence.auto => c.primary,
      AutomationConfidence.gated => c.warning,
      AutomationConfidence.manual => c.textSecondary,
    };

/// A `9×9`/`9×11` mark encoding [kind] independent of color — a document
/// outline for [SkillAttachmentKind.aionNativeTemplate], a rotated-square
/// diamond for [SkillAttachmentKind.delegatedSkill]. Component Spec §2.2.
class _KindGlyph extends StatelessWidget {
  const _KindGlyph({required this.kind, required this.color});

  final SkillAttachmentKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (kind == SkillAttachmentKind.delegatedSkill) {
      return Transform.rotate(
        angle: 0.785,
        child: Container(width: 7, height: 7, color: color),
      );
    }
    return Container(
      width: 9,
      height: 11,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// A status/stage row's attachment indicator: a confidence-tinted chip
/// when [attachment] is non-`null` (kind glyph + `"{KIND} · {CONFIDENCE}"`
/// label), or a quiet `+ Attach skill` ghost affordance when it's `null`.
/// Tapping either calls [onTap] to open [_AttachmentForm]. Component Spec
/// §2.
class _AttachmentBadge extends StatefulWidget {
  const _AttachmentBadge({required this.attachment, required this.onTap});

  final SkillAttachment? attachment;
  final VoidCallback onTap;

  @override
  State<_AttachmentBadge> createState() => _AttachmentBadgeState();
}

class _AttachmentBadgeState extends State<_AttachmentBadge> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final attachment = widget.attachment;

    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (value) => setState(() => _isFocused = value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: attachment == null
              ? _buildResting(context, c, t)
              : _buildAttached(context, c, t, attachment),
        ),
      ),
    );
  }

  Widget _buildResting(BuildContext context, AionColors c, AionThemeData t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _isHovered
            ? c.primary.withValues(alpha: t.isDark ? 0.12 : 0.07)
            : const Color(0x00000000),
        borderRadius: BorderRadius.all(AionRadius.sm),
        boxShadow: _isFocused ? AionShadows.focus(c, t.isDark) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+',
              style: AionText.button.copyWith(fontSize: 13, color: c.primary),
            ),
            const SizedBox(width: 5),
            Text(
              context.l10n.workflowSettingsAttachSkill,
              style: AionText.button.copyWith(fontSize: 11.5, color: c.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttached(
    BuildContext context,
    AionColors c,
    AionThemeData t,
    SkillAttachment attachment,
  ) {
    final col = _confidenceColor(c, attachment.confidence);
    final isManual = attachment.confidence == AutomationConfidence.manual;
    final fill = isManual
        ? c.neutralTint(t.isDark)
        : col.withValues(alpha: t.isDark ? 0.20 : 0.13);
    final border = isManual
        ? c.neutralBorderTint(t.isDark)
        : (_isHovered ? col.withValues(alpha: 0.35) : null);
    final kindLabel = attachment.kind == SkillAttachmentKind.delegatedSkill
        ? context.l10n.workflowSettingsKindSkillBadge
        : _kindOptionLabel(context, attachment.kind).toUpperCase();
    final confidenceLabel = _confidenceOptionLabel(
      context,
      attachment.confidence,
    ).toUpperCase();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: border != null ? Border.all(color: border, width: 1) : null,
        borderRadius: BorderRadius.all(AionRadius.sm),
        boxShadow: _isFocused ? AionShadows.focus(c, t.isDark) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _KindGlyph(kind: attachment.kind, color: col),
            const SizedBox(width: 6),
            Text(
              '$kindLabel · $confidenceLabel',
              style: AionText.chip.copyWith(color: col),
            ),
          ],
        ),
      ),
    );
  }
}

/// A generic two/three-option choice row — [_AttachmentForm]'s kind and
/// confidence selectors. See this section's own simplification note for
/// why this isn't the Component Spec's literal sliding-thumb
/// `SegmentedControl`.
class _SegmentedChoice<T> extends StatelessWidget {
  const _SegmentedChoice({
    required this.label,
    required this.options,
    required this.optionLabel,
    required this.value,
    required this.onChanged,
    this.dotColor,
  });

  final String label;
  final List<T> options;
  final String Function(T) optionLabel;
  final T value;
  final ValueChanged<T> onChanged;
  final Color Function(T)? dotColor;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AionText.label.copyWith(color: c.textSecondary)),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.background,
            border: Border.all(color: c.border, width: 1),
            borderRadius: BorderRadius.all(AionRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                for (final option in options)
                  Expanded(
                    child: _SegmentButton(
                      label: optionLabel(option),
                      selected: option == value,
                      dotColor: dotColor?.call(option),
                      onTap: () => onChanged(option),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One [_SegmentedChoice] option button.
class _SegmentButton extends StatefulWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dotColor;

  @override
  State<_SegmentButton> createState() => _SegmentButtonState();
}

class _SegmentButtonState extends State<_SegmentButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final fill = widget.selected
        ? c.surface
        : (_isHovered ? c.surfaceHover : const Color(0x00000000));
    final textColor = widget.selected ? c.textPrimary : c.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(7),
            border: widget.selected
                ? Border.all(color: c.border, width: 1)
                : null,
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, t.isDark ? 0.45 : 0.09),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.dotColor != null) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.dotColor,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: 6, height: 6),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: AionText.button.copyWith(fontSize: 13, color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The template picker (kind = `aionNativeTemplate`) — a
/// [SelectionMenu]-backed dropdown field listing [templates] by name, or
/// (when [templates] is empty) the no-templates prompt-to-create state.
/// Component Spec §3.2/§3.4.
class _TemplatePickerField extends StatefulWidget {
  const _TemplatePickerField({
    required this.templates,
    required this.selectedId,
    required this.onSelected,
    required this.isError,
  });

  final List<WorkflowPromptTemplate> templates;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final bool isError;

  @override
  State<_TemplatePickerField> createState() => _TemplatePickerFieldState();
}

class _TemplatePickerFieldState extends State<_TemplatePickerField> {
  bool _isFocused = false;
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.workflowSettingsTemplateFieldLabel,
              style: AionText.label.copyWith(color: c.textSecondary),
            ),
            Text(
              context.l10n.commonRequiredMarker,
              style: AionText.label.copyWith(color: c.danger),
            ),
            const Spacer(),
            _ManageTemplatesLink(
              label: context.l10n.workflowSettingsManageTemplates,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (widget.templates.isEmpty)
          _NoTemplatesPrompt()
        else
          _buildPicker(context, c, t),
      ],
    );
  }

  Widget _buildPicker(BuildContext context, AionColors c, AionThemeData t) {
    final selected = widget.templates
        .where((tp) => tp.id == widget.selectedId)
        .firstOrNull;
    return SelectionMenu<WorkflowPromptTemplate?>(
      semanticsLabel: context.l10n.workflowSettingsTemplateFieldLabel,
      items: widget.templates,
      currentValue: selected,
      itemLabel: (tp) => tp?.name ?? '',
      onSelected: (tp) => widget.onSelected(tp?.id),
      onOpenChanged: (open) => setState(() => _isOpen = open),
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      trigger: DecoratedBox(
        decoration: BoxDecoration(
          color: c.background,
          border: Border.all(
            color: widget.isError ? c.danger : c.border,
            width: widget.isError ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.all(AionRadius.md),
          boxShadow: widget.isError
              ? [BoxShadow(color: c.errorRing(t.isDark), spreadRadius: 3)]
              : (_isFocused || _isOpen ? AionShadows.focus(c, t.isDark) : null),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected?.name ??
                      context.l10n.workflowSettingsSelectTemplateHint,
                  style: AionText.bodySm.copyWith(
                    fontSize: 14,
                    color: selected != null ? c.textPrimary : c.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PhosphorIcon(
                PhosphorIcons.caretDownLight,
                size: 12,
                color: c.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable link navigating to [WorkflowPromptTemplatesScreen]. Backs
/// both the template picker's "Manage templates →" link (§3.2) and the
/// no-templates state's "+ New template" link (§3.4).
class _ManageTemplatesLink extends StatefulWidget {
  const _ManageTemplatesLink({required this.label});

  final String label;

  @override
  State<_ManageTemplatesLink> createState() => _ManageTemplatesLinkState();
}

class _ManageTemplatesLinkState extends State<_ManageTemplatesLink> {
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
        onTap: () => context.push('/workspace/settings/workflow/templates'),
        child: Text(
          widget.label,
          style: AionText.label.copyWith(
            fontSize: 12,
            color: _isHovered ? c.primaryHover : c.primary,
          ),
        ),
      ),
    );
  }
}

/// The template picker's empty-project state — a prompt-to-create row
/// replacing the dropdown while zero templates exist. Component Spec
/// §3.4.
class _NoTemplatesPrompt extends StatelessWidget {
  const _NoTemplatesPrompt();

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border.all(color: c.borderStrong, width: 1.5),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            PhosphorIcon(
              PhosphorIcons.fileTextLight,
              size: 16,
              color: c.textMuted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.workflowSettingsNoTemplatesTitle,
                    style: AionText.cardTitle.copyWith(
                      fontSize: 13,
                      color: c.textSecondary,
                    ),
                  ),
                  Text(
                    context.l10n.workflowSettingsNoTemplatesSubtitle,
                    style: AionText.bodySm.copyWith(
                      fontSize: 12,
                      color: c.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ManageTemplatesLink(
              label: context.l10n.workflowSettingsNewTemplate,
            ),
          ],
        ),
      ),
    );
  }
}

/// The inline kind/name/confidence editor opened by tapping an
/// [_AttachmentBadge] — creates, updates, or removes a [SkillAttachment]
/// on exactly one target (either [workflowStatusId] or [sddStage], never
/// both). Component Spec §3.
class _AttachmentForm extends StatefulWidget {
  const _AttachmentForm({
    required this.existing,
    required this.targetLabel,
    required this.templates,
    this.workflowStatusId,
    this.sddStage,
    required this.onDone,
  });

  /// The attachment being edited, or `null` when creating a new one.
  final SkillAttachment? existing;

  /// The status/stage's display name, used in the eyebrow line.
  final String targetLabel;

  /// Every project-configured [WorkflowPromptTemplate], for the template
  /// picker.
  final List<WorkflowPromptTemplate> templates;

  /// This form's target `WorkflowStatus.id` — exactly one of this and
  /// [sddStage] is non-`null`.
  final String? workflowStatusId;

  /// This form's target [SddStage] — exactly one of this and
  /// [workflowStatusId] is non-`null`.
  final SddStage? sddStage;

  /// Called after Save/Cancel/Remove to collapse the form back to
  /// [_AttachmentBadge].
  final VoidCallback onDone;

  @override
  State<_AttachmentForm> createState() => _AttachmentFormState();
}

class _AttachmentFormState extends State<_AttachmentForm> {
  static const _uuid = Uuid();

  late SkillAttachmentKind _kind;
  String? _templateId;
  late final TextEditingController _skillNameController;
  late AutomationConfidence _confidence;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = existing?.kind ?? SkillAttachmentKind.aionNativeTemplate;
    _templateId = existing?.templateId;
    _skillNameController = TextEditingController(
      text: existing?.skillName ?? '',
    );
    _confidence = existing?.confidence ?? AutomationConfidence.gated;
    // Rebuilds on every keystroke so Save's enabled/disabled state and
    // the field-error line track what's being typed live — mirrors
    // _AddStatusControlState's established pattern for the same reason.
    _skillNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _skillNameController.dispose();
    super.dispose();
  }

  bool get _isValid => switch (_kind) {
    SkillAttachmentKind.aionNativeTemplate => _templateId != null,
    SkillAttachmentKind.delegatedSkill =>
      _skillNameController.text.trim().isNotEmpty,
  };

  void _save() {
    if (!_isValid) {
      setState(() => _touched = true);
      return;
    }
    final attachment = SkillAttachment(
      id: widget.existing?.id ?? _uuid.v4(),
      workflowStatusId: widget.workflowStatusId,
      sddStage: widget.sddStage,
      kind: _kind,
      templateId: _kind == SkillAttachmentKind.aionNativeTemplate
          ? _templateId
          : null,
      skillName: _kind == SkillAttachmentKind.delegatedSkill
          ? _skillNameController.text.trim()
          : null,
      confidence: _confidence,
    );
    final cubit = context.read<WorkflowConfigCubit>();
    if (widget.existing == null) {
      cubit.createAttachment(attachment);
    } else {
      cubit.updateAttachment(attachment);
    }
    widget.onDone();
  }

  void _remove() {
    final existing = widget.existing;
    if (existing != null) {
      context.read<WorkflowConfigCubit>().deleteAttachment(existing.id);
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isEditing = widget.existing != null;
    final showError = _touched && !_isValid;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.primary, width: 1.5),
        borderRadius: BorderRadius.all(AionRadius.lg),
        boxShadow: AionShadows.focus(c, t.isDark),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing
                  ? context.l10n.workflowSettingsEditSkillEyebrow(
                      _attachmentDisplayName(
                        widget.existing!,
                        widget.templates,
                      ),
                    )
                  : context.l10n.workflowSettingsAttachSkillEyebrow(
                      widget.targetLabel.toUpperCase(),
                    ),
              style: AionText.caption.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: 13),
            _SegmentedChoice<SkillAttachmentKind>(
              label: context.l10n.workflowSettingsKindLabel,
              options: SkillAttachmentKind.values,
              optionLabel: (k) => _kindOptionLabel(context, k),
              value: _kind,
              onChanged: (k) => setState(() {
                _kind = k;
                _touched = true;
              }),
            ),
            const SizedBox(height: 13),
            if (_kind == SkillAttachmentKind.aionNativeTemplate)
              _TemplatePickerField(
                templates: widget.templates,
                selectedId: _templateId,
                onSelected: (id) => setState(() {
                  _templateId = id;
                  _touched = true;
                }),
                isError: showError,
              )
            else
              AppTextField(
                controller: _skillNameController,
                labelText: context.l10n.workflowSettingsSkillNameFieldLabel,
                isRequired: true,
                hintText: context.l10n.workflowSettingsSkillNameHint,
                isError: showError,
                onSubmitted: (_) => _save(),
              ),
            if (showError) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('▲', style: TextStyle(fontSize: 11, color: c.danger)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _kind == SkillAttachmentKind.aionNativeTemplate
                          ? context.l10n.workflowSettingsPickTemplateError
                          : context.l10n.workflowSettingsEnterSkillNameError,
                      style: AionText.bodySm.copyWith(
                        fontSize: 12,
                        color: c.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 13),
            _SegmentedChoice<AutomationConfidence>(
              label: context.l10n.workflowSettingsConfidenceLabel,
              options: AutomationConfidence.values,
              optionLabel: (v) => _confidenceOptionLabel(context, v),
              dotColor: (v) => _confidenceColor(c, v),
              value: _confidence,
              onChanged: (v) => setState(() {
                _confidence = v;
                _touched = true;
              }),
            ),
            const SizedBox(height: 6),
            Text(
              _confidenceHelpText(context, _confidence),
              style: AionText.bodySm.copyWith(
                fontSize: 12.5,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                if (isEditing) ...[
                  AppButton(
                    label: context.l10n.workflowSettingsRemoveAttachment,
                    variant: AppButtonVariant.ghost,
                    onPressed: _remove,
                  ),
                  const Spacer(),
                ] else
                  const Spacer(),
                AppButton(
                  label: context.l10n.workflowSettingsCancel,
                  variant: AppButtonVariant.ghost,
                  onPressed: widget.onDone,
                ),
                const SizedBox(width: 9),
                AppButton(
                  label: context.l10n.workflowSettingsSaveAttachment,
                  onPressed: _touched && !_isValid ? null : _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
