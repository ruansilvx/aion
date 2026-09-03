// design_system/molecules/interactive_link_span.dart — InteractiveLinkSpan hoverable/focusable inline link (design-system layer).

import 'package:flutter/widgets.dart';

/// A single-line, [WidgetSpan]-embeddable inline link with the full
/// hover/focused/pressed interaction states a plain [TextSpan] +
/// `TapGestureRecognizer` can't express on its own (a [TextSpan] carries a tap
/// recognizer but has no hover/focus concept at all). Implements `AIO-1998`
/// §2.4.1's Epic-link state table — mirrors `OverlayMenuItem`'s `MouseRegion`
/// → `FocusableActionDetector` → `GestureDetector` nesting and its
/// `onShowFocusHighlight`-based real keyboard-vs-pointer focus split
/// (`design_system/molecules/overlay_menu_item.dart`), adapted for an inline
/// span instead of a block row. Added as the shared precedent for
/// `PageDetailScreen`'s `_SpecOriginBadge` Epic link and `MarkdownView`'s
/// resolved-wikilink span — both previously used their own inert,
/// static-underline `TextSpan`, each citing the other as "precedent" for
/// skipping interactivity; this widget is the real one. Added for `AIO-1998`'s
/// `/verify` fix-up.
///
/// One deliberate deviation from design.md §2.4.1's literal table: the
/// underline renders in every state, including `Default`/`Focused`
/// (where the table says "none"), matching this codebase's pre-existing
/// link convention — every other inline link here (`MarkdownView`'s `a`
/// tag, its own prior wikilink span) is underlined at rest, since an
/// underline that only appears on hover gives non-mouse users no visual
/// affordance that the text is a link at all. Every other cell (hover's
/// custom-offset underline + color + cursor + tween, the keyboard focus
/// ring, the pressed dimming) matches the table exactly.
class InteractiveLinkSpan extends StatefulWidget {
  /// Creates an [InteractiveLinkSpan] rendering [text] in [style] (its
  /// `color` is ignored — [color]/[hoverColor] override it per
  /// interaction state), calling [onTap] on activation (pointer tap, or
  /// `Enter`/`Space` while focused). [semanticsLabel] is announced as a
  /// link.
  const InteractiveLinkSpan({
    super.key,
    required this.text,
    required this.style,
    required this.color,
    required this.hoverColor,
    required this.onTap,
    required this.semanticsLabel,
  });

  /// The link's visible text.
  final String text;

  /// Base text style (size/weight/family/height) — `color`/`decoration`
  /// are overridden per interaction state below.
  final TextStyle style;

  /// Default/keyboard-focused-idle color and underline tint.
  final Color color;

  /// Hovered/pressed/focused-while-hovered color and underline tint.
  final Color hoverColor;

  /// Called when the link is activated.
  final VoidCallback onTap;

  /// Announced via `Semantics(link: true, label: semanticsLabel)`.
  final String semanticsLabel;

  @override
  State<InteractiveLinkSpan> createState() => _InteractiveLinkSpanState();
}

class _InteractiveLinkSpanState extends State<InteractiveLinkSpan> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed != value) setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final useHoverColor = _isHovered || _isPressed;
    final baseColor = useHoverColor ? widget.hoverColor : widget.color;
    final textColor = _isPressed
        ? baseColor.withValues(alpha: 0.80)
        : baseColor;
    // Only a pointer hover gets the custom-offset underline + color
    // tween (design.md §2.4.1's "Hover (pointer)" row); keyboard-only
    // focus keeps the plain always-on `TextDecoration.underline` — see
    // this class's own dartdoc for why the underline itself never fully
    // disappears.
    final useCustomHoverUnderline = _isHovered;

    return Semantics(
      link: true,
      label: widget.semanticsLabel,
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
          onShowFocusHighlight: (value) =>
              setState(() => _isFocused = value),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Focused-keyboard ring, per design.md §2.4.1: drawn
                // outside this widget's own layout bounds (negative
                // insets inside a `Clip.none` Stack) so it never shifts
                // surrounding text.
                if (_isFocused)
                  Positioned.fill(
                    left: -3,
                    right: -3,
                    top: -1,
                    bottom: -1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: widget.color, width: 1.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                CustomPaint(
                  painter: useCustomHoverUnderline
                      ? _HoverUnderlinePainter(color: textColor)
                      : null,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 100),
                    style: widget.style.copyWith(
                      color: textColor,
                      decoration: useCustomHoverUnderline
                          ? null
                          : TextDecoration.underline,
                      decorationColor: widget.color.withValues(alpha: 0.4),
                      decorationThickness: 1,
                    ),
                    child: Text(widget.text),
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

/// Draws the hover-state underline `2px` below the text baseline at
/// `1px` thickness — design.md §2.4.1's hover row specifies this exact
/// offset, which a plain [TextStyle] underline (used for every other
/// state) can't express since it has no offset parameter of its own.
class _HoverUnderlinePainter extends CustomPainter {
  const _HoverUnderlinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_HoverUnderlinePainter oldDelegate) =>
      oldDelegate.color != color;
}
