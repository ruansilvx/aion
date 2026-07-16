// presentation/widgets/ticket_overflow_menu.dart — Shared ticket "more actions" overflow trigger (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/core/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';

/// The ticket "more actions" `⋯` trigger, shared across
/// `TicketDetailScreen`'s header, `TicketListTile` (list rows), and
/// `TicketBoardCard` (board cards). Opens a small overlay listing "Delete
/// ticket" (the only action today). Same `Overlay`/`LayerLink`/
/// `CompositedTransformFollower`/`mounted`-guard mechanics as
/// `MoveToStatusMenu` (`tickets_board_view.dart`) — a third instance of
/// that pattern, since this is an *action list* rather than a *value
/// picker* like `SelectionMenu`, so it isn't built on top of that widget.
/// Selecting "Delete ticket" opens [showAppConfirmDialog]; on
/// confirmation, calls [TicketsCubit.deleteTicket]. Renders distinct
/// default/hover/keyboard-focused/pressed/open fills and a focus ring, per
/// the design spec's interaction-state table.
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
                  constraints: const BoxConstraints(
                    minWidth: 180,
                    maxWidth: 240,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          button: true,
                          label: overlayContext.l10n.ticketDeleteMenuItem,
                          child: GestureDetector(
                            onTap: () {
                              _removeOverlay();
                              _onDeletePressed();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 9,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PhosphorIcon(
                                    PhosphorIcons.trashLight,
                                    size: 16,
                                    color: c.danger,
                                  ),
                                  const SizedBox(width: AionSpacing.sp8),
                                  Text(
                                    overlayContext.l10n.ticketDeleteMenuItem,
                                    style: AionText.bodySm.copyWith(
                                      color: c.danger,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    // Guards against setState-after-dispose — the same class of bug
    // project.md's AppDropdown overlay-dismiss crash note warns about.
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  Future<void> _onDeletePressed() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.ticketDeleteConfirmTitle,
      message: context.l10n.ticketDeleteConfirmMessage,
      confirmLabel: context.l10n.ticketDeleteConfirmAction,
      isDestructive: true,
    );
    if (confirmed && mounted) {
      context.read<TicketsCubit>().deleteTicket(widget.ticket.id);
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
            onShowFocusHighlight: (value) =>
                setState(() => _isFocused = value),
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
