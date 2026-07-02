import 'dart:ui';

import 'package:meta/meta.dart';

@immutable
class AionPriorityColors {
  final Color criticalBg;
  final Color criticalFg;
  final Color highBg;
  final Color highFg;
  final Color mediumBg;
  final Color mediumFg;
  final Color lowBg;
  final Color lowFg;

  const AionPriorityColors({
    required this.criticalBg,
    required this.criticalFg,
    required this.highBg,
    required this.highFg,
    required this.mediumBg,
    required this.mediumFg,
    required this.lowBg,
    required this.lowFg,
  });
}

@immutable
class AionColors {
  final Color background;
  final Color surface;
  final Color surfaceHover;
  final Color primary;
  final Color primaryHover;
  final Color primarySubtle;
  final Color secondary;
  final Color success;
  final Color danger;
  final Color warning;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color borderStrong;
  final AionPriorityColors priority;
  final Color typeTask;
  final Color typeStory;
  final Color typeEpic;

  const AionColors({
    required this.background,
    required this.surface,
    required this.surfaceHover,
    required this.primary,
    required this.primaryHover,
    required this.primarySubtle,
    required this.secondary,
    required this.success,
    required this.danger,
    required this.warning,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderStrong,
    required this.priority,
    required this.typeTask,
    required this.typeStory,
    required this.typeEpic,
  });
}

const AionPriorityColors arcticPriority = AionPriorityColors(
  criticalBg: Color(0xFFFBE0E5),
  criticalFg: Color(0xFFB22A41),
  highBg: Color(0xFFF6EACF),
  highFg: Color(0xFF8A6712),
  mediumBg: Color(0xFFDCEFF3),
  mediumFg: Color(0xFF1E7F92),
  lowBg: Color(0xFFE9EDF2),
  lowFg: Color(0xFF6C7A8B),
);

const AionPriorityColors obsidianPriority = AionPriorityColors(
  criticalBg: Color(0xFF351A22),
  criticalFg: Color(0xFFFF6B80),
  highBg: Color(0xFF2E2916),
  highFg: Color(0xFFE2BC5A),
  mediumBg: Color(0xFF12303A),
  mediumFg: Color(0xFF4FC3D6),
  lowBg: Color(0xFF1E2534),
  lowFg: Color(0xFF94A1BD),
);

const AionColors arctic = AionColors(
  background: Color(0xFFEDF2F8),
  surface: Color(0xFFFBFCFE),
  surfaceHover: Color(0xFFE4EDF6),
  primary: Color(0xFF2E86D4),
  primaryHover: Color(0xFF1E6DB6),
  primarySubtle: Color(0xFFDBE9F7),
  secondary: Color(0xFF5E7183),
  success: Color(0xFF1E9E76),
  danger: Color(0xFFCE3D54),
  warning: Color(0xFFB8912B),
  textPrimary: Color(0xFF142230),
  textSecondary: Color(0xFF46586A),
  textMuted: Color(0xFF8496A6),
  border: Color(0xFFD6E0EA),
  borderStrong: Color(0xFFBAC8D6),
  priority: arcticPriority,
  typeTask: Color(0xFF2E86D4),
  typeStory: Color(0xFF1E9E76),
  typeEpic: Color(0xFF6A5AD0),
);

const AionColors obsidian = AionColors(
  background: Color(0xFF0A0E18),
  surface: Color(0xFF131A29),
  surfaceHover: Color(0xFF1C2436),
  primary: Color(0xFF9366FF),
  primaryHover: Color(0xFFA886FF),
  primarySubtle: Color(0xFF241F3E),
  secondary: Color(0xFF57608A),
  success: Color(0xFF33D19B),
  danger: Color(0xFFF1546C),
  warning: Color(0xFFD7B24E),
  textPrimary: Color(0xFFE7EDF7),
  textSecondary: Color(0xFFA2AEC6),
  textMuted: Color(0xFF6B7690),
  border: Color(0xFF232C40),
  borderStrong: Color(0xFF35415C),
  priority: obsidianPriority,
  typeTask: Color(0xFF9366FF),
  typeStory: Color(0xFF33D19B),
  typeEpic: Color(0xFF5C7CF5),
);

const double fillAlphaArctic = 0.11;
const double fillAlphaObsidian = 0.16;
