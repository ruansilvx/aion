// design_system/molecules/overlay_menu_item.dart — Shared keyboard-focusable row wrapper for overlay menu lists (design-system layer).

import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyUpEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// A single interactive row inside an open overlay menu (`TicketOverflowMenu`,
/// `SelectionMenu<T>`, `MoveToStatusMenu`) — adds Tab-focusability,
/// `Enter`/`Space` activation, and a hover/focus/pressed fill to whatever
/// already-built, already-padded row content a caller passes as [child].
///
/// This is a pure interaction/accessibility wrapper: it owns **only**
/// [child]'s background fill and its own [FocusableActionDetector]/
/// [MouseRegion]/[GestureDetector] nesting — no padding, size, layout, or
/// content of its own. Hover and keyboard focus intentionally render as
/// the *same* fill (no separate focus ring): inside a small single-column
/// list of rows, "this row is highlighted" is the only information that
/// matters, not which input method produced the highlight.
///
/// Mirrors `TicketOverflowMenu`'s own trigger button's `MouseRegion` →
/// `FocusableActionDetector` → `GestureDetector` nesting and three-state
/// fill formula (`ticket_overflow_menu.dart`), generalized to arbitrary
/// row content and an [onTap] callback instead of the trigger's own
/// hardcoded overlay toggle. Added for `overlay-menu-keyboard-focus`; see
/// that change's `design.md` §1.
class OverlayMenuItem extends StatefulWidget {
  /// Creates an [OverlayMenuItem] wrapping [child].
  const OverlayMenuItem({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticsLabel,
    this.accent,
    this.restingTinted = false,
    this.autofocus = false,
    this.enabled = true,
  });

  /// The row's own already-built, already-padded content (an icon+label
  /// `Row`, a plain `Text`, etc.) — this widget adds no padding/layout of
  /// its own around it.
  final Widget child;

  /// Called on tap, `Enter`, or `Space`. Not called when [enabled] is
  /// `false`.
  final VoidCallback onTap;

  /// Announced by `Semantics(button: true)`.
  final String semanticsLabel;

  /// The row's accent color for a hover/focus/pressed wash of its own hue
  /// (e.g. `c.danger` for a destructive row, `c.typeEpic`/`c.typeBug` for
  /// a Promote-to-X row) — `null` for a plain, non-accented row (the
  /// standard `surfaceHover`/`border` raised-surface progression).
  final Color? accent;

  /// Whether the row's *resting* (non-hovered, non-focused, non-pressed)
  /// fill is already tinted with [accent] — the "Suggested" Promote row's
  /// existing resting tint. Has no effect when [accent] is `null`. Hover/
  /// focus/pressed always override this with a stronger wash of the same
  /// hue, they never blend a second color on top of it.
  final bool restingTinted;

  /// Whether this row should claim keyboard focus as soon as its menu
  /// opens — set `true` on a menu's first enabled row so keyboard users
  /// land inside the menu immediately, matching every other row's
  /// default of `false`.
  final bool autofocus;

  /// Whether this row can be hovered, focused, or activated. A disabled
  /// row renders its [child] dimmed, takes no focus stop, and shows the
  /// default (non-click) cursor.
  final bool enabled;

  @override
  State<OverlayMenuItem> createState() => _OverlayMenuItemState();
}

class _OverlayMenuItemState extends State<OverlayMenuItem> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed != value) {
      setState(() => _isPressed = value);
    }
  }

  /// Tracks raw `Enter`/`Space` key-down/key-up so a held activation key
  /// drives the same pressed feedback as a held mouse-down — the actual
  /// activation itself still runs through the `ActivateIntent` binding
  /// below, so this always returns [KeyEventResult.ignored].
  ///
  /// This lives on a bubbling ancestor `Focus` (see [build]) rather than
  /// inside the `ActivateIntent` action itself, since a single
  /// `CallbackAction.onInvoke` fires once per activation and can't
  /// express a held-duration press state the way `GestureDetector`'s
  /// `onTapDown`/`onTapUp` do for the mouse. Design.md §1.1's
  /// "Implementation note" documents this against the structure
  /// diagram above it.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isActivationKey =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
    if (!isActivationKey) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _setPressed(true);
    } else if (event is KeyUpEvent) {
      _setPressed(false);
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final accent = widget.accent;
    final hoverAlpha = t.isDark ? fillAlphaObsidian : fillAlphaArctic;

    final Color fill;
    if (_isPressed) {
      fill = accent != null
          ? c.pressedAccentTint(accent, t.isDark)
          : c.border;
    } else if (_isHovered || _isFocused) {
      fill = accent != null
          ? accent.withValues(alpha: hoverAlpha)
          : c.surfaceHover;
    } else if (accent != null && widget.restingTinted) {
      fill = c.accentTint(accent, t.isDark);
    } else {
      fill = const Color(0x00000000);
    }

    final content = widget.enabled
        ? widget.child
        : Opacity(opacity: 0.45, child: widget.child);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      // Doesn't request focus itself — it only observes key events
      // bubbling up from whichever row below actually holds focus (see
      // _handleKeyEvent's dartdoc).
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleKeyEvent,
        // MouseRegion wraps FocusableActionDetector (not the reverse)
        // to match TicketOverflowMenu's own trigger button's real
        // nesting, using a plain onEnter/onExit MouseRegion for
        // _isHovered instead of FocusableActionDetector's own
        // onShowHoverHighlight — that callback's input-modality
        // suppression logic is meant for focus rings, not plain
        // mouse-hover feedback. See design.md §1.1's Implementation
        // note.
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: widget.enabled
              ? (_) => setState(() => _isHovered = true)
              : null,
          onExit: widget.enabled
              ? (_) => setState(() => _isHovered = false)
              : null,
          child: FocusableActionDetector(
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onTap();
                  return null;
                },
              ),
            },
            onShowFocusHighlight: (value) =>
                setState(() => _isFocused = value),
            child: GestureDetector(
              onTap: widget.enabled ? widget.onTap : null,
              onTapDown: widget.enabled
                  ? (_) => _setPressed(true)
                  : null,
              onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
              onTapCancel: widget.enabled ? () => _setPressed(false) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
                decoration: BoxDecoration(color: fill),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
