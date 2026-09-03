// presentation/widgets/gitignore_confirmation_banner.dart — GitignoreConfirmationBanner (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// Inline, pre-submit banner shown on `NewProjectScreen` the moment the
/// chosen directory is detected as an existing git repository (see
/// `NewProjectScreen._browseDirectory`'s
/// `GitRepositoryClient.isGitRepository` check). Offers to auto-exclude
/// Aion's own bookkeeping (`.aion/`, `tickets/`) from that repo's
/// `.gitignore` via a checkbox, checked by default. Informational
/// **notice** tone throughout — this is Aion's inform-don't-block
/// posture, never a hard warning that blocks submission. Per
/// `AIO-1266` §2.
class GitignoreConfirmationBanner extends StatelessWidget {
  /// Creates a [GitignoreConfirmationBanner] reflecting [excludeAionPaths];
  /// calls [onChanged] with the toggled value when the checkbox (or its
  /// label) is activated.
  const GitignoreConfirmationBanner({
    super.key,
    required this.excludeAionPaths,
    required this.onChanged,
  });

  /// Whether the "add `.aion/`/`tickets/` to `.gitignore`" checkbox is
  /// currently checked.
  final bool excludeAionPaths;

  /// Called with the toggled value when the checkbox or its label is
  /// activated.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.noticeFill(isDark),
        border: Border.all(color: c.noticeBorder(isDark)),
        borderRadius: const BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MessageRow(colors: c, isDark: isDark),
            const SizedBox(height: AionSpacing.sp12),
            _CheckboxRow(
              colors: c,
              value: excludeAionPaths,
              onChanged: onChanged,
            ),
            if (!excludeAionPaths) ...[
              const SizedBox(height: 10),
              _UncheckedHint(colors: c),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.colors, required this.isDark});

  final AionColors colors;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.noticeIconTint(isDark),
              borderRadius: const BorderRadius.all(AionRadius.iconBtnSm),
            ),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: PhosphorIcon(
                  PhosphorIcons.gitBranchLight,
                  size: 17,
                  color: c.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.newProjectGitignoreBannerTitle,
                style: AionText.cardTitle.copyWith(
                  color: c.textPrimary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(
                  style: AionText.bodySm.copyWith(
                    color: c.textSecondary,
                    height: 1.5,
                  ),
                  children: [
                    TextSpan(
                      text: context.l10n.newProjectGitignoreBannerBodyBefore,
                    ),
                    _PathChip(text: '.aion/', colors: c),
                    TextSpan(
                      text:
                          context.l10n.newProjectGitignoreBannerBodyMiddle,
                    ),
                    _PathChip(text: 'tickets/', colors: c),
                    TextSpan(
                      text: context.l10n.newProjectGitignoreBannerBodyAfter,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// An inline monospace pill (surface-tinted background) for a bookkeeping
/// path fragment inside [_MessageRow]'s body text.
class _PathChip extends WidgetSpan {
  _PathChip({required String text, required AionColors colors})
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

class _CheckboxRow extends StatelessWidget {
  const _CheckboxRow({
    required this.colors,
    required this.value,
    required this.onChanged,
  });

  final AionColors colors;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(left: 39),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppCheckbox(value: value, onChanged: onChanged),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: Text.rich(
                TextSpan(
                  style: AionText.body.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: context.l10n.newProjectGitignoreCheckboxLabelBefore,
                    ),
                    TextSpan(
                      text: '.aion/',
                      style: AionText.key.copyWith(
                        fontSize: 12,
                        color: c.textSecondary,
                      ),
                    ),
                    TextSpan(
                      text: context.l10n.newProjectGitignoreCheckboxLabelMiddle,
                    ),
                    TextSpan(
                      text: 'tickets/',
                      style: AionText.key.copyWith(
                        fontSize: 12,
                        color: c.textSecondary,
                      ),
                    ),
                    TextSpan(
                      text: context.l10n.newProjectGitignoreCheckboxLabelAfter,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UncheckedHint extends StatelessWidget {
  const _UncheckedHint({required this.colors});

  final AionColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(left: 39),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PhosphorIcon(PhosphorIcons.warningLight, size: 13, color: c.warning),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              context.l10n.newProjectGitignoreUncheckedHint,
              style: AionText.bodySm.copyWith(
                fontSize: 12,
                color: c.textMuted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
