// presentation/widgets/ticket_overflow_menu.dart — Shared ticket "more actions" overflow trigger (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
/// ticket" plus, for `idea` tickets only, "Discuss" (starts a standalone
/// human-gated conversation via [TicketsCubit.startIdeaDiscussion] and
/// navigates straight to it — see `AIO-2940`/`AIO-2941`; replaces the old
/// one-click "Promote to Epic"/"Promote to Bug" actions) and "Change to
/// Known Gap"/"Change to Open Question" (linking to an existing target
/// ticket via [TicketLinkPicker], no "create new" option, via
/// [TicketsCubit.reclassifyIdea]) above it. Same `Overlay`/
/// `LayerLink`/`CompositedTransformFollower`/`mounted`-guard mechanics as
/// `MoveToStatusMenu` (`tickets_board_view.dart`) — a third instance of
/// that pattern, since this is an *action list* rather than a *value
/// picker* like `SelectionMenu`, so it isn't built on top of that widget.
/// Selecting "Delete ticket" previews the cascade via
/// [TicketsCubit.previewTrashCount], opens [showAppConfirmDialog] with a
/// cascade-aware message, and on confirmation calls
/// [TicketsCubit.trashTicket] — a reversible move to trash, not a
/// permanent delete. The trigger itself renders distinct default/hover/
/// keyboard-focused/pressed/open fills and a focus ring, per the design
/// spec's interaction-state table. The action-list rows opened by the
/// trigger ("Delete ticket", "Discuss", "Change to Known Gap/Open
/// Question") are themselves keyboard-focusable and `Enter`/`Space`-
/// activatable too, via [OverlayMenuItem].
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

  /// The target type ([TicketType.knownGap]/[TicketType.openQuestion]) of the
  /// reclassify target picker currently showing, or `null` when the overlay is
  /// showing the root action list instead. Reset to `null` whenever the
  /// overlay closes. Added for `AIO-934`.
  TicketType? _reclassifyTargetType;

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
                    maxWidth: _reclassifyTargetType != null
                        ? 210
                        : (widget.ticket.type == TicketType.idea ? 210 : 240),
                  ),
                  child: StatefulBuilder(
                    builder: (context, setOverlayState) {
                      final reclassifyTargetType = _reclassifyTargetType;
                      if (reclassifyTargetType != null) {
                        return _ReclassifyChooser(
                          targetType: reclassifyTargetType,
                          onBack: () => setOverlayState(
                            () => _reclassifyTargetType = null,
                          ),
                          candidatesLoader: () async {
                            final all = await ticketsCubit.getAllTickets();
                            return all
                                .where((t) => t.id != widget.ticket.id)
                                .toList();
                          },
                          onTargetSelected: (target) {
                            ticketsCubit.reclassifyIdea(
                              widget.ticket,
                              targetType: reclassifyTargetType,
                              targetTicketId: target.id,
                            );
                            _removeOverlay();
                          },
                        );
                      }
                      return _RootMenu(
                        ticketType: widget.ticket.type,
                        onDiscussTap: () {
                          _removeOverlay();
                          _onDiscussPressed(ticketsCubit);
                        },
                        onReclassifyTap: (type) =>
                            setOverlayState(() => _reclassifyTargetType = type),
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
    _reclassifyTargetType = null;
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

  /// Starts [widget.ticket]'s Discuss conversation via
  /// [TicketsCubit.startIdeaDiscussion] and navigates straight to the
  /// spawned chat ticket once it exists — mirrors
  /// `TicketDetailScreen._advanceSddStage`'s identical "resolves once the
  /// chat exists, not once its first AI reply lands" navigation shape.
  /// [ticketsCubit] is passed in rather than re-read via `context.read`
  /// here, since the overlay may already be removed (and this `State`
  /// possibly unmounted) by the time the awaited call resolves. Added for
  /// `AIO-2941`.
  Future<void> _onDiscussPressed(TicketsCubit ticketsCubit) async {
    final chatId = await ticketsCubit.startIdeaDiscussion(widget.ticket);
    if (chatId != null && mounted) {
      context.go('/workspace/tickets/$chatId');
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

/// The root action-list content ("Discuss" and "Change to Known Gap"/
/// "Change to Open Question", for `idea` tickets only, then Delete ticket).
/// Per design.md §7.1 Widened "Promote" menu and `AIO-934` §4; "Discuss"
/// replaced the previous "Promote to Epic"/"Promote to Bug" pair per
/// `AIO-2940`/`AIO-2941`.
class _RootMenu extends StatelessWidget {
  const _RootMenu({
    required this.ticketType,
    required this.onDiscussTap,
    required this.onReclassifyTap,
    required this.onDeleteTap,
  });

  /// The overflow menu's ticket's type — the discuss/reclassify rows
  /// render only when this is [TicketType.idea].
  final TicketType ticketType;

  /// Called when "Discuss" is tapped. Added for `AIO-2941`.
  final VoidCallback onDiscussTap;

  /// Called with [TicketType.knownGap] or [TicketType.openQuestion] when the
  /// corresponding reclassify row is tapped. Added for `AIO-934`.
  final ValueChanged<TicketType> onReclassifyTap;

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
          if (ticketType == TicketType.idea) ...[
            _MenuActionRow(
              icon: PhosphorIcons.chatCircleTextLight,
              iconColor: c.typeIdea,
              labelColor: c.textPrimary,
              label: context.l10n.ticketOverflowDiscuss,
              onTap: onDiscussTap,
              // First row in the list — claims keyboard focus on open.
              autofocus: true,
            ),
            _MenuActionRow(
              icon: PhosphorIcons.warningCircleLight,
              iconColor: c.typeKnownGap,
              labelColor: c.textPrimary,
              label: context.l10n.ticketOverflowReclassifyToKnownGap,
              onTap: () => onReclassifyTap(TicketType.knownGap),
            ),
            _MenuActionRow(
              icon: PhosphorIcons.questionMarkLight,
              iconColor: c.typeOpenQuestion,
              labelColor: c.textPrimary,
              label: context.l10n.ticketOverflowReclassifyToOpenQuestion,
              onTap: () => onReclassifyTap(TicketType.openQuestion),
            ),
            Container(color: c.border, height: 1),
          ],
          _MenuActionRow(
            icon: PhosphorIcons.trashLight,
            iconColor: c.danger,
            labelColor: c.danger,
            label: context.l10n.ticketDeleteMenuItem,
            onTap: onDeleteTap,
            // Only the discuss/reclassify rows above it can precede it,
            // and those render only for idea tickets — so this is row 0
            // whenever they're absent.
            autofocus: ticketType != TicketType.idea,
          ),
        ],
      ),
    );
  }
}

/// A single tappable icon+label row — used by [_RootMenu]'s "Discuss",
/// "Change to Known Gap"/"Change to Open Question", and "Delete ticket"
/// actions.
class _MenuActionRow extends StatelessWidget {
  const _MenuActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  /// Whether this row claims keyboard focus as soon as the menu opens —
  /// set on the list's first row only.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return OverlayMenuItem(
      onTap: onTap,
      semanticsLabel: label,
      // Each row's own icon color doubles as its hover/pressed fill
      // accent — always `c.danger` for the destructive "Delete ticket"
      // row, each action's own type accent for the others.
      accent: iconColor,
      autofocus: autofocus,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        child: Row(
          children: [
            PhosphorIcon(icon, size: 16, color: iconColor),
            const SizedBox(width: AionSpacing.sp8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AionText.bodySm.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Change to Known Gap"/"Change to Open Question" target picker
/// (`AIO-934` §4.2): a back header, then a single "Pick target ticket" row
/// embedding [TicketLinkPicker] as a searchable existing-ticket picker —
/// there is no "create new" option, a reclassification target must already
/// exist. [candidatesLoader]/[onTargetSelected] are supplied by
/// [_TicketOverflowMenuState._showOverlay] using its own `context` — this
/// widget itself never reads `TicketsCubit`, since it's mounted inside the
/// [OverlayEntry]'s subtree, outside the ticket-detail route's provider
/// scope. Added for `AIO-934`.
class _ReclassifyChooser extends StatelessWidget {
  const _ReclassifyChooser({
    required this.targetType,
    required this.onBack,
    required this.candidatesLoader,
    required this.onTargetSelected,
  });

  /// Which type the reclassified ticket becomes — [TicketType.knownGap]
  /// or [TicketType.openQuestion].
  final TicketType targetType;

  /// Called when the back caret is tapped, returning to [_RootMenu].
  final VoidCallback onBack;

  /// Loads [TicketLinkPicker]'s candidates — every other existing ticket,
  /// unfiltered by type (a known gap/open question's target may be any
  /// existing ticket).
  final Future<List<Ticket>> Function() candidatesLoader;

  /// Called with the selected ticket once a target is picked.
  final ValueChanged<Ticket> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final isKnownGap = targetType == TicketType.knownGap;
    final headerTitle = isKnownGap
        ? context.l10n.ticketOverflowReclassifyToKnownGap
        : context.l10n.ticketOverflowReclassifyToOpenQuestion;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChooserHeader(onBack: onBack, title: headerTitle),
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
                  context.l10n.ticketReclassifyPickTarget,
                  style: AionText.bodySm.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TicketLinkPicker(
                candidatesLoader: candidatesLoader,
                // Reused purely as a searchable "pick a target ticket"
                // control (see `reclassifyIdea`) — no `TicketLink` is
                // ever created from this call site, so no link-type
                // choice is offered and the picked type is discarded.
                linkTypeOptions: const [],
                onSelected: (ticket, _) => onTargetSelected(ticket),
              ),
            ],
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
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AionText.label.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
