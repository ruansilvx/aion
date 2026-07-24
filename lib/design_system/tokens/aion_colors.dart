// design_system/tokens/aion_colors.dart — Color token definitions (design-system layer).

import 'dart:ui';

import 'package:meta/meta.dart';

/// The four-level priority color scale (background + foreground pairs).
/// Deliberately distinct from [AionColors.primary]/[AionColors.secondary]
/// so priority never gets confused with an action color.
@immutable
class AionPriorityColors {
  /// Background for a critical-priority badge.
  final Color criticalBg;

  /// Text/foreground for a critical-priority badge.
  final Color criticalFg;

  /// Background for a high-priority badge.
  final Color highBg;

  /// Text/foreground for a high-priority badge.
  final Color highFg;

  /// Background for a medium-priority badge.
  final Color mediumBg;

  /// Text/foreground for a medium-priority badge.
  final Color mediumFg;

  /// Background for a low-priority badge.
  final Color lowBg;

  /// Text/foreground for a low-priority badge.
  final Color lowFg;

  /// Creates an [AionPriorityColors] palette. All eight colors are required.
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

/// A complete Aion color palette for one theme variant (Arctic or Obsidian).
///
/// This is the sole source of color in Aion — there is no `ThemeData`,
/// `ColorScheme`, or Material color token anywhere in the app. Widgets read
/// an [AionColors] instance via `ThemeScope.of(context).colors`. See the
/// design.md token-role table for what each field is used for.
@immutable
class AionColors {
  /// Main app canvas color.
  final Color background;

  /// Cards, panels, inputs, list body.
  final Color surface;

  /// Raised/hovered surface, ID badge fill, icon buttons.
  final Color surfaceHover;

  /// Buttons, links, focus rings, active icons, selected state.
  final Color primary;

  /// [primary] on hover/press.
  final Color primaryHover;

  /// Selection tint, AI comment bubble, AI badge background.
  final Color primarySubtle;

  /// Secondary avatars, secondary action text.
  final Color secondary;

  /// Success states, "Done" status.
  final Color success;

  /// Destructive actions, errors, required-field asterisk.
  final Color danger;

  /// Warning states only — kept separate from priority colors.
  final Color warning;

  /// Body and heading text.
  final Color textPrimary;

  /// Supporting text, secondary labels, default icon color.
  final Color textSecondary;

  /// Placeholder, captions, timestamps, "Backlog" status.
  final Color textMuted;

  /// Default hairline (1px) border.
  final Color border;

  /// Emphasized border, outlined-avatar/swatch ring.
  final Color borderStrong;

  /// The four-level priority badge palette for this theme.
  final AionPriorityColors priority;

  /// Base accent color for [TicketType.task] chips.
  final Color typeTask;

  /// Base accent color for [TicketType.story] chips.
  final Color typeStory;

  /// Base accent color for [TicketType.epic] chips.
  final Color typeEpic;

  /// Base accent color for [TicketType.resource] chips.
  final Color typeResource;

  /// Base accent color for [TicketType.page] chips.
  final Color typePage;

  /// Base accent color for [TicketType.signal] chips.
  final Color typeSignal;

  /// Base accent color for [TicketType.release] chips.
  final Color typeRelease;

  /// Base accent color for [TicketType.chat] chips. Added for
  /// `aion-arch/changes/sdd-ticket-execution` — completes the seven-type
  /// palette so `TypeChip`/`LinkedTicketsSection` no longer fall back to
  /// [typeTask] for `chat` tickets.
  final Color typeChat;

  /// Creates an [AionColors] palette. All fields are required.
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
    required this.typeResource,
    required this.typePage,
    required this.typeSignal,
    required this.typeRelease,
    required this.typeChat,
  });
}

/// Priority palette for [arctic] (light theme).
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

/// Priority palette for [obsidian] (dark theme).
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

/// Arctic — the light, celestial theme palette.
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
  typeResource: Color(0xFFC2622E),
  typePage: Color(0xFFB0499E),
  typeSignal: Color(0xFF0E8C9E),
  typeRelease: Color(0xFFD8402C),
  typeChat: Color(0xFF4C6FDE),
);

/// Obsidian — the dark, abyssal theme palette.
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
  typeResource: Color(0xFFE68A4E),
  typePage: Color(0xFFD98CE6),
  typeSignal: Color(0xFF34C6D6),
  typeRelease: Color(0xFFF26A4B),
  typeChat: Color(0xFF7C93FF),
);

/// Opacity applied to tinted chip fills (e.g. `c.typeTask.withOpacity(a)`)
/// when [arctic] is active.
const double fillAlphaArctic = 0.11;

/// Opacity applied to tinted chip fills when [obsidian] is active. Higher
/// than [fillAlphaArctic] because dark surfaces need more fill to read as
/// tinted.
const double fillAlphaObsidian = 0.16;

/// Derived, theme-aware overlay/tint colors computed from existing
/// [AionColors] fields — not stored as separate palette entries since
/// their only variation across themes is opacity, not hue. Added for the
/// multi-project Hub (`features/projects/`); see
/// `aion-arch/changes/multi-project-hub/design.md` §0.
extension AionColorsHubTokens on AionColors {
  /// `EmptyHubState` emblem halo glow.
  Color emblemGlow(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.50 : 0.32);

  /// Compact "no directory" notice background (`NewProjectScreen`).
  Color noticeFill(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.10 : 0.06);

  /// Compact "no directory" notice border (`NewProjectScreen`).
  Color noticeBorder(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.30 : 0.20);

  /// Remove-icon disc fill and destructive menu-row hover fill
  /// (`ProjectCard` overflow menu).
  Color destructiveTint(bool isDark) =>
      danger.withValues(alpha: isDark ? 0.20 : 0.14);

  /// Error-state ring for an invalid `NewProjectScreen` form field.
  Color errorRing(bool isDark) =>
      danger.withValues(alpha: isDark ? 0.24 : 0.14);

  // needsRepair — an EXPECTED, recoverable state, not a crash, so it uses
  // `warning`, not `danger`. `danger` stays reserved for destructive/error.
  /// `TicketNeedsRepairBanner`/`TicketSyncStatusBadge` fill in the
  /// `needsRepair` state.
  Color needsRepairTint(bool isDark) =>
      warning.withValues(alpha: isDark ? 0.20 : 0.14);

  /// `TicketNeedsRepairBanner`/`TicketSyncStatusBadge` border in the
  /// `needsRepair` state.
  Color needsRepairBorderTint(bool isDark) =>
      warning.withValues(alpha: isDark ? 0.42 : 0.34);

  /// `TicketNeedsRepairBanner`'s leading icon-chip fill in the
  /// `needsRepair` state.
  Color needsRepairIconTint(bool isDark) =>
      warning.withValues(alpha: isDark ? 0.24 : 0.18);

  // primary family — pendingReconcile: active but calm.
  /// `TicketSyncStatusBadge` fill in the `pendingReconcile` state.
  Color pendingTint(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.18 : 0.12);

  /// `TicketSyncStatusBadge` spinner track-ring color in the
  /// `pendingReconcile` state.
  Color pendingSpinnerTrack(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.32 : 0.24);

  // success family — brief post-repair confirmation.
  /// `TicketNeedsRepairBanner`'s success-confirmation fill.
  Color repairedTint(bool isDark) =>
      success.withValues(alpha: isDark ? 0.20 : 0.14);

  /// `TicketNeedsRepairBanner`'s success-confirmation border.
  Color repairedBorderTint(bool isDark) =>
      success.withValues(alpha: isDark ? 0.42 : 0.34);

  /// `TicketNeedsRepairBanner`'s success-confirmation icon-chip fill.
  Color repairedIconTint(bool isDark) =>
      success.withValues(alpha: isDark ? 0.24 : 0.18);

  // success family — ProviderConnectionBadge, connected state. Added for
  // provider-configuration; see aion-arch/changes/provider-configuration/design.md.
  /// `ProviderConnectionBadge` fill in the `connected` state.
  Color connectedTint(bool isDark) =>
      success.withValues(alpha: isDark ? 0.20 : 0.14);

  /// `ProviderConnectionBadge` border in the `connected` state.
  Color connectedBorderTint(bool isDark) =>
      success.withValues(alpha: isDark ? 0.42 : 0.34);

  // warning family — ProviderConnectionBadge, disconnected state. An
  // EXPECTED, recoverable condition (not yet connected), not a
  // destructive action — `danger` stays reserved for delete/error.
  /// `ProviderConnectionBadge` fill in the `disconnected` state.
  Color disconnectedTint(bool isDark) =>
      warning.withValues(alpha: isDark ? 0.20 : 0.14);

  /// `ProviderConnectionBadge` border in the `disconnected` state.
  Color disconnectedBorderTint(bool isDark) =>
      warning.withValues(alpha: isDark ? 0.42 : 0.34);

  // `ProviderConnectionBadge`'s `checking` state deliberately reuses
  // [pendingTint]/[pendingSpinnerTrack] above rather than adding
  // numerically-identical duplicates — both represent the same "active
  // but calm" primary-family treatment.

  // failure family — _ExecutionActionBanner, verificationFailed state.
  // Added for coding-execution-reliability-and-safety; see that change's
  // design.md §4.
  /// `_ExecutionActionBanner`'s failure-tone fill.
  Color dangerTint(bool isDark) =>
      danger.withValues(alpha: isDark ? 0.16 : 0.11);

  /// `_ExecutionActionBanner`'s failure-tone border.
  Color dangerBorderTint(bool isDark) =>
      danger.withValues(alpha: isDark ? 0.42 : 0.28);
}
