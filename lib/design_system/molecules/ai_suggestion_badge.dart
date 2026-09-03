// design_system/molecules/ai_suggestion_badge.dart — AiSuggestionBadge widget (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// A small, non-interactive pill flagging a field value as AI-suggested and
/// not yet confirmed or edited by the user — rendered inline immediately after
/// a field's value (e.g. `TicketMetadataSection`'s Complexity/Estimate rows).
/// Informational and monochrome, deliberately reusing the same neutral "quiet
/// chrome" tint the estimate/timeSpent rollup indicator already uses, rather
/// than `primarySubtle` — see `AIO-75` §0.1 for why `primarySubtle` is
/// rejected here. Has no hover/focus/ press/disabled states of its own. See
/// `AIO-75`'s linked Documentation page, §1, for the full visual spec.
class AiSuggestionBadge extends StatelessWidget {
  /// Creates an [AiSuggestionBadge]. [lowConfidence] selects the
  /// low-confidence (cold-start) variant.
  const AiSuggestionBadge({super.key, required this.lowConfidence});

  /// `true` renders the low-confidence variant (dashed border, dimmed
  /// icon, and the low-confidence label); `false` renders the plain
  /// "AI suggested" variant.
  final bool lowConfidence;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final fill = c.neutralTint(t.isDark);
    final iconColor = lowConfidence
        ? c.textSecondary.withValues(alpha: 0.72)
        : c.textSecondary;

    // `aiSuggestedLowConfidenceBadge` is authored as the low-confidence
    // variant's complete label ("AI suggested · low confidence"), not a
    // fragment to append after `aiSuggestedBadge` — appending both would
    // duplicate "AI suggested". One `Text` swaps its full content by
    // [lowConfidence] instead.
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PhosphorIcon(PhosphorIconsFill.sparkle, size: 12, color: iconColor),
          const SizedBox(width: 5),
          Text(
            lowConfidence
                ? context.l10n.aiSuggestedLowConfidenceBadge
                : context.l10n.aiSuggestedBadge,
            style: AionText.badgeLabel.copyWith(
              color: lowConfidence ? c.textMuted : c.textSecondary,
            ),
          ),
        ],
      ),
    );

    if (!lowConfidence) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: const BorderRadius.all(AionRadius.sm),
        ),
        child: content,
      );
    }

    return CustomPaint(
      painter: _DashedRoundedRectPainter(
        color: c.neutralBorderTint(t.isDark),
        fillColor: fill,
        radius: AionRadius.sm.x,
      ),
      child: content,
    );
  }
}

/// Draws a filled rounded rect with a dashed hairline border — used by
/// [AiSuggestionBadge]'s low-confidence variant, since Flutter's [Border]
/// has no built-in dash style. Deliberately not a Material `OutlinedBorder`
/// — this app never uses Material widgets.
class _DashedRoundedRectPainter extends CustomPainter {
  const _DashedRoundedRectPainter({
    required this.color,
    required this.fillColor,
    required this.radius,
  });

  /// The dashed hairline's color.
  final Color color;

  /// The solid fill drawn behind the dashed hairline.
  final Color fillColor;

  /// Corner radius, matching [AiSuggestionBadge]'s container radius.
  final double radius;

  static const _dashWidth = 3.0;
  static const _dashGap = 2.5;
  static const _strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    canvas.drawRRect(rrect, Paint()..color = fillColor);

    final borderPath = Path()..addRRect(rrect);
    final dashPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    for (final metric in borderPath.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          dashPaint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.radius != radius;
}
