// core/theme/aion_shadows.dart — Shadow/elevation token definitions (core/theme layer).

import 'package:flutter/painting.dart';

import 'package:aion/core/theme/aion_colors.dart';

/// Aion's elevation scale, expressed as [BoxShadow] lists derived from the
/// active [AionColors] (shadow colors are theme-dependent, so these are
/// methods rather than constants).
abstract final class AionShadows {
  /// Subtle floating-card shadow for [arctic]. Returns an empty list for
  /// [obsidian], which uses border separation instead of shadow.
  static List<BoxShadow> card(AionColors c, bool isDark) {
    if (isDark) return const [];
    return [
      BoxShadow(
        color: c.textPrimary.withOpacity(0.07),
        blurRadius: 2,
        spreadRadius: 0,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// FAB / send-button glow shadow.
  static List<BoxShadow> fab(AionColors c, bool isDark) {
    return [
      BoxShadow(
        color: c.primary.withOpacity(isDark ? 0.60 : 0.45),
        blurRadius: 28,
        spreadRadius: -8,
        offset: const Offset(0, 14),
      ),
    ];
  }

  /// Focus ring for text fields and dropdowns — a solid 3px spread with no
  /// blur, not a soft glow.
  static List<BoxShadow> focus(AionColors c, bool isDark) {
    return [
      BoxShadow(
        color: c.primary.withOpacity(isDark ? 0.30 : 0.16),
        blurRadius: 0,
        spreadRadius: 3,
      ),
    ];
  }

  /// Glow behind the AI-comment avatar mark.
  static List<BoxShadow> aiGlow(AionColors c, bool isDark) {
    return [
      BoxShadow(
        color: c.primary.withOpacity(isDark ? 0.60 : 0.45),
        blurRadius: 14,
      ),
    ];
  }
}
