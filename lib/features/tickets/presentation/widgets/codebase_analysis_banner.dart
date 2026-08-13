// presentation/widgets/codebase_analysis_banner.dart — CodebaseAnalysisBanner (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/enums/summarization_depth.dart';
import 'package:aion/features/tickets/presentation/cubit/codebase_analysis_status.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/widgets/banner_shell.dart';

/// Once-only, dismissible banner offering an opt-in codebase-summarization
/// scan — shown on `TicketsListScreen` immediately after a project is
/// created from an already-git-tracked directory (see
/// `ActiveProjectCubit.consumeCodebaseAnalysisOffer`). Subscribes directly
/// to `TicketsCubit.codebaseAnalysisStatus` and renders one of four
/// states: the depth-choice offer ([CodebaseAnalysisIdle]), a live
/// progress readout ([CodebaseAnalysisRunning]), a success summary
/// ([CodebaseAnalysisDone]), or a failure message
/// ([CodebaseAnalysisFailed]). Per
/// `aion-arch/changes/new-project-onboarding/design.md` §3.
///
/// The running state's "Hide" control does not stop the in-flight scan —
/// `AgentModelClient` exposes no cancellation — it only removes the
/// banner from view; any tickets the run drafts still appear in the list
/// once it finishes. Added for `aion-arch/changes/new-project-onboarding`.
class CodebaseAnalysisBanner extends StatelessWidget {
  /// Creates a [CodebaseAnalysisBanner]. [onDismiss] is called whenever
  /// the banner's dismiss control (× in the offer/done/failed states,
  /// "Hide" in the running state) is activated — the caller owns whether
  /// the banner stays mounted.
  const CodebaseAnalysisBanner({super.key, required this.onDismiss});

  /// Called when the user dismisses the banner.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TicketsCubit>();

    return StreamBuilder<CodebaseAnalysisStatus>(
      stream: cubit.codebaseAnalysisStatus,
      initialData: const CodebaseAnalysisIdle(),
      builder: (context, snapshot) {
        final status = snapshot.data ?? const CodebaseAnalysisIdle();
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: KeyedSubtree(
            key: ValueKey(status.runtimeType),
            child: switch (status) {
              CodebaseAnalysisIdle() => _OfferBanner(
                projectName: cubit.projectName,
                onPickDepth: (depth) =>
                    cubit.runCodebaseSummarization(depth: depth),
                onDismiss: onDismiss,
              ),
              CodebaseAnalysisRunning(:final depth, :final statusText) =>
                _RunningBanner(
                  depth: depth,
                  statusText: statusText,
                  onHide: onDismiss,
                ),
              CodebaseAnalysisDone(:final count) => _DoneBanner(
                count: count,
                onDismiss: onDismiss,
              ),
              CodebaseAnalysisFailed(:final message) => _FailedBanner(
                message: message,
                onDismiss: onDismiss,
              ),
            },
          ),
        );
      },
    );
  }
}

/// The [CodebaseAnalysisIdle] state: an offer to scan, a depth choice
/// (shallow/full), and a dismiss ×.
class _OfferBanner extends StatelessWidget {
  const _OfferBanner({
    required this.projectName,
    required this.onPickDepth,
    required this.onDismiss,
  });

  /// The active project's display name, inlined (monospace) into the
  /// body copy per design.md §3.1 — `null` falls back to generic
  /// wording (`codebaseAnalysisOfferBodyFallbackName`).
  final String? projectName;

  final ValueChanged<SummarizationDepth> onPickDepth;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    return BannerShell(
      fill: c.ideaFill(isDark),
      border: c.ideaBorderTint(isDark),
      onDismiss: onDismiss,
      dismissSemanticLabel: context.l10n.codebaseAnalysisDismissLabel,
      child: Padding(
        padding: const EdgeInsets.only(right: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BannerIconChip(
                  fill: c.ideaIconTint(isDark),
                  icon: PhosphorIcons.magnifyingGlassPlusLight,
                  iconColor: c.typeIdea,
                ),
                const SizedBox(width: AionSpacing.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              context.l10n.codebaseAnalysisOfferTitle,
                              style: AionText.h2.copyWith(
                                fontSize: 15,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AionSpacing.sp8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.ideaChipTint(isDark),
                              borderRadius: const BorderRadius.all(
                                AionRadius.sm,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              child: Text(
                                context.l10n.codebaseAnalysisOfferBadge,
                                style: AionText.chip.copyWith(
                                  color: c.typeIdea,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          style: AionText.bodySm.copyWith(
                            color: c.textSecondary,
                            height: 1.5,
                          ),
                          children: [
                            TextSpan(
                              text: context.l10n.codebaseAnalysisOfferBodyBefore,
                            ),
                            _InlineCodeSpan(
                              text:
                                  projectName ??
                                  context
                                      .l10n
                                      .codebaseAnalysisOfferBodyFallbackName,
                              colors: c,
                            ),
                            TextSpan(
                              text:
                                  context.l10n.codebaseAnalysisOfferBodyMiddle,
                            ),
                            TextSpan(
                              text: context.l10n.codebaseAnalysisOfferBodyIdea,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ).copyWith(color: c.typeIdea),
                            ),
                            TextSpan(
                              text: context.l10n.codebaseAnalysisOfferBodyAfter,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Row(
                children: [
                  Expanded(
                    child: _DepthChoiceButton(
                      label: context.l10n.codebaseAnalysisShallowLabel,
                      hint: context.l10n.codebaseAnalysisShallowHint,
                      isPrimary: true,
                      onTap: () => onPickDepth(SummarizationDepth.shallow),
                    ),
                  ),
                  const SizedBox(width: AionSpacing.sp12),
                  Expanded(
                    child: _DepthChoiceButton(
                      label: context.l10n.codebaseAnalysisFullLabel,
                      hint: context.l10n.codebaseAnalysisFullHint,
                      isPrimary: false,
                      onTap: () => onPickDepth(SummarizationDepth.full),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An inline monospace pill (`surfaceHover`-tinted background) for the
/// project name embedded in [_OfferBanner]'s body text, per design.md
/// §3.1 (mirrors `GitignoreConfirmationBanner`'s `_PathChip`).
class _InlineCodeSpan extends WidgetSpan {
  _InlineCodeSpan({required String text, required AionColors colors})
    : super(
        alignment: PlaceholderAlignment.middle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceHover,
            borderRadius: const BorderRadius.all(Radius.circular(4)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            child: Text(
              text,
              style: AionText.key.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      );
}

/// A two-line (label + hint) depth-choice button — `AppButton` only
/// supports a single-line label, so this hand-rolls the same
/// primary/secondary visual language for the two-line case, mirroring
/// `AppButton`'s own hover/press states.
class _DepthChoiceButton extends StatefulWidget {
  const _DepthChoiceButton({
    required this.label,
    required this.hint,
    required this.isPrimary,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  State<_DepthChoiceButton> createState() => _DepthChoiceButtonState();
}

class _DepthChoiceButtonState extends State<_DepthChoiceButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final fill = widget.isPrimary
        ? (_isHovered ? c.primaryHover : c.primary)
        : (_isPressed
              ? c.border
              : (_isHovered ? c.surfaceHover : c.surface));
    final labelColor = widget.isPrimary
        ? const Color(0xFFFFFFFF)
        : c.textPrimary;
    final hintColor = widget.isPrimary
        ? const Color(0xFFFFFFFF).withValues(alpha: t.isDark ? 0.72 : 0.82)
        : c.textMuted;

    return Semantics(
      button: true,
      label: '${widget.label} — ${widget.hint}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedScale(
            scale: _isPressed ? 0.98 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: const BorderRadius.all(AionRadius.md),
                border: widget.isPrimary
                    ? null
                    : Border.all(color: c.borderStrong),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: AionText.button.copyWith(
                        fontSize: 13.5,
                        color: labelColor,
                      ),
                    ),
                    Text(
                      widget.hint,
                      style: AionText.bodySm.copyWith(
                        fontSize: 11.5,
                        color: hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The [CodebaseAnalysisRunning] state: a spinner, a depth-specific
/// title, and a live status line, plus a "Hide" control instead of a
/// dismiss ×.
class _RunningBanner extends StatelessWidget {
  const _RunningBanner({
    required this.depth,
    required this.statusText,
    required this.onHide,
  });

  /// Which scan depth is running — selects between the "— shallow scan"
  /// and "— full scan" title variants (design.md §3.2).
  final SummarizationDepth depth;
  final String? statusText;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    return BannerShell(
      fill: c.pendingTint(isDark),
      border: c.pendingTint(isDark),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.pendingIconTint(isDark),
              borderRadius: const BorderRadius.all(AionRadius.sm),
            ),
            child: const SizedBox(
              width: 34,
              height: 34,
              child: Center(child: AppSpinner(size: 17)),
            ),
          ),
          const SizedBox(width: AionSpacing.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  depth == SummarizationDepth.shallow
                      ? context.l10n.codebaseAnalysisRunningTitleShallow
                      : context.l10n.codebaseAnalysisRunningTitleFull,
                  style: AionText.h2.copyWith(
                    fontSize: 15,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  statusText ?? context.l10n.codebaseAnalysisRunningDefaultStatus,
                  style: AionText.streamStatus.copyWith(
                    color: c.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AionSpacing.sp12),
          _HideButton(onTap: onHide),
        ],
      ),
    );
  }
}

class _HideButton extends StatefulWidget {
  const _HideButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_HideButton> createState() => _HideButtonState();
}

class _HideButtonState extends State<_HideButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: const BorderRadius.all(AionRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(
              context.l10n.codebaseAnalysisHideAction,
              style: AionText.button.copyWith(
                fontSize: 12.5,
                color: _isHovered ? c.textPrimary : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The [CodebaseAnalysisDone] state: a success confirmation with the
/// created-ticket count.
class _DoneBanner extends StatelessWidget {
  const _DoneBanner({required this.count, required this.onDismiss});

  final int count;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    return BannerShell(
      fill: c.repairedTint(isDark),
      border: c.repairedBorderTint(isDark),
      onDismiss: onDismiss,
      dismissSemanticLabel: context.l10n.codebaseAnalysisDismissLabel,
      child: Padding(
        padding: const EdgeInsets.only(right: 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BannerIconChip(
              fill: c.repairedIconTint(isDark),
              icon: PhosphorIcons.checkLight,
              iconColor: c.success,
            ),
            const SizedBox(width: AionSpacing.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.codebaseAnalysisDoneTitle(count),
                    style: AionText.h2.copyWith(
                      fontSize: 15,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.codebaseAnalysisDoneBody,
                    style: AionText.bodySm.copyWith(
                      color: c.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The [CodebaseAnalysisFailed] state: a soft failure message — no retry
/// in v1 (see design.md §3.4).
class _FailedBanner extends StatelessWidget {
  const _FailedBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    return BannerShell(
      fill: c.dangerTint(isDark),
      border: c.dangerBorderTint(isDark),
      onDismiss: onDismiss,
      dismissSemanticLabel: context.l10n.codebaseAnalysisDismissLabel,
      child: Padding(
        padding: const EdgeInsets.only(right: 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BannerIconChip(
              fill: c.dangerIconTint(isDark),
              icon: PhosphorIcons.warningLight,
              iconColor: c.danger,
              iconSize: 18,
            ),
            const SizedBox(width: AionSpacing.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.codebaseAnalysisFailedTitle,
                    style: AionText.h2.copyWith(
                      fontSize: 15,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.codebaseAnalysisFailedBody,
                    style: AionText.bodySm.copyWith(
                      color: c.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
