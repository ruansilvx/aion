// core/routing/workspace_nav_shell.dart — WorkspaceNavShell persistent navigation chrome (core layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart'
    show ticketsErrorMessage;
import 'package:aion/features/tickets/presentation/widgets/notification_dropdown.dart';

/// Persistent navigation chrome wrapping every `/workspace/*` route's
/// content: a left sidebar on wide layouts, a bottom tab bar on narrow
/// ones, both offering the same three destinations (Tickets,
/// Documentation, Inbox — see
/// `aion-arch/changes/new-project-onboarding-inbox/design.md` §1) plus a
/// shared secondary-actions trigger (Switch Project, Trash).
///
/// Rendered by `WorkspaceShell` around its routed `child` — see
/// `app_router.dart`. Replaces the ad hoc per-screen header buttons
/// (`_SwitchProjectButton`/`_DocumentationEntryButton`/`_TrashEntryButton`)
/// that `TicketsListScreen` used to own alone, and gives `DocumentationScreen`
/// a way back to Tickets for the first time on every platform.
///
/// Also owns an app-wide `BlocListener<TicketsCubit, TicketsState>`
/// that shows an [AppToast] for every classified [TicketsErrorReason]
/// [TicketsCubit] emits, regardless of which `/workspace/*` screen is
/// currently active — `app_router.dart`'s single `ShellRoute` wraps
/// Tickets, Documentation, and Settings alike, and
/// `BlocProvider<TicketsCubit>` sits above this widget in the tree, so
/// no new provider wiring is needed. Added for
/// `aion-arch/changes/board-execution-indicators-and-notifications`.
class WorkspaceNavShell extends StatelessWidget {
  /// Creates a [WorkspaceNavShell]. [currentLocation] drives which
  /// destination renders as active; [child] is the routed screen content.
  const WorkspaceNavShell({
    super.key,
    required this.currentLocation,
    required this.child,
  });

  /// The current route path (`GoRouterState.uri.path`), used to compute
  /// the active [_NavDestination] via [_destinationFor].
  final String currentLocation;

  /// The routed screen content for the current `/workspace/*` location.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final destination = _destinationFor(currentLocation);

    void selectTickets() => context.go('/workspace/tickets');
    void selectDocumentation() => context.go('/workspace/documentation');
    void selectInbox() => context.go('/workspace/inbox');

    return BlocListener<TicketsCubit, TicketsState>(
      listenWhen: (previous, current) => current is TicketsError,
      listener: (context, state) {
        final reason = (state as TicketsError).reason;
        if (reason == null) return; // raw/unclassified — screen-local only
        AppToast.show(context, ticketsErrorMessage(context, reason));
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth <= _kBreakpoint;
          return isCompact
              ? _CompactShell(
                  active: destination,
                  onSelectTickets: selectTickets,
                  onSelectDocumentation: selectDocumentation,
                  onSelectInbox: selectInbox,
                  child: child,
                )
              : _WideShell(
                  active: destination,
                  onSelectTickets: selectTickets,
                  onSelectDocumentation: selectDocumentation,
                  onSelectInbox: selectInbox,
                  child: child,
                );
        },
      ),
    );
  }
}

/// Width, in logical pixels, at or below which [WorkspaceNavShell] renders
/// [_CompactShell] (bottom tab bar) instead of [_WideShell] (sidebar).
/// Matches the existing `LayoutBuilder` + `constraints.maxWidth`
/// responsive convention (`MarkdownEditor`'s 640, `TrashScreen`'s 380).
const double _kBreakpoint = 900;

/// The three top-level sections [WorkspaceNavShell] can switch between.
/// Built to make adding a future section a matter of extending this enum
/// plus [_destinationFor], not restructuring the shell.
enum _NavDestination {
  /// `/workspace/tickets` and its sub-routes (`/new`, `/trash`, `/:id`).
  tickets,

  /// `/workspace/documentation` and `/workspace/pages/*` — pages are
  /// Documentation's content even though their routes live outside the
  /// `/workspace/documentation` path prefix.
  documentation,

  /// `/workspace/inbox` — the Inbox launcher/history destination. An
  /// Inbox-spawned chat does **not** get its own route prefix; it renders
  /// via the existing `/workspace/tickets/:id` route, so opening one from
  /// the Inbox history list resolves to [tickets], not this destination —
  /// same as any other ticket detail view. Added for
  /// `aion-arch/changes/new-project-onboarding-inbox`.
  inbox,
}

/// Resolves [location] to the [_NavDestination] it belongs to.
/// `/workspace/documentation` and `/workspace/pages/*` both resolve to
/// [_NavDestination.documentation]; `/workspace/inbox` resolves to
/// [_NavDestination.inbox]; everything else under `/workspace/tickets*`
/// resolves to [_NavDestination.tickets].
_NavDestination _destinationFor(String location) {
  if (location.startsWith('/workspace/documentation') ||
      location.startsWith('/workspace/pages')) {
    return _NavDestination.documentation;
  }
  if (location.startsWith('/workspace/inbox')) {
    return _NavDestination.inbox;
  }
  return _NavDestination.tickets;
}

/// Wide-layout (`> 900px`) rendering: a fixed-width left sidebar beside
/// the routed [child].
class _WideShell extends StatelessWidget {
  /// Creates a [_WideShell].
  const _WideShell({
    required this.active,
    required this.onSelectTickets,
    required this.onSelectDocumentation,
    required this.onSelectInbox,
    required this.child,
  });

  /// The currently active destination, used to highlight the matching
  /// nav item.
  final _NavDestination active;

  /// Navigates to `/workspace/tickets`.
  final VoidCallback onSelectTickets;

  /// Navigates to `/workspace/documentation`.
  final VoidCallback onSelectDocumentation;

  /// Navigates to `/workspace/inbox`.
  final VoidCallback onSelectInbox;

  /// The routed screen content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Sidebar(
          active: active,
          onSelectTickets: onSelectTickets,
          onSelectDocumentation: onSelectDocumentation,
          onSelectInbox: onSelectInbox,
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The sidebar's top zone: the AION hexagon emblem plus wordmark, sitting
/// above the nav items. Purely decorative — per design.md's Claude Design
/// visual spec §1, not itself interactive.
class _BrandHeader extends StatelessWidget {
  /// Creates a [_BrandHeader].
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 20),
      child: Row(
        children: [
          PhosphorIcon(PhosphorIcons.hexagonFill, size: 26, color: c.primary),
          const SizedBox(width: 10),
          Text(
            'AION',
            style: AionText.caption.copyWith(color: c.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The fixed-width (244px) left sidebar rendered by [_WideShell]: the
/// brand header, then the three [_NavItem] destinations, then flexible
/// space, then [_NotificationBellTrigger] beside [_SecondaryActionsTrigger],
/// both anchored to the bottom. Added
/// [_NotificationBellTrigger] for
/// `aion-arch/changes/pr-metadata-and-notification-center`; see that
/// change's design.md Component Spec §2.
class _Sidebar extends StatelessWidget {
  /// Creates a [_Sidebar].
  const _Sidebar({
    required this.active,
    required this.onSelectTickets,
    required this.onSelectDocumentation,
    required this.onSelectInbox,
  });

  /// The currently active destination.
  final _NavDestination active;

  /// Navigates to `/workspace/tickets`.
  final VoidCallback onSelectTickets;

  /// Navigates to `/workspace/documentation`.
  final VoidCallback onSelectDocumentation;

  /// Navigates to `/workspace/inbox`.
  final VoidCallback onSelectInbox;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.border, width: 1)),
      ),
      child: SizedBox(
        width: 244,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BrandHeader(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavItem(
                    compact: false,
                    active: active == _NavDestination.tickets,
                    icon: PhosphorIcons.squaresFourLight,
                    label: context.l10n.ticketsListTitle,
                    onTap: onSelectTickets,
                  ),
                  const SizedBox(height: AionSpacing.sp4),
                  _NavItem(
                    compact: false,
                    active: active == _NavDestination.documentation,
                    icon: PhosphorIcons.bookOpenLight,
                    label: context.l10n.documentationTitle,
                    onTap: onSelectDocumentation,
                  ),
                  const SizedBox(height: AionSpacing.sp4),
                  _NavItem(
                    compact: false,
                    active: active == _NavDestination.inbox,
                    icon: PhosphorIcons.trayLight,
                    label: context.l10n.inboxScreenTitle,
                    onTap: onSelectInbox,
                  ),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    _NotificationBellTrigger(compact: false),
                    SizedBox(width: AionSpacing.sp8),
                    _SecondaryActionsTrigger(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact-layout (`<= 900px`) rendering: the routed [child] above a
/// fixed-height bottom tab bar.
class _CompactShell extends StatelessWidget {
  /// Creates a [_CompactShell].
  const _CompactShell({
    required this.active,
    required this.onSelectTickets,
    required this.onSelectDocumentation,
    required this.onSelectInbox,
    required this.child,
  });

  /// The currently active destination, used to highlight the matching
  /// nav item.
  final _NavDestination active;

  /// Navigates to `/workspace/tickets`.
  final VoidCallback onSelectTickets;

  /// Navigates to `/workspace/documentation`.
  final VoidCallback onSelectDocumentation;

  /// Navigates to `/workspace/inbox`.
  final VoidCallback onSelectInbox;

  /// The routed screen content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: child),
        _BottomTabBar(
          active: active,
          onSelectTickets: onSelectTickets,
          onSelectDocumentation: onSelectDocumentation,
          onSelectInbox: onSelectInbox,
        ),
      ],
    );
  }
}

/// The fixed-height (72px + bottom safe area) bottom tab bar rendered by
/// [_CompactShell]: the three [_NavItem] destinations plus the
/// [_NotificationBellTrigger] and [_SecondaryActionsTrigger]. Per
/// `aion-arch/changes/new-project-onboarding-inbox/design.md` §1.3, the
/// trigger cell is a fixed 56px [SizedBox] (not `Expanded`) — the three
/// destinations stay equal `Expanded` thirds of the remaining space,
/// rather than all cells splitting evenly, since a destination must
/// stay tappable/legible while the trailing triggers are just fixed
/// 56px cells that never needed a full share. [_NotificationBellTrigger]
/// gets its own fixed 56px cell, placed before
/// [_SecondaryActionsTrigger]'s — see design.md Component Spec §3.1.
/// Added for `aion-arch/changes/pr-metadata-and-notification-center`.
class _BottomTabBar extends StatelessWidget {
  /// Creates a [_BottomTabBar].
  const _BottomTabBar({
    required this.active,
    required this.onSelectTickets,
    required this.onSelectDocumentation,
    required this.onSelectInbox,
  });

  /// The currently active destination.
  final _NavDestination active;

  /// Navigates to `/workspace/tickets`.
  final VoidCallback onSelectTickets;

  /// Navigates to `/workspace/documentation`.
  final VoidCallback onSelectDocumentation;

  /// Navigates to `/workspace/inbox`.
  final VoidCallback onSelectInbox;

  /// Below this bar *content* width (the bar's own width minus its 12+12
  /// horizontal padding), the three destination cells step down to a
  /// tighter icon/label size — design.md §1.3's "Secondary tightening at
  /// ultra-narrow widths."
  static const _kUltraNarrowContentWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 14 + bottomInset),
        child: SizedBox(
          height: 72,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final ultraNarrow =
                  constraints.maxWidth < _kUltraNarrowContentWidth;
              return Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      compact: true,
                      ultraNarrow: ultraNarrow,
                      active: active == _NavDestination.tickets,
                      icon: PhosphorIcons.squaresFourLight,
                      label: context.l10n.ticketsListTitle,
                      onTap: onSelectTickets,
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      compact: true,
                      ultraNarrow: ultraNarrow,
                      active: active == _NavDestination.documentation,
                      icon: PhosphorIcons.bookOpenLight,
                      label: context.l10n.documentationTitle,
                      onTap: onSelectDocumentation,
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      compact: true,
                      ultraNarrow: ultraNarrow,
                      active: active == _NavDestination.inbox,
                      icon: PhosphorIcons.trayLight,
                      label: context.l10n.inboxScreenTitle,
                      onTap: onSelectInbox,
                    ),
                  ),
                  const SizedBox(
                    width: 56,
                    child: Center(child: _NotificationBellTrigger(compact: true)),
                  ),
                  const SizedBox(
                    width: 56,
                    child: Center(child: _SecondaryActionsTrigger()),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A single tappable nav destination row/cell, shared between [_Sidebar]
/// (icon-beside-label, [compact] `false`) and [_BottomTabBar]
/// (icon-above-label, [compact] `true`). Handles its own hover/focus/
/// press visual states; [active] drives the selected-section tint.
class _NavItem extends StatefulWidget {
  /// Creates a [_NavItem].
  const _NavItem({
    required this.compact,
    this.ultraNarrow = false,
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  /// `true` for the bottom-tab-bar (icon-above-label) layout, `false`
  /// for the sidebar (icon-beside-label) layout.
  final bool compact;

  /// Only meaningful when [compact] is `true`: below the bottom tab
  /// bar's 360px ultra-narrow content-width threshold, steps the icon
  /// 22 → 20px and the label 11 → 10.5px (design.md §1.3). Ignored in
  /// the (non-compact) sidebar layout.
  final bool ultraNarrow;

  /// Whether this item represents the currently active destination.
  final bool active;

  /// The leading Phosphor Light glyph.
  final IconData icon;

  /// The visible label — always navigates to that destination's root
  /// route when tapped, even from a sub-route of that destination.
  final String label;

  /// Called on tap or keyboard activation.
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final isEmphasized = _isHovered || _isPressed;
    final fill = widget.active
        ? c.primarySubtle
        : (isEmphasized ? c.surfaceHover : const Color(0x00000000));
    final foreground = widget.active ? c.primary : c.textSecondary;
    final boxShadow = _isFocused
        ? AionShadows.focus(c, t.isDark)
        : const <BoxShadow>[];

    final compactAndUltraNarrow = widget.compact && widget.ultraNarrow;
    final iconSize = widget.compact
        ? (compactAndUltraNarrow ? 20.0 : 22.0)
        : 20.0;
    final icon = PhosphorIcon(widget.icon, size: iconSize, color: foreground);
    final label = Text(
      widget.label,
      style: widget.compact
          ? AionText.navTabLabel.copyWith(
              color: foreground,
              fontSize: compactAndUltraNarrow ? 10.5 : null,
            )
          : AionText.cardTitle.copyWith(color: foreground, letterSpacing: -0.07),
      overflow: TextOverflow.ellipsis,
    );

    final content = widget.compact
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: AionSpacing.sp4),
              label,
            ],
          )
        : Row(
            children: [
              icon,
              const SizedBox(width: AionSpacing.sp12),
              Expanded(child: label),
            ],
          );

    return Semantics(
      button: true,
      label: widget.label,
      selected: widget.active,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.97 : 1.0,
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: double.infinity,
                padding: widget.compact
                    ? const EdgeInsets.symmetric(vertical: 8, horizontal: 4)
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.all(AionRadius.md),
                  boxShadow: boxShadow,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The secondary-actions options offered behind [_SecondaryActionsTrigger]
/// — utility destinations that don't warrant a top-level [_NavDestination]
/// slot.
enum _SecondaryAction {
  /// Returns to `/hub` to switch the active project.
  switchProject,

  /// Navigates to `/workspace/tickets/trash`.
  trash,

  /// Navigates to `/workspace/settings`.
  settings,

  /// Navigates to `/workspace/settings/workflow`. Added for
  /// `aion-arch/changes/configurable-ticket-workflow`.
  workflowSettings,
}

/// The shared secondary-actions entry point rendered by both [_Sidebar]
/// and [_BottomTabBar]: the existing 38×38 "U" avatar-circle visual, now
/// wired as a [SelectionMenu] trigger offering "Switch Project" and
/// "Trash". Identical widget in both layouts — not two different
/// secondary-action mechanisms per breakpoint.
class _SecondaryActionsTrigger extends StatefulWidget {
  /// Creates a [_SecondaryActionsTrigger].
  const _SecondaryActionsTrigger();

  @override
  State<_SecondaryActionsTrigger> createState() =>
      _SecondaryActionsTriggerState();
}

class _SecondaryActionsTriggerState extends State<_SecondaryActionsTrigger> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final isEmphasized = _isHovered || _isPressed || _isFocused || _isMenuOpen;
    final borderColor = isEmphasized ? c.borderStrong : c.border;
    final boxShadow = (_isFocused || _isMenuOpen)
        ? AionShadows.focus(c, t.isDark)
        : const <BoxShadow>[];

    // No nested FocusableActionDetector/GestureDetector here — SelectionMenu
    // already wraps `trigger` in its own tap-to-toggle GestureDetector and
    // focus/activation FocusableActionDetector; duplicating either would
    // create a second, competing gesture recognizer and tab stop for the
    // same control. Hover uses MouseRegion (doesn't enter the gesture
    // arena); press uses Listener (raw pointer events, same reason); focus
    // is reported back via SelectionMenu.onFocusChange below instead of a
    // second Focus node.
    final avatar = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) => setState(() => _isPressed = false),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.surfaceHover,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 1),
              boxShadow: boxShadow,
            ),
            child: Center(
              child: Text(
                'U',
                style: AionText.key.copyWith(color: c.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );

    return SelectionMenu<_SecondaryAction?>(
      trigger: avatar,
      items: _SecondaryAction.values,
      currentValue: null,
      openUpward: true,
      onOpenChanged: (open) => setState(() => _isMenuOpen = open),
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      itemLabel: (action) => switch (action) {
        _SecondaryAction.switchProject => context.l10n.projectSwitcherMenuLabel,
        _SecondaryAction.trash => context.l10n.ticketTrashScreenTitle,
        _SecondaryAction.settings => context.l10n.settingsScreenTitle,
        _SecondaryAction.workflowSettings =>
          context.l10n.workflowSettingsScreenTitle,
        null => '',
      },
      onSelected: (action) {
        switch (action) {
          case _SecondaryAction.switchProject:
            context.go('/hub');
          case _SecondaryAction.trash:
            context.go('/workspace/tickets/trash');
          case _SecondaryAction.settings:
            context.go('/workspace/settings');
          case _SecondaryAction.workflowSettings:
            context.go('/workspace/settings/workflow');
          case null:
            break;
        }
      },
      semanticsLabel: context.l10n.navShellSecondaryMenuLabel,
    );
  }
}

/// The notification-center bell trigger, rendered beside
/// [_SecondaryActionsTrigger] in both [_Sidebar] (wide) and
/// [_BottomTabBar] (compact) — one widget, two geometry variants keyed
/// by [compact], per design.md Component Spec §2/§3. Shows
/// `TicketsCubit.unreadNotificationCount`'s live badge and opens
/// [NotificationDropdownPanel] in an `Overlay`, built on the same
/// `LayerLink`/`CompositedTransformFollower`/`mounted`-guard mechanics
/// `TicketOverflowMenu` already uses — a fourth instance of that
/// pattern (an action list, not a `SelectionMenu` value picker). Added
/// for `aion-arch/changes/pr-metadata-and-notification-center`.
class _NotificationBellTrigger extends StatefulWidget {
  /// Creates a [_NotificationBellTrigger]. Set [compact] `true` for the
  /// bottom-tab-bar's 56px-cell/22px-glyph variant, `false` (default) for
  /// the sidebar's 38×38 variant.
  const _NotificationBellTrigger({required this.compact});

  /// Whether to render the compact bottom-tab-bar geometry instead of
  /// the wide sidebar geometry.
  final bool compact;

  @override
  State<_NotificationBellTrigger> createState() =>
      _NotificationBellTriggerState();
}

class _NotificationBellTriggerState extends State<_NotificationBellTrigger> {
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
    final overlay = Overlay.of(context);
    // Resolved from this State's own context — not the OverlayEntry's,
    // which renders outside the route's provider scope — mirrors
    // TicketOverflowMenu's identical precaution.
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
              offset: const Offset(0, -8),
              targetAnchor: widget.compact
                  ? Alignment.topRight
                  : Alignment.topLeft,
              followerAnchor: widget.compact
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft,
              child: _AnimatedDropdownEntrance(
                child: NotificationDropdownPanel(
                  ticketsCubit: ticketsCubit,
                  onDismiss: _removeOverlay,
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
    // Guards against setState-after-dispose — same precaution
    // TicketOverflowMenu takes.
    if (mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final ticketsCubit = context.read<TicketsCubit>();

    final borderColor = _isOpen || _isHovered || _isFocused
        ? c.borderStrong
        : c.border;
    // Default textSecondary, hover textPrimary, menu-open primary — per
    // design.md Component Spec §2.2/§3.2's interactive-state tables
    // (menu-open takes precedence over hover).
    final glyphColor = _isOpen
        ? c.primary
        : (_isHovered ? c.textPrimary : c.textSecondary);
    final boxShadow = (_isFocused || _isOpen)
        ? AionShadows.focus(c, t.isDark)
        : const <BoxShadow>[];

    final glyph = PhosphorIcon(
      PhosphorIcons.bellSimpleLight,
      size: widget.compact ? 22 : 20,
      color: glyphColor,
    );

    final tile = widget.compact
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: (_isHovered || _isPressed)
                  ? c.surfaceHover
                  : const Color(0x00000000),
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Center(child: glyph),
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.surfaceHover,
              border: Border.all(color: borderColor, width: 1),
              borderRadius: BorderRadius.all(AionRadius.iconBtn),
              boxShadow: boxShadow,
            ),
            child: Center(child: glyph),
          );

    return CompositedTransformTarget(
      link: _layerLink,
      child: ValueListenableBuilder<int>(
        valueListenable: ticketsCubit.unreadNotificationCount,
        builder: (context, count, _) {
          return Semantics(
            button: true,
            label: context.l10n.notificationBellSemantics(count),
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
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.easeOut,
                    child: SizedBox(
                      width: widget.compact ? 56 : 38,
                      height: widget.compact ? 56 : 38,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          tile,
                          if (count > 0)
                            Positioned(
                              top: widget.compact ? 14 : -5,
                              right: widget.compact ? 12 : -5,
                              child: _UnreadCountBadge(count: count),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Wraps [child] (the [NotificationDropdownPanel]) with the fade + 4px
/// rise entrance motion per design.md Component Spec §4.3 — 120ms
/// `Curves.easeOut`, opacity 0→1 and a `Transform.translate` from
/// `Offset(0, 4)` to `Offset.zero`. Runs once on mount; no exit
/// animation (the overlay is removed immediately on dismiss, matching
/// `TicketOverflowMenu`'s existing immediate-removal precedent).
class _AnimatedDropdownEntrance extends StatelessWidget {
  const _AnimatedDropdownEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 4),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// The unread-count disc anchored to [_NotificationBellTrigger]'s
/// top-right corner. Per design.md Component Spec §2.4: `1-9` → a
/// single digit in a 16×16 circle; `10-99` → two digits in a pill;
/// `> 99` → a capped `"99+"` pill. A 1.5px stroke in the host surface
/// color makes the disc read as lifted off the glyph.
class _UnreadCountBadge extends StatelessWidget {
  const _UnreadCountBadge({required this.count});

  /// The unread count to render — always `> 0` (the caller only
  /// mounts this widget when `count > 0`).
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final label = count > 99 ? '99+' : '$count';
    final isSingleDigit = count < 10;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.primary,
        shape: isSingleDigit ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isSingleDigit
            ? null
            : const BorderRadius.all(Radius.circular(8)),
        border: Border.all(color: c.surface, width: 1.5),
      ),
      child: Container(
        constraints: BoxConstraints(
          minWidth: isSingleDigit ? 16 : 20,
          minHeight: 16,
        ),
        padding: isSingleDigit
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AionText.countBadge.copyWith(color: const Color(0xFFFFFFFF)),
        ),
      ),
    );
  }
}
