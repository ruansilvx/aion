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

/// The four-level severity color scale (background + foreground pairs) for
/// a `TicketType.bug` ticket. Deliberately a single-temperature "ember
/// ramp" (fire-red → orange → clay → ash-gray, cooling from critical to
/// low) rather than [AionPriorityColors]'s four-hue set, plus a leading
/// triangle marker on `SeverityBadge`, so severity is never visually
/// confused with priority.
@immutable
class AionSeverityColors {
  /// Background for a critical-severity badge.
  final Color criticalBg;

  /// Text/foreground for a critical-severity badge.
  final Color criticalFg;

  /// Background for a high-severity badge.
  final Color highBg;

  /// Text/foreground for a high-severity badge.
  final Color highFg;

  /// Background for a medium-severity badge.
  final Color mediumBg;

  /// Text/foreground for a medium-severity badge.
  final Color mediumFg;

  /// Background for a low-severity badge.
  final Color lowBg;

  /// Text/foreground for a low-severity badge.
  final Color lowFg;

  /// Creates an [AionSeverityColors] palette. All eight colors are required.
  const AionSeverityColors({
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

  /// Base accent color for [TicketType.idea] chips. Renamed from `typeSignal`
  /// for `AIO-934` — same values, since the rename is value-preserving.
  final Color typeIdea;

  /// Base accent color for [TicketType.knownGap] chips. Added for `AIO-934`.
  final Color typeKnownGap;

  /// Base accent color for [TicketType.openQuestion] chips. Added for
  /// `AIO-934`.
  final Color typeOpenQuestion;

  /// Base accent color for [TicketType.release] chips.
  final Color typeRelease;

  /// Base accent color for [TicketType.chat] chips. Added for `AIO-1856` —
  /// completes the seven-type palette so `TypeChip`/`LinkedTicketsSection` no
  /// longer fall back to [typeTask] for `chat` tickets.
  final Color typeChat;

  /// Base accent color for [TicketType.bug] chips. Added for `AIO-425`.
  final Color typeBug;

  /// Base accent color for [TicketType.spec] chips/badges. NOTE: intentionally
  /// hue-shifts between themes — amethyst in [arctic], azure in [obsidian] —
  /// because [typeTask] follows [primary] from blue to violet in the dark
  /// theme, swapping which hue band sits free for a tenth type accent. Do not
  /// "correct" one theme's value to match the other's hue. Added for
  /// `AIO-1998`.
  final Color typeSpec;

  /// The four-level severity badge palette for this theme, for
  /// [TicketType.bug] tickets. Added for `AIO-425`.
  final AionSeverityColors severity;

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
    required this.typeIdea,
    required this.typeKnownGap,
    required this.typeOpenQuestion,
    required this.typeRelease,
    required this.typeChat,
    required this.typeBug,
    required this.typeSpec,
    required this.severity,
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

/// Severity palette for [arctic] (light theme).
const AionSeverityColors arcticSeverity = AionSeverityColors(
  criticalBg: Color(0xFFFAE1DB),
  criticalFg: Color(0xFFC22F1D),
  highBg: Color(0xFFFBE7D5),
  highFg: Color(0xFFC1631A),
  mediumBg: Color(0xFFF6E6D8),
  mediumFg: Color(0xFFA9683A),
  lowBg: Color(0xFFEDEAE5),
  lowFg: Color(0xFF7C7267),
);

/// Severity palette for [obsidian] (dark theme).
const AionSeverityColors obsidianSeverity = AionSeverityColors(
  criticalBg: Color(0xFF3A1D18),
  criticalFg: Color(0xFFFF6E4D),
  highBg: Color(0xFF33251A),
  highFg: Color(0xFFF5924A),
  mediumBg: Color(0xFF2C2419),
  mediumFg: Color(0xFFD69A5E),
  lowBg: Color(0xFF26231F),
  lowFg: Color(0xFF9A8E7E),
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
  typeIdea: Color(0xFF0E8C9E),
  typeKnownGap: Color(0xFF2F9E3F),
  typeOpenQuestion: Color(0xFFC6397D),
  typeRelease: Color(0xFFD8402C),
  typeChat: Color(0xFF4C6FDE),
  typeBug: Color(0xFF5E8C1E),
  typeSpec: Color(0xFF8A3FB0),
  severity: arcticSeverity,
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
  typeIdea: Color(0xFF34C6D6),
  typeKnownGap: Color(0xFF54C85C),
  typeOpenQuestion: Color(0xFFEE72AE),
  typeRelease: Color(0xFFF26A4B),
  typeChat: Color(0xFF7C93FF),
  typeBug: Color(0xFF98D13C),
  typeSpec: Color(0xFF3FA9F5),
  severity: obsidianSeverity,
);

/// Opacity applied to tinted chip fills (e.g. `c.typeTask.withOpacity(a)`)
/// when [arctic] is active.
const double fillAlphaArctic = 0.11;

/// Opacity applied to tinted chip fills when [obsidian] is active. Higher
/// than [fillAlphaArctic] because dark surfaces need more fill to read as
/// tinted.
const double fillAlphaObsidian = 0.16;

/// Derived, theme-aware overlay/tint colors computed from existing
/// [AionColors] fields — not stored as separate palette entries since their
/// only variation across themes is opacity, not hue. Added for the
/// multi-project Hub (`features/projects/`); see `AIO-1174` §0.
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
  // provider-configuration; see AIO-1699's linked Documentation page.
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

  // warning family — legibility-boosted text shade for copy rendered over
  // a warningTint-filled chip (raw `warning` is low-contrast there). Added
  // for dont-spawn-new-chat-ticket-per-execution-trigger; see that
  // change's design.md §5.1.
  /// A `warning`-derived text color legible as body copy over
  /// `needsRepairTint`/`needsRepairBorderTint`-style warning chips —
  /// blended toward white in dark mode, toward black in light mode.
  Color warningText(bool isDark) => isDark
      ? Color.lerp(warning, const Color(0xFFFFFFFF), 0.30)!
      : Color.lerp(warning, const Color(0xFF000000), 0.45)!;

  // danger family — cancellation affordances (`ExecutionCancelControl`'s
  // focus ring and label text). Added for parallel-work; see that
  // change's design.md §7.1.
  /// `ExecutionCancelControl`'s focused-state ring color — a
  /// `danger`-keyed parallel of [focusRing], same alpha values.
  Color cancelFocusRing(bool isDark) =>
      danger.withValues(alpha: isDark ? 0.30 : 0.16);

  /// A `danger`-derived text color legible as body copy over
  /// danger-tinted chrome — blended toward white in dark mode, toward
  /// black in light mode. Derived exactly like [warningText], keyed to
  /// `danger` instead of `warning`.
  Color dangerText(bool isDark) => isDark
      ? Color.lerp(danger, const Color(0xFFFFFFFF), 0.22)!
      : Color.lerp(danger, const Color(0xFF000000), 0.35)!;

  // AI/override-tone family — a `primary`-keyed border distinct from the
  // neutral `noticeBorder` family, for surfaces that read as "this is
  // AI/skill-authored," matching `primarySubtle`'s existing "AI comment
  // bubble" role. Added for `AIO-1654`; see its linked Documentation page
  // (Skill/Convention Overrides spec) §2.5/§3.2.
  /// `OverridesListScreen`'s "Overridden" chip border and
  /// `OverrideEditorScreen`'s status-line variant A ("editing an
  /// override") border.
  Color aiBubbleBorder(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.42 : 0.28);

  // primary family — icon-chip fill behind the gitignore-banner branch
  // glyph. Added for new-project-onboarding; see that change's
  // design.md §1.2.
  /// `GitignoreConfirmationBanner`'s leading icon-chip fill.
  Color noticeIconTint(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.22 : 0.14);

  // primary family — icon-chip fill behind CodebaseAnalysisBanner's
  // running spinner. Added for new-project-onboarding; see
  // design.md §1.2.
  /// `CodebaseAnalysisBanner`'s leading icon-chip fill in the `running`
  /// state.
  Color pendingIconTint(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.20 : 0.12);

  // danger family — icon-chip fill behind CodebaseAnalysisBanner's failure
  // glyph. Added for `AIO-1266`; see its linked Documentation page, §1.2.
  /// `CodebaseAnalysisBanner`'s leading icon-chip fill in the `failed`
  /// state.
  Color dangerIconTint(bool isDark) =>
      danger.withValues(alpha: isDark ? 0.24 : 0.16);

  // idea family — CodebaseAnalysisBanner's identity accent (typeIdea), since a
  // scan's output is `idea` tickets. Renamed from the `signal*`/`typeSignal`
  // family (value-preserving) for `AIO-934`. Originally added for `AIO-1266`;
  // see its linked Documentation page, §1.2.
  /// `CodebaseAnalysisBanner`'s `offer`-state fill.
  Color ideaFill(bool isDark) =>
      typeIdea.withValues(alpha: isDark ? 0.13 : 0.08);

  /// `CodebaseAnalysisBanner`'s `offer`-state border.
  Color ideaBorderTint(bool isDark) =>
      typeIdea.withValues(alpha: isDark ? 0.34 : 0.26);

  /// `CodebaseAnalysisBanner`'s `offer`-state leading icon-chip fill.
  Color ideaIconTint(bool isDark) =>
      typeIdea.withValues(alpha: isDark ? 0.22 : 0.15);

  /// `CodebaseAnalysisBanner`'s "IDEAS" badge fill.
  Color ideaChipTint(bool isDark) =>
      typeIdea.withValues(alpha: isDark ? 0.20 : 0.13);

  // Generic accent tint, parameterized on an explicit accent rather than one
  // fixed instance field — every other *Tint method above closes over a single
  // color (e.g. primary/danger/typeSignal); the widened signal "Promote"
  // menu's suggested-row treatment needs the same fill formula for whichever
  // of typeEpic/typeBug the classifier suggested. Added for `AIO-1300`; see
  // its linked Documentation page, §7.3.1.
  /// A resting-state tint of [accent] at the "whisper" alpha used by the
  /// widened signal "Promote" menu's suggested-row background — fainter
  /// than [surfaceHover] so hover still reads as a state change on top of
  /// it.
  Color accentTint(Color accent, bool isDark) =>
      accent.withValues(alpha: isDark ? 0.09 : 0.06);

  // accent family — pressed-state wash for OverlayMenuItem's accented rows
  // (destructive "Delete ticket", suggested Promote-to-Epic/Bug). 1.6× the
  // existing fillAlphaArctic/fillAlphaObsidian hover wash — the deepest stop
  // in the same accent hue, matching the pressed-wash multiplier the shipped
  // Ticket Deletion Spec §2.2 established. Added for `AIO-1337`; see its
  // linked Documentation page, §1.3.
  /// The pressed-state wash of [accent] used by `OverlayMenuItem`'s
  /// accented rows — 1.6× [fillAlphaArctic]/[fillAlphaObsidian], the
  /// deepest wash stop in [accent]'s own hue.
  Color pressedAccentTint(Color accent, bool isDark) =>
      accent.withValues(alpha: isDark ? 0.256 : 0.176);

  // neutral/informational family — quiet numeric/data chrome that must not
  // read as an accent (not error/warning/success/active). Backs the
  // estimate/timeSpent rollup indicators. Added for
  // estimate-timespent-rollup-for-ticket-hierarchy; see that change's
  // design.md §0.1.
  /// `RollupIndicator`/`RollupBadge` fill — a quiet, informational tint
  /// derived from [textSecondary] so it tracks the theme automatically.
  /// No new hue is introduced.
  Color neutralTint(bool isDark) =>
      textSecondary.withValues(alpha: isDark ? 0.14 : 0.09);

  /// Hairline for the same neutral family, used when [neutralTint] must
  /// sit on a tinted background (e.g. `RollupBadge` on a selected row).
  Color neutralBorderTint(bool isDark) =>
      textSecondary.withValues(alpha: isDark ? 0.26 : 0.18);

  // primary family — faint fill under an actively-working control, and a
  // standalone focus-ring color for widgets that build their own
  // `BoxShadow` rather than going through `AionShadows.focus`. Added for
  // ai-assisted-complexity-and-estimate-suggestions; see that change's
  // design.md §0.1.
  /// `RegenerateButton`'s in-flight-state fill (§2.6 of that change's
  /// design.md).
  Color primaryWash(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.16 : 0.10);

  /// `RegenerateButton`'s focused-state ring color (§2.4 of that change's
  /// design.md) — same alpha values as `AionShadows.focus`'s default ring,
  /// exposed as a plain color for call sites that assemble their own
  /// `BoxShadow` list.
  Color focusRing(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.30 : 0.16);

  // typeChat family — _ToolProposalBanner's identity accent (the banner is
  // keyed to the CHAT type chip's own color, not primary/success/danger — see
  // that spec's §0 "Identity decision"). Mirrors dangerTint/
  // dangerBorderTint's shape exactly, keyed to typeChat instead of danger.
  // Added for `AIO-1118`; see its linked Documentation page, §4.
  /// `_ToolProposalBanner`'s fill — identical alpha level to the CHAT type
  /// chip's own tint.
  Color chatTint(bool isDark) =>
      typeChat.withValues(alpha: isDark ? 0.16 : 0.11);

  /// `_ToolProposalBanner`'s border — identical alpha level to the
  /// success/danger banner borders.
  Color chatBorderTint(bool isDark) =>
      typeChat.withValues(alpha: isDark ? 0.42 : 0.28);

  // primary family — _NoColumnsVisibleHint's motif (the board's
  // all-columns-hidden empty state). Distinct alpha stops from
  // primaryWash/focusRing above, so not reused from either. Added for
  // `AIO-1069`; see its linked Documentation page (Component Spec) §4.3.
  /// `_NoColumnsVisibleHint`'s motif border.
  Color columnsMotifBorderTint(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.30 : 0.18);

  /// `_NoColumnsVisibleHint`'s motif bar fill — flat across both themes,
  /// unlike every other tint in this family (Component Spec §4.3).
  Color get columnsMotifBarTint => primary.withValues(alpha: 0.28);

  // typeChat family — PendingSkillAttachmentBanner's AI-mark halo and
  // Confirm-button glow. Added for workflow-skill-attachments; see that
  // change's design.md (Component Spec) §6.1.
  /// `PendingSkillAttachmentBanner`'s AI-mark halo glow and Confirm
  /// button's shadow glow — both use this identical typeChat-keyed value.
  Color chatGlow(bool isDark) =>
      typeChat.withValues(alpha: isDark ? 0.55 : 0.40);

  // Generic accent tint, parameterized on an explicit accent — the
  // notification dropdown's leading outcome-icon tile fill needs the standard
  // chip alpha applied to whichever accent (success/danger/ warning/primary) a
  // given `NotificationKind` maps to (Component Spec §0.4, §6.3), the same
  // "parameterized on `accent`" shape [accentTint] already established, but at
  // the stronger chip-fill alpha ([fillAlphaArctic]/[fillAlphaObsidian])
  // rather than [accentTint]'s fainter "whisper" alpha. Added for `AIO-1586`;
  // see its linked Documentation page's Component Spec §0.1.
  /// The notification dropdown row's leading outcome-icon tile fill —
  /// [accent] at the standard chip alpha ([fillAlphaArctic]/
  /// [fillAlphaObsidian]).
  Color outcomeTileFill(Color accent, bool isDark) =>
      accent.withValues(alpha: isDark ? fillAlphaObsidian : fillAlphaArctic);

  // primary family — the `ASK ·` identity accent's own hairline, distinct from
  // the neutral `border`/`borderStrong` family used by preset/rule condition
  // chips (RB §4.1) since this is the one condition kind that costs a live
  // model round trip. Added for `AIO-613`; see its linked Documentation page's
  // "New tokens" section / Component Spec §3.2, §4.1.
  /// The `ASK ·` question chip's (canvas card, §3.2) and `ASK` badge's
  /// (outline row, §4.1) 1px hairline — the `primary`-toned sibling of
  /// RB §4.1's neutral `border` hairline.
  Color agentAccentBorderTint(bool isDark) =>
      primary.withValues(alpha: isDark ? 0.40 : 0.28);

  // danger family — agentJudgment's empty-prompt/incomplete-node error
  // treatment (Component Spec §2.5.5, §3.3, §4.3), parallel to
  // multi-project-hub's [errorRing] but at this change's own alpha stops.
  /// Error ring around an empty-prompt `AgentPromptField` (§2.5.5) and the
  /// incomplete `ASK ·` canvas node card (§3.3) — per RB §3.5.7's error
  /// convention.
  Color agentJudgmentErrorRing(bool isDark) =>
      danger.withValues(alpha: isDark ? 0.26 : 0.14);

  /// Incomplete/empty-prompt fill for the `ASK ·` outline row (§4.3) and
  /// canvas node card question chip (§3.3).
  Color agentJudgmentErrorFill(bool isDark) =>
      danger.withValues(alpha: isDark ? 0.14 : 0.08);

  // primary family — `AgentPromptField`'s text-selection fill (Component
  // Spec §2.2). Flat across both themes, like [columnsMotifBarTint] above.
  /// `AgentPromptField`'s text-selection highlight — identical alpha in
  /// both themes (§2.2).
  Color get agentPromptSelectionFill => primary.withValues(alpha: 0.24);
}
