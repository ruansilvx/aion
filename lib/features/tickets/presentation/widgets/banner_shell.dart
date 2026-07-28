// presentation/widgets/banner_shell.dart — Shared banner shell primitives (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/design_system/design_system.dart';

/// Shared outer shell every inline ticket-list banner (`CodebaseAnalysisBanner`,
/// `BaselineUpgradeBanner`) renders inside — fill/border color, radius,
/// padding, and an optional dismiss × (omitted for a banner state that
/// uses its own trailing control instead, e.g. `CodebaseAnalysisBanner`'s
/// running state). Hoisted out of `codebase_analysis_banner.dart` so both
/// banners share one implementation rather than duplicating it.
class BannerShell extends StatelessWidget {
  /// Creates a [BannerShell] filled with [fill], bordered with [border],
  /// wrapping [child]. When [onDismiss] is non-null, a [BannerDismissButton]
  /// is overlaid top-right.
  const BannerShell({
    super.key,
    required this.fill,
    required this.border,
    required this.child,
    this.onDismiss,
    this.dismissSemanticLabel,
  });

  /// The banner's background fill color.
  final Color fill;

  /// The banner's border color.
  final Color border;

  /// The banner's content.
  final Widget child;

  /// Called when the dismiss × is tapped. `null` omits the dismiss ×.
  final VoidCallback? onDismiss;

  /// Screen-reader label for the dismiss ×. Required whenever [onDismiss]
  /// is set.
  final String? dismissSemanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 26),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: const BorderRadius.all(AionRadius.lg),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: child,
          ),
          if (onDismiss != null)
            Positioned(
              top: 8,
              right: 8,
              child: BannerDismissButton(
                onTap: onDismiss!,
                semanticLabel: dismissSemanticLabel!,
              ),
            ),
        ],
      ),
    );
  }
}

/// The × control [BannerShell] overlays top-right when [BannerShell.onDismiss]
/// is set.
class BannerDismissButton extends StatefulWidget {
  /// Creates a [BannerDismissButton] calling [onTap] when activated,
  /// announced to screen readers as [semanticLabel].
  const BannerDismissButton({
    super.key,
    required this.onTap,
    required this.semanticLabel,
  });

  /// Called when the dismiss control is tapped.
  final VoidCallback onTap;

  /// Screen-reader label for this control.
  final String semanticLabel;

  @override
  State<BannerDismissButton> createState() => _BannerDismissButtonState();
}

class _BannerDismissButtonState extends State<BannerDismissButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _isHovered ? c.surfaceHover : const Color(0x00000000),
              borderRadius: const BorderRadius.all(AionRadius.sm),
            ),
            child: SizedBox(
              width: 26,
              height: 26,
              child: Center(
                child: PhosphorIcon(
                  PhosphorIcons.xLight,
                  size: 15,
                  color: _isHovered ? c.textSecondary : c.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A leading icon-chip, shared shape across every ticket-list banner state
/// — only the fill/icon color and glyph vary.
class BannerIconChip extends StatelessWidget {
  /// Creates a [BannerIconChip] filled with [fill] showing [icon] tinted
  /// [iconColor].
  const BannerIconChip({
    super.key,
    required this.fill,
    required this.icon,
    required this.iconColor,
    this.iconSize = 19,
  });

  /// The chip's background fill color.
  final Color fill;

  /// The glyph to render.
  final PhosphorIconData icon;

  /// The glyph's color.
  final Color iconColor;

  /// The glyph's size in logical pixels. Defaults to `19`.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: const BorderRadius.all(AionRadius.sm),
      ),
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: PhosphorIcon(icon, size: iconSize, color: iconColor),
        ),
      ),
    );
  }
}
