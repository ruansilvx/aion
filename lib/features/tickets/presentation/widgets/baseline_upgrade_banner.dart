// presentation/widgets/baseline_upgrade_banner.dart — BaselineUpgradeBanner (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/presentation/widgets/banner_shell.dart';

/// Lazy, one-time-per-open offer banner shown on `TicketsListScreen` when the
/// active project's pinned baseline version isn't the latest bundled one (see
/// `ActiveProjectCubit.switchTo`'s `offerBaselineUpgrade` computation). Two
/// states, no diff/review UI: an [_OfferBanner] ("Upgrade" or dismiss ×) and,
/// once tapped, an [_UpgradingBanner] — near-instant local I/O, with no
/// separate "done" confirmation state; the version now shown wherever
/// `Project.baselineVersion` is rendered (`ProjectCard`, the Settings
/// "BASELINE" section) is confirmation enough. Added for `AIO-297`.
class BaselineUpgradeBanner extends StatefulWidget {
  /// Creates a [BaselineUpgradeBanner] offering to upgrade from
  /// [currentVersion] to [targetVersion]. [onDismiss] is called when the
  /// offer is declined, or once an accepted upgrade completes — the
  /// caller owns whether the banner stays mounted.
  const BaselineUpgradeBanner({
    super.key,
    required this.currentVersion,
    required this.targetVersion,
    required this.onDismiss,
  });

  /// The active project's currently pinned baseline version.
  final String currentVersion;

  /// The latest bundled baseline version being offered.
  final String targetVersion;

  /// Called when the user dismisses the offer, or once an accepted
  /// upgrade finishes.
  final VoidCallback onDismiss;

  @override
  State<BaselineUpgradeBanner> createState() => _BaselineUpgradeBannerState();
}

class _BaselineUpgradeBannerState extends State<BaselineUpgradeBanner> {
  bool _isUpgrading = false;

  Future<void> _accept() async {
    setState(() => _isUpgrading = true);
    await context.read<ActiveProjectProvider>().acceptBaselineUpgrade();
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: _isUpgrading
          ? _UpgradingBanner(
              key: const ValueKey('upgrading'),
              currentVersion: widget.currentVersion,
              targetVersion: widget.targetVersion,
            )
          : _OfferBanner(
              key: const ValueKey('offer'),
              targetVersion: widget.targetVersion,
              onAccept: _accept,
              onDismiss: widget.onDismiss,
            ),
    );
  }
}

/// The offer state: an icon chip, title + version-naming body, a primary
/// "Upgrade" action, and a dismiss ×.
class _OfferBanner extends StatelessWidget {
  const _OfferBanner({
    super.key,
    required this.targetVersion,
    required this.onAccept,
    required this.onDismiss,
  });

  final String targetVersion;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    return BannerShell(
      fill: c.noticeFill(isDark),
      border: c.noticeBorder(isDark),
      onDismiss: onDismiss,
      dismissSemanticLabel: context.l10n.baselineUpgradeDismissLabel,
      child: Padding(
        padding: const EdgeInsets.only(right: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BannerIconChip(
                  fill: c.noticeIconTint(isDark),
                  icon: PhosphorIcons.arrowUpLight,
                  iconColor: c.primary,
                ),
                const SizedBox(width: AionSpacing.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.baselineUpgradeOfferTitle,
                        style: AionText.h2.copyWith(
                          fontSize: 15,
                          color: c.textPrimary,
                        ),
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
                              text: context.l10n.baselineUpgradeOfferBodyBefore,
                            ),
                            _VersionPill(text: 'v$targetVersion', colors: c),
                            TextSpan(
                              text: context.l10n.baselineUpgradeOfferBodyAfter,
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
              child: AppButton(
                label: context.l10n.baselineUpgradeAcceptLabel,
                onPressed: onAccept,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An inline monospace pill for the version named in [_OfferBanner]'s
/// body text — mirrors `CodebaseAnalysisBanner`'s `_InlineCodeSpan`
/// treatment.
class _VersionPill extends WidgetSpan {
  _VersionPill({required String text, required AionColors colors})
    : super(
        alignment: PlaceholderAlignment.middle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceHover,
            borderRadius: const BorderRadius.all(Radius.circular(5)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(
              text,
              style: AionText.key.copyWith(
                fontSize: 12,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      );
}

/// The upgrading state, entered immediately when "Upgrade" is tapped —
/// near-instant local I/O, so there's no dismiss control. Shell
/// dimensions match [_OfferBanner] so there's no reflow.
class _UpgradingBanner extends StatelessWidget {
  const _UpgradingBanner({
    super.key,
    required this.currentVersion,
    required this.targetVersion,
  });

  final String currentVersion;
  final String targetVersion;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    return BannerShell(
      fill: c.pendingTint(isDark),
      border: c.noticeBorder(isDark),
      child: Padding(
        padding: const EdgeInsets.only(right: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        context.l10n.baselineUpgradeUpgradingTitle,
                        style: AionText.h2.copyWith(
                          fontSize: 15,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.l10n.baselineUpgradeUpgradingStatus(
                          'v$currentVersion',
                          'v$targetVersion',
                        ),
                        style: AionText.streamStatus.copyWith(
                          color: c.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.only(left: 46),
              child: _UpgradingButton(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The disabled, spinner-labeled "Upgrading…" action row shown while
/// [_UpgradingBanner] is mounted — hand-rolled because [AppButton] has no
/// built-in spinner-with-label state, mirroring how
/// `CodebaseAnalysisBanner`'s `_DepthChoiceButton`/`_HideButton` hand-roll
/// one-off treatments beyond [AppButton]'s built-in capability.
class _UpgradingButton extends StatelessWidget {
  const _UpgradingButton();

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.45),
        borderRadius: const BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 13, height: 13, child: AppSpinner(size: 13)),
            const SizedBox(width: AionSpacing.sp8),
            Text(
              context.l10n.baselineUpgradeUpgradingLabel,
              style: AionText.button.copyWith(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
