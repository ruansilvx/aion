// design_system/tokens/aion_theme.dart — AionThemeData plain Dart theme class (design-system layer).

import 'package:meta/meta.dart';

import 'package:aion/design_system/tokens/aion_colors.dart';

/// The active theme: a color palette plus whether it's the dark variant.
/// Deliberately not a `ThemeData` — Aion has no Material theming layer.
/// Accessed via `ThemeScope.of(context)`.
@immutable
class AionThemeData {
  /// The active color palette ([arctic] or [obsidian]).
  final AionColors colors;

  /// Whether this is the dark ([obsidian]) variant.
  final bool isDark;

  /// Creates an [AionThemeData]. Prefer the top-level [aionThemeArctic] and
  /// [aionThemeObsidian] singletons over constructing new instances.
  const AionThemeData({required this.colors, required this.isDark});

  /// The tint opacity to use for chip/badge fills in this theme — see
  /// [fillAlphaArctic] and [fillAlphaObsidian].
  double get fillAlpha => isDark ? fillAlphaObsidian : fillAlphaArctic;
}

/// The Arctic (light) theme singleton.
const aionThemeArctic = AionThemeData(colors: arctic, isDark: false);

/// The Obsidian (dark) theme singleton.
const aionThemeObsidian = AionThemeData(colors: obsidian, isDark: true);
