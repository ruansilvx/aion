// design_system/atoms/app_button.dart — AppButton primitive widget (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// Visual style of an [AppButton].
enum AppButtonVariant {
  /// Filled with [AionColors.primary]; white text. The default.
  primary,

  /// Filled with [AionColors.surfaceHover] and a border; used for secondary
  /// actions.
  secondary,

  /// Transparent fill, [AionColors.primary] text; lowest-emphasis action.
  ghost,

  /// Filled with [AionColors.danger]; white text. For destructive actions.
  destructive,
}

/// Aion's button primitive — replaces `ElevatedButton`/`TextButton` with a
/// `GestureDetector` + `DecoratedBox` built entirely from [AionColors]/
/// [AionText]/[AionRadius] tokens. No Material widget involvement.
class AppButton extends StatefulWidget {
  /// Creates an [AppButton].
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isFullWidth = false,
  });

  /// The button's text label.
  final String label;

  /// Called when the button is activated. `null` renders the button disabled
  /// (reduced opacity, no press/hover feedback).
  final VoidCallback? onPressed;

  /// Which visual style to render. Defaults to [AppButtonVariant.primary].
  final AppButtonVariant variant;

  /// Optional leading icon, rendered before [label].
  final PhosphorIconData? icon;

  /// Whether to render the full-width submit variant (used for primary form
  /// actions like "Create ticket").
  final bool isFullWidth;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  final ValueNotifier<bool> _isHovered = ValueNotifier(false);
  bool _isPressed = false;

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDisabled = widget.onPressed == null;

    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: !isDisabled,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: isDisabled ? MouseCursor.defer : SystemMouseCursors.click,
          onEnter: (_) => _isHovered.value = true,
          onExit: (_) => _isHovered.value = false,
          child: GestureDetector(
            onTap: widget.onPressed,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: ValueListenableBuilder<bool>(
              valueListenable: _isHovered,
              builder: (context, hovered, _) {
                final fill = _fillColor(c, hovered, isDisabled);
                final textColor = _textColor(c);
                final border = _border(c);
                final shadow = isDisabled
                    ? const <BoxShadow>[]
                    : _shadow(c, t.isDark);

                return AnimatedScale(
                  scale: isDisabled ? 1.0 : (_isPressed ? 0.98 : 1.0),
                  duration: const Duration(milliseconds: 80),
                  child: Opacity(
                    opacity: isDisabled ? 0.45 : 1.0,
                    child: _DecoratedContent(
                      isFullWidth: widget.isFullWidth,
                      icon: widget.icon,
                      label: widget.label,
                      padding: _padding(),
                      fill: fill,
                      textColor: textColor,
                      border: border,
                      shadow: shadow,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  EdgeInsets _padding() {
    switch (widget.variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.destructive:
        return const EdgeInsets.symmetric(vertical: 10, horizontal: 17);
      case AppButtonVariant.secondary:
        return const EdgeInsets.symmetric(vertical: 9, horizontal: 16);
      case AppButtonVariant.ghost:
        return const EdgeInsets.symmetric(vertical: 10, horizontal: 8);
    }
  }

  Color _fillColor(AionColors c, bool hovered, bool isDisabled) {
    switch (widget.variant) {
      case AppButtonVariant.primary:
        return hovered && !isDisabled ? c.primaryHover : c.primary;
      case AppButtonVariant.secondary:
        return hovered && !isDisabled ? c.border : c.surfaceHover;
      case AppButtonVariant.ghost:
        return const Color(0x00000000);
      case AppButtonVariant.destructive:
        return c.danger;
    }
  }

  Color _textColor(AionColors c) {
    switch (widget.variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.destructive:
        return const Color(
          0xFFFFFFFF,
        ); // white text on colored fill — no token for white
      case AppButtonVariant.secondary:
        return c.textPrimary;
      case AppButtonVariant.ghost:
        return c.primary;
    }
  }

  BoxBorder? _border(AionColors c) {
    if (widget.variant == AppButtonVariant.secondary) {
      return Border.all(color: c.borderStrong, width: 1);
    }
    return null;
  }

  List<BoxShadow> _shadow(AionColors c, bool isDark) {
    if (widget.variant == AppButtonVariant.primary) {
      return [
        BoxShadow(
          color: c.primary.withValues(alpha: isDark ? 0.60 : 0.45),
          blurRadius: 18,
          spreadRadius: -9,
        ),
      ];
    }
    return const [];
  }
}

/// Renders [AppButton]'s decorated fill/border/shadow box around its
/// icon+label content, given already-resolved style values.
class _DecoratedContent extends StatelessWidget {
  const _DecoratedContent({
    required this.isFullWidth,
    required this.icon,
    required this.label,
    required this.padding,
    required this.fill,
    required this.textColor,
    required this.border,
    required this.shadow,
  });

  final bool isFullWidth;
  final PhosphorIconData? icon;
  final String label;
  final EdgeInsets padding;
  final Color fill;
  final Color textColor;
  final BoxBorder? border;
  final List<BoxShadow> shadow;

  @override
  Widget build(BuildContext context) {
    final content = isFullWidth
        ? Padding(
            padding: const EdgeInsets.all(15),
            child: Center(child: _Label(label: label, color: textColor, fontSize: 15)),
          )
        : Padding(
            padding: padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  PhosphorIcon(icon!, size: 18, color: textColor),
                  const SizedBox(width: AionSpacing.sp8),
                ],
                _Label(label: label, color: textColor),
              ],
            ),
          );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.all(
          isFullWidth ? const Radius.circular(13) : AionRadius.md,
        ),
        border: border,
        boxShadow: shadow,
      ),
      child: content,
    );

    return isFullWidth
        ? SizedBox(width: double.infinity, child: decorated)
        : decorated;
  }
}

/// Renders [AppButton]'s text label in [AionText.button] style.
class _Label extends StatelessWidget {
  const _Label({required this.label, required this.color, this.fontSize});

  final String label;
  final Color color;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final style = AionText.button.copyWith(color: color, fontSize: fontSize);
    return Text(label, style: style);
  }
}
