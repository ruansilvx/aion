import 'package:flutter/painting.dart';

import 'package:aion/core/theme/aion_colors.dart';

abstract final class AionShadows {
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

  static List<BoxShadow> focus(AionColors c, bool isDark) {
    return [
      BoxShadow(
        color: c.primary.withOpacity(isDark ? 0.30 : 0.16),
        blurRadius: 0,
        spreadRadius: 3,
      ),
    ];
  }

  static List<BoxShadow> aiGlow(AionColors c, bool isDark) {
    return [
      BoxShadow(
        color: c.primary.withOpacity(isDark ? 0.60 : 0.45),
        blurRadius: 14,
      ),
    ];
  }
}
