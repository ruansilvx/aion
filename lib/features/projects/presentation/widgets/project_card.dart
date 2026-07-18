// presentation/widgets/project_card.dart — ProjectCard Hub grid tile, its overflow menu, and remove confirmation (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/domain/entities/project.dart';

/// One project's card in the Hub grid: name, location, last-opened time,
/// baseline badge, an Open action, and an overflow menu with a
/// destructive Remove action. Tapping the card body (anywhere except the
/// overflow trigger and the Open button) opens the project — identical
/// to pressing [onOpen]. See
/// `aion-arch/changes/multi-project-hub/design.md` §1, §6, §7.
class ProjectCard extends StatefulWidget {
  /// Creates a [ProjectCard] for [project].
  const ProjectCard({
    super.key,
    required this.project,
    required this.onOpen,
    required this.onRemove,
  });

  /// The project this card represents.
  final Project project;

  /// Called when the card body or its Open button is activated.
  final VoidCallback onOpen;

  /// Called after the user confirms removal in the remove-confirmation
  /// dialog.
  final VoidCallback onRemove;

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _toggleOverflowMenu() {
    if (_overlayEntry != null) {
      _removeOverflowMenu();
    } else {
      _showOverflowMenu();
    }
  }

  void _showOverflowMenu() {
    final t = ThemeScope.of(context);
    final c = t.colors;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverflowMenu,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 6),
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.borderStrong, width: 1),
                  borderRadius: BorderRadius.all(AionRadius.md),
                  boxShadow: AionShadows.overlay(c, t.isDark),
                ),
                child: SizedBox(
                  width: 176,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _OverflowRow(
                          icon: PhosphorIcons.folderLight,
                          iconColor: c.textSecondary,
                          label: overlayContext.l10n.projectCardOpenMenuItem,
                          textColor: c.textPrimary,
                          hoverFill: c.surfaceHover,
                          onTap: () {
                            _removeOverflowMenu();
                            widget.onOpen();
                          },
                        ),
                        const SizedBox(height: 2),
                        DecoratedBox(
                          decoration: BoxDecoration(color: c.border),
                          child: const SizedBox(height: 1),
                        ),
                        const SizedBox(height: 2),
                        _OverflowRow(
                          icon: PhosphorIcons.trashLight,
                          iconColor: c.danger,
                          label: overlayContext.l10n.projectCardRemoveMenuItem,
                          textColor: c.danger,
                          hoverFill: c.destructiveTint(t.isDark),
                          onTap: () {
                            _removeOverflowMenu();
                            _confirmRemove(overlayContext);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() {});
  }

  void _removeOverflowMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    // Guards against setState-after-dispose — the same class of bug
    // project.md's AppDropdown overlay-dismiss crash note warns about.
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.removeProjectConfirmTitle,
      message: context.l10n.removeProjectConfirmMessage(widget.project.name),
      confirmLabel: context.l10n.removeProjectConfirmAction,
      tone: ConfirmDialogTone.destructive,
    );
    if (confirmed) {
      widget.onRemove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isMenuOpen = _overlayEntry != null;
    final isEmphasized = _isHovered || isMenuOpen;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        label: widget.project.name,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: FocusableActionDetector(
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onOpen();
                  return null;
                },
              ),
            },
            onShowFocusHighlight: (value) => setState(() => _isFocused = value),
            child: GestureDetector(
              onTap: widget.onOpen,
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) => setState(() => _isPressed = false),
              onTapCancel: () => setState(() => _isPressed = false),
              child: AnimatedScale(
                scale: _isPressed ? 0.985 : 1.0,
                duration: const Duration(milliseconds: 90),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  decoration: BoxDecoration(
                    color: isEmphasized ? c.surfaceHover : c.surface,
                    border: Border.all(
                      color: _isFocused
                          ? c.primary
                          : (isEmphasized ? c.borderStrong : c.border),
                      width: _isFocused ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.all(AionRadius.lg),
                    boxShadow: [
                      if (_isFocused) ...AionShadows.focus(c, t.isDark),
                      ...AionShadows.card(c, t.isDark),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TitleRow(
                        colors: c,
                        project: widget.project,
                        isMenuOpen: _overlayEntry != null,
                        onToggleOverflowMenu: _toggleOverflowMenu,
                      ),
                      const SizedBox(height: AionSpacing.sp12),
                      _LocationRow(colors: c, project: widget.project),
                      const SizedBox(height: AionSpacing.sp12),
                      _MetaRow(
                        colors: c,
                        project: widget.project,
                        lastOpenedLabel: _relativeLastOpened(
                          context,
                          widget.project.lastOpenedAt,
                        ),
                        onOpen: widget.onOpen,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Formats [lastOpenedAt] as a short relative label, resolving
  /// [AppLocalizations] plurals via `context.l10n` per the
  /// `Localization` convention.
  String _relativeLastOpened(BuildContext context, DateTime lastOpenedAt) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final elapsed = now.difference(lastOpenedAt);

    if (elapsed.inHours < 1) return l10n.projectCardLastOpenedJustNow;
    if (elapsed.inHours < 24) {
      return l10n.projectCardLastOpenedHoursAgo(elapsed.inHours);
    }
    final elapsedDays = elapsed.inDays;
    if (elapsedDays == 1) return l10n.projectCardLastOpenedYesterday;
    if (elapsedDays < 7) return l10n.projectCardLastOpenedDaysAgo(elapsedDays);
    return l10n.projectCardLastOpenedWeeksAgo(elapsedDays ~/ 7);
  }
}

/// [ProjectCard]'s title row: the project name and its overflow-menu
/// trigger.
class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.colors,
    required this.project,
    required this.isMenuOpen,
    required this.onToggleOverflowMenu,
  });

  final AionColors colors;
  final Project project;
  final bool isMenuOpen;
  final VoidCallback onToggleOverflowMenu;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AionText.cardTitle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.15,
              color: c.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: AionSpacing.sp8),
        Semantics(
          button: true,
          label: context.l10n.projectCardOverflowLabel(project.name),
          child: GestureDetector(
            onTap: onToggleOverflowMenu,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isMenuOpen ? c.surfaceHover : null,
                borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
              ),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIcons.dotsThreeLight,
                    size: 20,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// [ProjectCard]'s location row: root path (or app-storage label) with a
/// leading folder/database glyph.
class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.colors, required this.project});

  final AionColors colors;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final rootPath = project.rootPath;
    final locationText =
        rootPath ??
        context.l10n.projectCardAppStorageLabel(project.storageKey);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PhosphorIcon(
          rootPath != null
              ? PhosphorIcons.folderLight
              : PhosphorIcons.databaseLight,
          size: 14,
          color: c.textMuted,
        ),
        const SizedBox(width: AionSpacing.sp8),
        Expanded(
          child: Text(
            locationText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AionText.key.copyWith(fontSize: 11.5, color: c.textMuted),
          ),
        ),
      ],
    );
  }
}

/// [ProjectCard]'s meta row: baseline version badge, last-opened label,
/// and the Open action.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.colors,
    required this.project,
    required this.lastOpenedLabel,
    required this.onOpen,
  });

  final AionColors colors;
  final Project project;
  final String lastOpenedLabel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceHover,
            border: Border.all(color: c.border, width: 1),
            borderRadius: BorderRadius.all(AionRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Text(
              'v${project.baselineVersion}',
              style: AionText.key.copyWith(
                fontSize: 10.5,
                color: c.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          lastOpenedLabel,
          style: AionText.time.copyWith(color: c.textMuted),
        ),
        const Spacer(),
        _OpenButton(colors: c, onOpen: onOpen),
      ],
    );
  }
}

/// [ProjectCard]'s Open action button.
class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.colors, required this.onOpen});

  final AionColors colors;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onOpen,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceHover,
          border: Border.all(color: c.borderStrong, width: 1),
          borderRadius: BorderRadius.all(AionRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            context.l10n.projectCardOpenAction,
            style: AionText.button.copyWith(fontSize: 13, color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// One row in [ProjectCard]'s overflow menu (icon + label, hoverable).
class _OverflowRow extends StatelessWidget {
  const _OverflowRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.textColor,
    required this.hoverFill,
    required this.onTap,
  });

  final PhosphorIconData icon;
  final Color iconColor;
  final String label;
  final Color textColor;
  final Color hoverFill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HoverableMenuRow(
      hoverFill: hoverFill,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(icon, size: 13, color: iconColor),
          const SizedBox(width: AionSpacing.sp8),
          Text(
            label,
            style: AionText.bodySm.copyWith(color: textColor, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

/// A single hoverable overflow-menu row, shared by the "Open" and
/// "Remove" rows in [ProjectCard]'s overflow menu.
class _HoverableMenuRow extends StatefulWidget {
  const _HoverableMenuRow({
    required this.hoverFill,
    required this.onTap,
    required this.child,
  });

  final Color hoverFill;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_HoverableMenuRow> createState() => _HoverableMenuRowState();
}

class _HoverableMenuRowState extends State<_HoverableMenuRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _isHovered ? widget.hoverFill : null,
            borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
