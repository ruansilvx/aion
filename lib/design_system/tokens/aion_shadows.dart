// design_system/tokens/aion_shadows.dart — Shadow/elevation token definitions (design-system layer).

import 'package:flutter/painting.dart';

import 'package:aion/design_system/tokens/aion_colors.dart';

/// Aion's elevation scale, expressed as [BoxShadow] lists derived from the
/// active [AionColors] (shadow colors are theme-dependent, so these are
/// methods rather than constants).
abstract final class AionShadows {
  /// Subtle floating-card shadow for [arctic]. Returns a soft, contracted
  /// glow for [obsidian] — [BoxDecoration.boxShadow] has no inset variant
  /// in this Flutter SDK, so the negative [BoxShadow.spreadRadius] keeps
  /// the glow close to the edge instead of casting a normal drop shadow —
  /// on top of the border separation already used for dark theme.
  static List<BoxShadow> card(AionColors c, bool isDark) {
    if (isDark) {
      return [
        BoxShadow(
          color: c.primary.withValues(alpha: 0.12),
          blurRadius: 8,
          spreadRadius: -4,
        ),
      ];
    }
    return [
      BoxShadow(
        color: c.textPrimary.withValues(alpha: 0.07),
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
        color: c.primary.withValues(alpha: isDark ? 0.60 : 0.45),
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
        color: c.primary.withValues(alpha: isDark ? 0.30 : 0.16),
        blurRadius: 0,
        spreadRadius: 3,
      ),
    ];
  }

  /// Glow behind the AI-comment avatar mark.
  static List<BoxShadow> aiGlow(AionColors c, bool isDark) {
    return [
      BoxShadow(
        color: c.primary.withValues(alpha: isDark ? 0.60 : 0.45),
        blurRadius: 14,
      ),
    ];
  }

  /// Elevated overlay-panel shadow (e.g. `TicketParentPicker`'s search +
  /// candidate-list panel) — heavier than [card], since these panels carry
  /// more content than a simple floating menu.
  static List<BoxShadow> overlay(AionColors c, bool isDark) {
    return [
      BoxShadow(
        color: const Color(0xFF000000).withValues(
          alpha: isDark ? 0.55 : 0.16,
        ),
        blurRadius: 28,
        offset: const Offset(0, 12),
      ),
    ];
  }

  /// Confirmation/alert dialog card shadow — a larger, softer float than
  /// [card] since a dialog sits centered above a dimming scrim rather than
  /// inline in the page layout.
  static List<BoxShadow> dialog(AionColors c, bool isDark) {
    return [
      BoxShadow(
        color: const Color(0xFF000000).withValues(alpha: isDark ? 0.60 : 0.18),
        blurRadius: 40,
        spreadRadius: -6,
        offset: const Offset(0, 20),
      ),
    ];
  }
}
