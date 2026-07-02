// core/theme/aion_radius.dart — Radius and spacing token definitions (core/theme layer).

import 'dart:ui';

/// Aion's corner-radius scale. Every `BorderRadius` in the app is built from
/// one of these — no raw `Radius.circular(n)` in widget code.
abstract final class AionRadius {
  /// Chips, badges, small buttons.
  static const sm = Radius.circular(6);

  /// Buttons, inputs.
  static const md = Radius.circular(10);

  /// Cards, search bar, comment bubble.
  static const lg = Radius.circular(12);

  /// FAB.
  static const xl = Radius.circular(16);

  /// Comment composer input, pill-shaped elements.
  static const pill = Radius.circular(22);

  /// Header icon buttons (e.g. the back button).
  static const iconBtn = Radius.circular(11);
}

/// Aion's spacing scale — a base-4px system. Every gap/padding value in the
/// app is one of these constants, never a raw number.
abstract final class AionSpacing {
  /// 4px.
  static const double sp4 = 4.0;

  /// 8px.
  static const double sp8 = 8.0;

  /// 12px.
  static const double sp12 = 12.0;

  /// 16px.
  static const double sp16 = 16.0;

  /// 20px.
  static const double sp20 = 20.0;

  /// 24px.
  static const double sp24 = 24.0;

  /// 32px.
  static const double sp32 = 32.0;
}
