// design_system/atoms/app_filter_chip.dart — AppFilterChip primitive (design-system layer).

import 'package:flutter/widgets.dart';

import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// A small removable pill representing one active filter value: a label
/// plus a trailing "×" tap target. General-purpose (not ticket-specific),
/// same placement rationale as [AppCheckbox] — lives in
/// `design_system/atoms/` alongside it. A chip only ever represents an
/// *active* filter, so it has a single resting appearance — it borrows
/// [AppDropdown]'s `isActive` color language (`primarySubtle` fill,
/// `primary` border + text) for continuity with the trigger it
/// summarizes. Only the "×" is interactive/focusable; [label] itself is
/// plain text.
class AppFilterChip extends StatefulWidget {
  /// Creates an [AppFilterChip] showing [label], calling [onRemove] when
  /// its "×" is activated. [removeSemanticsLabel] is the accessibility
  /// announcement for the "×" target (e.g. `"Remove In Progress filter"`).
  const AppFilterChip({
    super.key,
    required this.label,
    required this.onRemove,
    required this.removeSemanticsLabel,
  });

  /// The filter value's display text, shown in natural case (never
  /// uppercased).
  final String label;

  /// Called when the "×" is tapped, or activated via `Enter`/`Space`
  /// while it holds keyboard focus.
  final VoidCallback onRemove;

  /// Accessibility label for the "×" target's `Semantics(button: true)`.
  final String removeSemanticsLabel;

  @override
  State<AppFilterChip> createState() => _AppFilterChipState();
}

class _AppFilterChipState extends State<AppFilterChip> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed != value) setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final alpha = t.isDark ? fillAlphaObsidian : fillAlphaArctic;

    final Color glyphColor;
    Color? wash;
    if (_isPressed) {
      glyphColor = c.primaryHover;
      wash = c.primary.withValues(alpha: alpha * 1.6);
    } else if (_isHovered) {
      glyphColor = c.primaryHover;
      wash = c.primary.withValues(alpha: alpha);
    } else if (_isFocused) {
      glyphColor = c.primary;
      wash = c.primary.withValues(alpha: alpha);
    } else {
      glyphColor = c.primary;
      wash = null;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.primarySubtle,
        border: Border.all(color: c.primary, width: 1),
        borderRadius: BorderRadius.all(AionRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 4, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              label: widget.label,
              child: Text(
                widget.label,
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ).copyWith(color: c.primary),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: widget.removeSemanticsLabel,
              child: FocusableActionDetector(
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      widget.onRemove();
                      return null;
                    },
                  ),
                },
                onShowFocusHighlight: (value) =>
                    setState(() => _isFocused = value),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _isHovered = true),
                  onExit: (_) => setState(() => _isHovered = false),
                  child: GestureDetector(
                    onTap: widget.onRemove,
                    onTapDown: (_) => _setPressed(true),
                    onTapUp: (_) => _setPressed(false),
                    onTapCancel: () => _setPressed(false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: wash,
                        borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
                      ),
                      child: CustomPaint(
                        size: const Size(12, 12),
                        painter: _XPainter(color: glyphColor),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a thin "×" glyph, 1.5px stroke, round caps — the [AppFilterChip]
/// remove-target icon, matching [color].
class _XPainter extends CustomPainter {
  const _XPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(0, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _XPainter oldDelegate) =>
      oldDelegate.color != color;
}
