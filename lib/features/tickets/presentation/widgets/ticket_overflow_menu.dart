// presentation/widgets/ticket_overflow_menu.dart — Shared ticket "more actions" overflow trigger (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_link_picker.dart';

/// The ticket "more actions" `⋯` trigger, shared across
/// `TicketDetailScreen`'s header, `TicketListTile` (list rows), and
/// `TicketBoardCard` (board cards). Opens a small overlay listing "Delete
/// ticket" plus, for `signal` tickets only, "Promote to Epic" (linking to
/// an existing epic via [TicketLinkPicker], or creating a new one, via
/// [TicketsCubit.promoteSignalToEpic]) above it. Same `Overlay`/
/// `LayerLink`/`CompositedTransformFollower`/`mounted`-guard mechanics as
/// `MoveToStatusMenu` (`tickets_board_view.dart`) — a third instance of
/// that pattern, since this is an *action list* rather than a *value
/// picker* like `SelectionMenu`, so it isn't built on top of that widget.
/// Selecting "Delete ticket" previews the cascade via
/// [TicketsCubit.previewTrashCount], opens [showAppConfirmDialog] with a
/// cascade-aware message, and on confirmation calls
/// [TicketsCubit.trashTicket] — a reversible move to trash, not a
/// permanent delete. Renders distinct default/hover/keyboard-focused/
/// pressed/open fills and a focus ring, per the design spec's
/// interaction-state table.
class TicketOverflowMenu extends StatefulWidget {
  /// Creates a [TicketOverflowMenu] for [ticket]. Set [compact] to `true`
  /// for the smaller 26×26/16px footprint used inline on list rows and
  /// board cards; leave `false` (default) for the 37×37/20px footprint
  /// used in `TicketDetailScreen`'s header.
  const TicketOverflowMenu({
    super.key,
    required this.ticket,
    this.compact = false,
  });

  /// The ticket this menu's actions apply to.
  final Ticket ticket;

  /// Whether to render the smaller inline-trigger footprint (list rows,
  /// board cards) instead of the larger header footprint.
  final bool compact;

  @override
  State<TicketOverflowMenu> createState() => _TicketOverflowMenuState();
}

class _TicketOverflowMenuState extends State<TicketOverflowMenu> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  /// Whether the overlay is currently showing the "Promote to Epic"
  /// existing-vs-new chooser (§5.2) instead of the root action list.
  /// Reset to `false` whenever the overlay closes.
  bool _showPromoteChooser = false;

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final overlay = Overlay.of(context);
    // Resolved from this State's own context — not the OverlayEntry's,
    // which renders outside the ticket-detail route's provider scope —
    // and captured now for the closures below, same as `c`/`t` above.
    final ticketsCubit = context.read<TicketsCubit>();

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
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
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  boxShadow: AionShadows.card(c, t.isDark),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 180,
                    maxWidth: _showPromoteChooser ? 208 : 240,
                  ),
                  child: StatefulBuilder(
                    builder: (context, setOverlayState) {
                      return _showPromoteChooser
                          ? _PromoteChooser(
                              onBack: () => setOverlayState(
                                () => _showPromoteChooser = false,
                              ),
                              candidatesLoader: () async {
                                final all = await ticketsCubit
                                    .getAllTickets();
                                return all
                                    .where((t) => t.type == TicketType.epic)
                                    .toList();
                              },
                              onLinkSelected: (epic) {
                                ticketsCubit.promoteSignalToEpic(
                                  widget.ticket,
                                  existingEpicId: epic.id,
                                );
                                _removeOverlay();
                              },
                              onCreateNewTap: () {
                                ticketsCubit.promoteSignalToEpic(
                                  widget.ticket,
                                );
                                _removeOverlay();
                              },
                            )
                          : _RootMenu(
                              ticketType: widget.ticket.type,
                              onPromoteTap: () => setOverlayState(
                                () => _showPromoteChooser = true,
                              ),
                              onDeleteTap: () {
                                _removeOverlay();
                                _onDeletePressed();
                              },
                            );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _showPromoteChooser = false;
    // Guards against setState-after-dispose — the same class of bug
    // project.md's AppDropdown overlay-dismiss crash note warns about.
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  Future<void> _onDeletePressed() async {
    final total = await context.read<TicketsCubit>().previewTrashCount([
      widget.ticket.id,
    ]);
    if (!mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.ticketDeleteConfirmTitle,
      message: context.l10n.ticketTrashConfirmMessage(total),
      confirmLabel: context.l10n.ticketDeleteConfirmAction,
      tone: ConfirmDialogTone.reversible,
    );
    if (confirmed && mounted) {
      context.read<TicketsCubit>().trashTicket(widget.ticket.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final size = widget.compact ? 26.0 : 37.0;
    final iconSize = widget.compact ? 16.0 : 20.0;
    final radius = widget.compact ? AionRadius.iconBtnSm : AionRadius.iconBtn;

    final fill = _isPressed
        ? c.border
        : (_isOpen || _isHovered || _isFocused)
        ? c.surfaceHover
        : const Color(0x00000000);
    final boxShadow = _isFocused
        ? [
            BoxShadow(
              color: c.primary.withValues(alpha: t.isDark ? 0.30 : 0.16),
              spreadRadius: 3,
            ),
          ]
        : const <BoxShadow>[];

    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        label: context.l10n.ticketOverflowMenuLabel(widget.ticket.ticketId),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: FocusableActionDetector(
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _toggleOverlay();
                  return null;
                },
              ),
            },
            onShowFocusHighlight: (value) => setState(() => _isFocused = value),
            child: GestureDetector(
              onTap: _toggleOverlay,
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) => setState(() => _isPressed = false),
              onTapCancel: () => setState(() => _isPressed = false),
              child: AnimatedScale(
                scale: _isPressed ? 0.96 : 1.0,
                duration: const Duration(milliseconds: 80),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.all(radius),
                    boxShadow: boxShadow,
                  ),
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Center(
                      child: PhosphorIcon(
                        PhosphorIcons.dotsThreeLight,
                        size: iconSize,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The root action-list content (Promote to Epic, for `signal` tickets
/// only, then Delete ticket). Per design.md §5.1.
class _RootMenu extends StatelessWidget {
  const _RootMenu({
    required this.ticketType,
    required this.onPromoteTap,
    required this.onDeleteTap,
  });

  /// The overflow menu's ticket's type — "Promote to Epic" renders only
  /// when this is [TicketType.signal].
  final TicketType ticketType;

  /// Called when "Promote to Epic" is tapped.
  final VoidCallback onPromoteTap;

  /// Called when "Delete ticket" is tapped.
  final VoidCallback onDeleteTap;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ticketType == TicketType.signal) ...[
            _MenuActionRow(
              icon: PhosphorIcons.crownLight,
              iconColor: c.textSecondary,
              labelColor: c.textPrimary,
              label: context.l10n.ticketPromoteToEpicMenuItem,
              onTap: onPromoteTap,
            ),
            Container(color: c.border, height: 1),
          ],
          _MenuActionRow(
            icon: PhosphorIcons.trashLight,
            iconColor: c.danger,
            labelColor: c.danger,
            label: context.l10n.ticketDeleteMenuItem,
            onTap: onDeleteTap,
          ),
        ],
      ),
    );
  }
}

/// A single tappable, intrinsically-sized icon+label row — shared by
/// [_RootMenu]'s two actions.
class _MenuActionRow extends StatelessWidget {
  const _MenuActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(icon, size: 16, color: iconColor),
              const SizedBox(width: AionSpacing.sp8),
              Text(
                label,
                style: AionText.bodySm.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Promote to Epic" existing-vs-new chooser (§5.2/§5.3): a back
/// header, then "Link to existing epic" (an embedded [TicketLinkPicker])
/// and "Create new epic" (a direct action, no further dialog).
/// [candidatesLoader]/[onLinkSelected]/[onCreateNewTap] are supplied by
/// [_TicketOverflowMenuState._showOverlay] using its own `context` —
/// this widget itself never reads `TicketsCubit`, since it's mounted
/// inside the [OverlayEntry]'s subtree, outside the ticket-detail
/// route's provider scope.
class _PromoteChooser extends StatelessWidget {
  const _PromoteChooser({
    required this.onBack,
    required this.candidatesLoader,
    required this.onLinkSelected,
    required this.onCreateNewTap,
  });

  /// Called when the back caret is tapped, returning to [_RootMenu].
  final VoidCallback onBack;

  /// Loads [TicketLinkPicker]'s candidate epics.
  final Future<List<Ticket>> Function() candidatesLoader;

  /// Called with the selected epic when "Link to existing epic" resolves.
  final ValueChanged<Ticket> onLinkSelected;

  /// Called when "Create new epic" is tapped.
  final VoidCallback onCreateNewTap;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChooserHeader(
          onBack: onBack,
          title: context.l10n.ticketPromoteToEpicMenuItem,
        ),
        Container(color: c.border, height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(
            children: [
              PhosphorIcon(
                PhosphorIcons.linkLight,
                size: 16,
                color: c.textSecondary,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  context.l10n.ticketPromoteLinkExisting,
                  style: AionText.bodySm.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TicketLinkPicker(
                candidatesLoader: candidatesLoader,
                onSelected: onLinkSelected,
              ),
            ],
          ),
        ),
        Container(color: c.border, height: 1),
        Semantics(
          button: true,
          label: context.l10n.ticketPromoteCreateNew,
          child: GestureDetector(
            onTap: onCreateNewTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 10,
              ),
              child: Row(
                children: [
                  PhosphorIcon(
                    PhosphorIcons.plusLight,
                    size: 16,
                    color: c.primary,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      context.l10n.ticketPromoteCreateNew,
                      style: AionText.bodySm.copyWith(
                        color: c.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The chooser's back-navigation header row: a back caret + [title].
class _ChooserHeader extends StatelessWidget {
  const _ChooserHeader({required this.onBack, required this.title});

  final VoidCallback onBack;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: context.l10n.commonBack,
            child: GestureDetector(
              onTap: onBack,
              child: SizedBox(
                width: 26,
                height: 26,
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIcons.caretLeftLight,
                    size: 14,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(title, style: AionText.label.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}
