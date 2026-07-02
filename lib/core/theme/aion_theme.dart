import 'package:meta/meta.dart';

import 'package:aion/core/theme/aion_colors.dart';

@immutable
class AionThemeData {
  final AionColors colors;
  final bool isDark;

  const AionThemeData({required this.colors, required this.isDark});

  double get fillAlpha => isDark ? fillAlphaObsidian : fillAlphaArctic;
}

const aionThemeArctic = AionThemeData(colors: arctic, isDark: false);
const aionThemeObsidian = AionThemeData(colors: obsidian, isDark: true);
