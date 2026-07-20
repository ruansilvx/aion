// core/routing/workspace_nav_shell.dart — WorkspaceNavShell persistent navigation chrome (core layer).

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// Persistent navigation chrome wrapping every `/workspace/*` route's
/// content: a left sidebar on wide layouts, a bottom tab bar on narrow
/// ones, both offering the same two destinations (Tickets, Documentation)
/// plus a shared secondary-actions trigger (Switch Project, Trash).
///
/// Rendered by `WorkspaceShell` around its routed `child` — see
/// `app_router.dart`. Replaces the ad hoc per-screen header buttons
/// (`_SwitchProjectButton`/`_DocumentationEntryButton`/`_TrashEntryButton`)
/// that `TicketsListScreen` used to own alone, and gives `DocumentationScreen`
/// a way back to Tickets for the first time on every platform.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth <= _kBreakpoint;
        return isCompact
            ? _CompactShell(
                active: destination,
                onSelectTickets: selectTickets,
                onSelectDocumentation: selectDocumentation,
                child: child,
              )
            : _WideShell(
                active: destination,
                onSelectTickets: selectTickets,
                onSelectDocumentation: selectDocumentation,
                child: child,
              );
      },
    );
  }
}

/// Width, in logical pixels, at or below which [WorkspaceNavShell] renders
/// [_CompactShell] (bottom tab bar) instead of [_WideShell] (sidebar).
/// Matches the existing `LayoutBuilder` + `constraints.maxWidth`
/// responsive convention (`MarkdownEditor`'s 640, `TrashScreen`'s 380).
const double _kBreakpoint = 900;

/// The two top-level sections [WorkspaceNavShell] can switch between.
/// Built to make adding a future section (e.g. a Chat section) a matter
/// of extending this enum plus [_destinationFor], not restructuring the
/// shell.
enum _NavDestination {
  /// `/workspace/tickets` and its sub-routes (`/new`, `/trash`, `/:id`).
  tickets,

  /// `/workspace/documentation` and `/workspace/pages/*` — pages are
  /// Documentation's content even though their routes live outside the
  /// `/workspace/documentation` path prefix.
  documentation,
}

/// Resolves [location] to the [_NavDestination] it belongs to.
/// `/workspace/documentation` and `/workspace/pages/*` both resolve to
/// [_NavDestination.documentation]; everything else under
/// `/workspace/tickets*` resolves to [_NavDestination.tickets].
_NavDestination _destinationFor(String location) {
  if (location.startsWith('/workspace/documentation') ||
      location.startsWith('/workspace/pages')) {
    return _NavDestination.documentation;
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
    required this.child,
  });

  /// The currently active destination, used to highlight the matching
  /// nav item.
  final _NavDestination active;

  /// Navigates to `/workspace/tickets`.
  final VoidCallback onSelectTickets;

  /// Navigates to `/workspace/documentation`.
  final VoidCallback onSelectDocumentation;

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
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The fixed-width (244px) left sidebar rendered by [_WideShell]: the two
/// [_NavItem] destinations top-aligned, then flexible space, then the
/// [_SecondaryActionsTrigger] anchored to the bottom.
class _Sidebar extends StatelessWidget {
  /// Creates a [_Sidebar].
  const _Sidebar({
    required this.active,
    required this.onSelectTickets,
    required this.onSelectDocumentation,
  });

  /// The currently active destination.
  final _NavDestination active;

  /// Navigates to `/workspace/tickets`.
  final VoidCallback onSelectTickets;

  /// Navigates to `/workspace/documentation`.
  final VoidCallback onSelectDocumentation;

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
                ],
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: _SecondaryActionsTrigger(),
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
    required this.child,
  });

  /// The currently active destination, used to highlight the matching
  /// nav item.
  final _NavDestination active;

  /// Navigates to `/workspace/tickets`.
  final VoidCallback onSelectTickets;

  /// Navigates to `/workspace/documentation`.
  final VoidCallback onSelectDocumentation;

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
        ),
      ],
    );
  }
}

/// The fixed-height (72px + bottom safe area) bottom tab bar rendered by
/// [_CompactShell]: the two [_NavItem] destinations plus the
/// [_SecondaryActionsTrigger], laid out as three equal cells.
class _BottomTabBar extends StatelessWidget {
  /// Creates a [_BottomTabBar].
  const _BottomTabBar({
    required this.active,
    required this.onSelectTickets,
    required this.onSelectDocumentation,
  });

  /// The currently active destination.
  final _NavDestination active;

  /// Navigates to `/workspace/tickets`.
  final VoidCallback onSelectTickets;

  /// Navigates to `/workspace/documentation`.
  final VoidCallback onSelectDocumentation;

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
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  compact: true,
                  active: active == _NavDestination.tickets,
                  icon: PhosphorIcons.squaresFourLight,
                  label: context.l10n.ticketsListTitle,
                  onTap: onSelectTickets,
                ),
              ),
              Expanded(
                child: _NavItem(
                  compact: true,
                  active: active == _NavDestination.documentation,
                  icon: PhosphorIcons.bookOpenLight,
                  label: context.l10n.documentationTitle,
                  onTap: onSelectDocumentation,
                ),
              ),
              const Expanded(
                child: Center(child: _SecondaryActionsTrigger()),
              ),
            ],
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
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  /// `true` for the bottom-tab-bar (icon-above-label) layout, `false`
  /// for the sidebar (icon-beside-label) layout.
  final bool compact;

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

    final icon = PhosphorIcon(widget.icon, size: widget.compact ? 22 : 20, color: foreground);
    final label = Text(
      widget.label,
      style: widget.compact
          ? AionText.navTabLabel.copyWith(color: foreground)
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
        null => '',
      },
      onSelected: (action) {
        switch (action) {
          case _SecondaryAction.switchProject:
            context.go('/hub');
          case _SecondaryAction.trash:
            context.go('/workspace/tickets/trash');
          case null:
            break;
        }
      },
      semanticsLabel: context.l10n.navShellSecondaryMenuLabel,
    );
  }
}
