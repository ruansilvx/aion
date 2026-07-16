// design_system/atoms/app_checkbox.dart — AppCheckbox primitive (design-system layer).

import 'package:flutter/widgets.dart';

import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// A small, square, non-Material checkbox primitive: filled with a white
/// check mark when [value] is `true`, outlined and empty when `false`.
/// Used by `TicketListTile`/`TicketBoardCard` in selection mode. General-
/// purpose (not ticket-specific) — lives in `design_system/atoms/` alongside
/// `AppButton`. Renders default/hover/keyboard-focused/
/// disabled states per the design spec's `AppCheckbox` interaction table.
class AppCheckbox extends StatefulWidget {
  /// Creates an [AppCheckbox] reflecting [value]; calls [onChanged] with
  /// the toggled value on tap or keyboard activation.
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  /// Whether the checkbox is currently checked.
  final bool value;

  /// Called with the toggled value when the checkbox is tapped, activated
  /// via keyboard, or when `null` is not applicable (never called when
  /// [enabled] is `false`).
  final ValueChanged<bool> onChanged;

  /// Whether the checkbox responds to input. When `false`, renders at
  /// reduced opacity and ignores taps/keyboard activation.
  final bool enabled;

  @override
  State<AppCheckbox> createState() => _AppCheckboxState();
}

class _AppCheckboxState extends State<AppCheckbox> {
  bool _isHovered = false;
  bool _isFocused = false;

  void _handleTap() {
    if (!widget.enabled) return;
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final Color fill;
    final Color border;
    if (widget.value) {
      fill = _isHovered ? c.primaryHover : c.primary;
      border = _isHovered ? c.primaryHover : c.primary;
    } else {
      fill = c.surface;
      border = _isHovered ? c.primary : c.borderStrong;
    }

    final boxShadow = _isFocused
        ? [
            BoxShadow(
              color: c.primary.withValues(alpha: t.isDark ? 0.30 : 0.16),
              spreadRadius: 3,
            ),
          ]
        : const <BoxShadow>[];

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(
          color: widget.enabled ? border : c.border,
          width: 1.5,
        ),
        borderRadius: BorderRadius.all(AionRadius.sm),
        boxShadow: boxShadow,
      ),
      child: widget.value
          ? const CustomPaint(size: Size(20, 20), painter: _CheckmarkPainter())
          : null,
    );

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.45,
      child: Semantics(
        button: true,
        checked: widget.value,
        enabled: widget.enabled,
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: FocusableActionDetector(
            enabled: widget.enabled,
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _handleTap();
                  return null;
                },
              ),
            },
            onShowFocusHighlight: (value) =>
                setState(() => _isFocused = value),
            child: GestureDetector(
              onTap: _handleTap,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(child: box),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the check-mark glyph shown inside a checked [AppCheckbox]: a
/// two-segment polyline, `1.6px` stroke, round caps, white.
class _CheckmarkPainter extends CustomPainter {
  const _CheckmarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF) // white check mark on primary fill
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.26, size.height * 0.55)
      ..lineTo(size.width * 0.42, size.height * 0.72)
      ..lineTo(size.width * 0.76, size.height * 0.32);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter oldDelegate) => false;
}
