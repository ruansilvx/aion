// core/widgets/app_button.dart — AppButton primitive widget (core layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/theme/aion_colors.dart';
import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';

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
                return AnimatedScale(
                  scale: isDisabled ? 1.0 : (_isPressed ? 0.98 : 1.0),
                  duration: const Duration(milliseconds: 80),
                  child: Opacity(
                    opacity: isDisabled ? 0.45 : 1.0,
                    child: _buildDecoratedContent(
                      c,
                      hovered,
                      isDisabled,
                      t.isDark,
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

  Widget _buildDecoratedContent(
    AionColors c,
    bool hovered,
    bool isDisabled,
    bool isDark,
  ) {
    final fill = _fillColor(c, hovered, isDisabled);
    final textColor = _textColor(c);
    final border = _border(c);
    final shadow = isDisabled ? const <BoxShadow>[] : _shadow(c, isDark);

    final content = widget.isFullWidth
        ? Padding(
            padding: const EdgeInsets.all(15),
            child: Center(child: _label(textColor, fontSize: 15)),
          )
        : Padding(
            padding: _padding(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  PhosphorIcon(widget.icon!, size: 18, color: textColor),
                  const SizedBox(width: AionSpacing.sp8),
                ],
                _label(textColor),
              ],
            ),
          );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.all(
          widget.isFullWidth ? const Radius.circular(13) : AionRadius.md,
        ),
        border: border,
        boxShadow: shadow,
      ),
      child: content,
    );

    return widget.isFullWidth
        ? SizedBox(width: double.infinity, child: decorated)
        : decorated;
  }

  Widget _label(Color color, {double? fontSize}) {
    final style = AionText.button.copyWith(color: color, fontSize: fontSize);
    return Text(widget.label, style: style);
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
