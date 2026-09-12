// presentation/widgets/gitignore_confirmation_banner.dart — GitignoreConfirmationBanner (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';

/// Inline, pre-submit banner shown on `NewProjectScreen` the moment the chosen
/// directory is detected as an existing git repository (see
/// `NewProjectScreen._browseDirectory`'s `GitRepositoryClient.isGitRepository`
/// check). Offers two independent first-run choices, in a single divided
/// choice group:
///
/// 1. Auto-exclude Aion's own bookkeeping (`.aion/`, and `tickets/` unless a
///    separate tickets repo is also chosen) from that repo's `.gitignore`,
///    checked by default.
/// 2. Keep tickets in their own repository (`.aion/tickets-repo`) instead of
///    projecting them under the chosen directory, unchecked by default, with
///    an optional remote-URL field revealed when checked.
///
/// Informational **notice** tone throughout — this is Aion's inform-don't-
/// block posture, never a hard warning that blocks submission. Per
/// `AIO-1266` §2, extended for the separate-tickets-repo choice per
/// `AIO-2857`.
class GitignoreConfirmationBanner extends StatelessWidget {
  /// Creates a [GitignoreConfirmationBanner] reflecting [excludeAionPaths]
  /// and [separateTicketsRepo]; calls the matching `onChanged` callback when
  /// either checkbox (or its label) is activated. [ticketsRepoRemoteUrlController]
  /// backs the optional remote-URL field revealed when [separateTicketsRepo]
  /// is `true` — its text is read by the caller at submit time, not passed
  /// as a separate value here, so typing doesn't need to round-trip through
  /// `setState`.
  const GitignoreConfirmationBanner({
    super.key,
    required this.excludeAionPaths,
    required this.onExcludeAionPathsChanged,
    required this.separateTicketsRepo,
    required this.onSeparateTicketsRepoChanged,
    required this.ticketsRepoRemoteUrlController,
  });

  /// Whether the "add `.aion/`[/`tickets/`] to `.gitignore`" checkbox is
  /// currently checked.
  final bool excludeAionPaths;

  /// Called with the toggled value when the gitignore checkbox or its label
  /// is activated.
  final ValueChanged<bool> onExcludeAionPathsChanged;

  /// Whether "keep tickets in their own repository" is currently checked.
  final bool separateTicketsRepo;

  /// Called with the toggled value when the separate-tickets-repo checkbox
  /// or its label is activated.
  final ValueChanged<bool> onSeparateTicketsRepoChanged;

  /// Backs the optional remote-URL field revealed when [separateTicketsRepo]
  /// is `true`. Left as-typed (not cleared) when the checkbox is unchecked,
  /// so re-checking restores it.
  final TextEditingController ticketsRepoRemoteUrlController;

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
            Padding(
              padding: const EdgeInsets.only(left: 39),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GitignoreChoiceRow(
                    colors: c,
                    value: excludeAionPaths,
                    separateTicketsRepo: separateTicketsRepo,
                    onChanged: onExcludeAionPathsChanged,
                  ),
                  const SizedBox(height: 11),
                  DecoratedBox(
                    decoration: BoxDecoration(color: c.noticeDivider(isDark)),
                    child: const SizedBox(height: 1),
                  ),
                  const SizedBox(height: 11),
                  _SeparateTicketsRepoChoiceRow(
                    colors: c,
                    value: separateTicketsRepo,
                    onChanged: onSeparateTicketsRepoChanged,
                  ),
                  _RevealedTicketsRepoRemoteSection(
                    colors: c,
                    show: separateTicketsRepo,
                    controller: ticketsRepoRemoteUrlController,
                  ),
                ],
              ),
            ),
            if (!excludeAionPaths) ...[
              const SizedBox(height: 10),
              _UncheckedHint(
                colors: c,
                separateTicketsRepo: separateTicketsRepo,
              ),
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
              Text(
                context.l10n.newProjectRepoChoicesBody,
                style: AionText.bodySm.copyWith(
                  color: c.textSecondary,
                  height: 1.5,
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
/// path fragment inside this banner's body/label/hint text.
class _PathChip extends WidgetSpan {
  _PathChip({
    required String text,
    required AionColors colors,
    double fontSize = 12,
  }) : super(
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
                 fontSize: fontSize,
                 color: colors.textSecondary,
               ),
             ),
           ),
         ),
       );
}

/// §2.3 — the existing gitignore checkbox, whose label narrows from
/// `.aion/`+`tickets/` to just `.aion/` once [separateTicketsRepo] is
/// checked (that project's source repo never gets a `tickets/` directory in
/// that case). The label swap animates via [AnimatedSize] + [FadeTransition]
/// rather than popping instantly, since the pointer is on the *other*
/// checkbox when it happens.
class _GitignoreChoiceRow extends StatelessWidget {
  const _GitignoreChoiceRow({
    required this.colors,
    required this.value,
    required this.separateTicketsRepo,
    required this.onChanged,
  });

  final AionColors colors;
  final bool value;
  final bool separateTicketsRepo;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final l10n = context.l10n;
    final semanticLabel = separateTicketsRepo
        ? '${l10n.newProjectGitignoreCheckboxLabelAionOnlyBefore}.aion/'
              '${l10n.newProjectGitignoreCheckboxLabelAionOnlyAfter}'
        : '${l10n.newProjectGitignoreCheckboxLabelBefore}.aion/'
              '${l10n.newProjectGitignoreCheckboxLabelMiddle}tickets/'
              '${l10n.newProjectGitignoreCheckboxLabelAfter}';

    return Semantics(
      button: true,
      checked: value,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppCheckbox(value: value, onChanged: onChanged),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(!value),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: Alignment.topLeft,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Text.rich(
                      key: ValueKey(separateTicketsRepo),
                      TextSpan(
                        style: AionText.body.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        children: separateTicketsRepo
                            ? [
                                TextSpan(
                                  text: l10n
                                      .newProjectGitignoreCheckboxLabelAionOnlyBefore,
                                ),
                                _PathChip(text: '.aion/', colors: c),
                                TextSpan(
                                  text: l10n
                                      .newProjectGitignoreCheckboxLabelAionOnlyAfter,
                                ),
                              ]
                            : [
                                TextSpan(
                                  text: l10n
                                      .newProjectGitignoreCheckboxLabelBefore,
                                ),
                                _PathChip(text: '.aion/', colors: c),
                                TextSpan(
                                  text: l10n
                                      .newProjectGitignoreCheckboxLabelMiddle,
                                ),
                                _PathChip(text: 'tickets/', colors: c),
                                TextSpan(
                                  text: l10n
                                      .newProjectGitignoreCheckboxLabelAfter,
                                ),
                              ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// §2.4 — the new "keep tickets in their own repository" checkbox.
class _SeparateTicketsRepoChoiceRow extends StatelessWidget {
  const _SeparateTicketsRepoChoiceRow({
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
    final l10n = context.l10n;
    final semanticLabel =
        '${l10n.newProjectSeparateTicketsRepoLabel}. '
        '${l10n.newProjectSeparateTicketsRepoHintBefore}.aion/tickets-repo'
        '${l10n.newProjectSeparateTicketsRepoHintAfter}';

    return Semantics(
      button: true,
      checked: value,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AppCheckbox(value: value, onChanged: onChanged),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(!value),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.newProjectSeparateTicketsRepoLabel,
                      style: AionText.body.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        style: AionText.bodySm.copyWith(
                          fontSize: 12,
                          color: c.textMuted,
                          height: 1.45,
                        ),
                        children: [
                          TextSpan(
                            text: l10n.newProjectSeparateTicketsRepoHintBefore,
                          ),
                          _PathChip(
                            text: '.aion/tickets-repo',
                            colors: c,
                            fontSize: 11.5,
                          ),
                          TextSpan(
                            text: l10n.newProjectSeparateTicketsRepoHintAfter,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// §2.5 — wraps [_TicketsRepoRemoteField] in the reveal/hide animation
/// ([AnimatedSize] + [FadeTransition], 180ms `Curves.easeOut`, matching the
/// banner's own mount treatment in `NewProjectScreen`), and, once the field
/// is revealed, scrolls it into view if the reveal pushed it below the
/// visible viewport.
class _RevealedTicketsRepoRemoteSection extends StatefulWidget {
  const _RevealedTicketsRepoRemoteSection({
    required this.colors,
    required this.show,
    required this.controller,
  });

  final AionColors colors;
  final bool show;
  final TextEditingController controller;

  @override
  State<_RevealedTicketsRepoRemoteSection> createState() =>
      _RevealedTicketsRepoRemoteSectionState();
}

class _RevealedTicketsRepoRemoteSectionState
    extends State<_RevealedTicketsRepoRemoteSection> {
  static const _duration = Duration(milliseconds: 180);
  final _fieldKey = GlobalKey();

  @override
  void didUpdateWidget(covariant _RevealedTicketsRepoRemoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) {
      Future.delayed(_duration, () {
        final fieldContext = _fieldKey.currentContext;
        if (fieldContext == null || !fieldContext.mounted) return;
        Scrollable.ensureVisible(
          fieldContext,
          duration: _duration,
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _duration,
      curve: Curves.easeOut,
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: _duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeOut,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: widget.show
            ? Padding(
                key: const ValueKey('shown'),
                padding: const EdgeInsets.only(top: 11),
                child: KeyedSubtree(
                  key: _fieldKey,
                  child: _TicketsRepoRemoteField(
                    colors: widget.colors,
                    controller: widget.controller,
                  ),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('hidden')),
      ),
    );
  }
}

/// §2.5 — the optional remote-URL field, indented to the second checkbox's
/// text block (18px box + 10px gap → 28px).
class _TicketsRepoRemoteField extends StatelessWidget {
  const _TicketsRepoRemoteField({
    required this.colors,
    required this.controller,
  });

  final AionColors colors;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(left: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: controller,
            labelText: l10n.newProjectTicketsRepoRemoteLabel,
            isOptional: true,
            hintText: l10n.newProjectTicketsRepoRemotePlaceholder,
            style: AionText.key.copyWith(fontWeight: FontWeight.w400),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final isEmpty = value.text.trim().isEmpty;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _RemoteHint(
                  key: ValueKey(isEmpty),
                  colors: c,
                  isEmpty: isEmpty,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RemoteHint extends StatelessWidget {
  const _RemoteHint({super.key, required this.colors, required this.isEmpty});

  final AionColors colors;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: PhosphorIcon(
            PhosphorIcons.infoLight,
            size: 12,
            color: c.textMuted,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: isEmpty
              ? Text(
                  l10n.newProjectTicketsRepoRemoteHintBlank,
                  style: AionText.bodySm.copyWith(
                    fontSize: 11.5,
                    color: c.textMuted,
                    height: 1.4,
                  ),
                )
              : Text.rich(
                  TextSpan(
                    style: AionText.bodySm.copyWith(
                      fontSize: 11.5,
                      color: c.textMuted,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: l10n.newProjectTicketsRepoRemoteHintSetBefore,
                      ),
                      _PathChip(text: 'origin', colors: c, fontSize: 11.5),
                      TextSpan(
                        text: l10n.newProjectTicketsRepoRemoteHintSetAfter,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _UncheckedHint extends StatelessWidget {
  const _UncheckedHint({
    required this.colors,
    required this.separateTicketsRepo,
  });

  final AionColors colors;
  final bool separateTicketsRepo;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(left: 39),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: PhosphorIcon(
              PhosphorIcons.warningLight,
              size: 13,
              color: c.warning,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: separateTicketsRepo
                ? Text.rich(
                    TextSpan(
                      style: AionText.bodySm.copyWith(
                        fontSize: 12,
                        color: c.textMuted,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: l10n
                              .newProjectGitignoreUncheckedHintAionOnlyBefore,
                        ),
                        _PathChip(text: '.aion/', colors: c),
                        TextSpan(
                          text: l10n
                              .newProjectGitignoreUncheckedHintAionOnlyAfter,
                        ),
                      ],
                    ),
                  )
                : Text(
                    l10n.newProjectGitignoreUncheckedHint,
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
