// presentation/screens/release_draft_screen.dart — ReleaseDraftScreen (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/release_draft.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';

/// Semver-ish validator for the version field: `major.minor.patch`, with
/// an optional `-suffix`. Deliberately permissive (doesn't enforce
/// numeric-only segments beyond the three dot-separated ones) since this
/// is a UX guard against an obviously-malformed value, not a full semver
/// grammar.
final RegExp _semverPattern = RegExp(r'^\d+\.\d+\.\d+(-[\w.]+)?$');

/// The AI-drafted [ReleaseDraft] review screen — reached only by pushing
/// via [Navigator.push] from [ReleaseSummarySection] (no `go_router`
/// route; this is a transient review step, not something deep-linked to).
/// Shows [ReleaseDraft.changelogMarkdown]/[ReleaseDraft.suggestedVersion]
/// as freely editable fields; nothing is written to git until Confirm &
/// Tag (gated by [showAppConfirmDialog]) resolves. When
/// [ReleaseDraft.detectedVersionFile] is `null`, the version field is
/// replaced by a "no version file detected" notice and the confirm
/// action relabels to Save changelog, skipping the confirmation dialog —
/// there's no tag name to confirm — but still calling
/// [TicketsCubit.confirmRelease] (the only write path this change adds;
/// see that method's dartdoc for why it always tags/pushes regardless of
/// a version-file bump being available). On failure, stays on screen
/// with an error banner and the same editable draft, so a retry doesn't
/// require redrafting from scratch. Added for
/// `aion-arch/changes/release-preparation-and-tagging`; see that
/// change's design.md §5.3.
class ReleaseDraftScreen extends StatefulWidget {
  /// Creates a [ReleaseDraftScreen] reviewing [draft].
  const ReleaseDraftScreen({super.key, required this.draft});

  /// The drafted release to review/edit/confirm.
  final ReleaseDraft draft;

  @override
  State<ReleaseDraftScreen> createState() => _ReleaseDraftScreenState();
}

class _ReleaseDraftScreenState extends State<ReleaseDraftScreen> {
  late final TextEditingController _changelogController;
  late final TextEditingController _versionController;

  /// Whether [TicketsCubit.confirmRelease] is currently in flight —
  /// disables both fields and both footer actions.
  bool _confirming = false;

  /// The raw error from the most recent failed [TicketsCubit
  /// .confirmRelease] call, or `null` when there's nothing to show. Shown
  /// as the push-failure banner (design.md §5) rather than a toast/dialog
  /// — the draft stays mounted and editable underneath so a retry is
  /// possible without redrafting.
  String? _errorMessage;

  /// Whether the changelog field's required-field error is currently
  /// shown — set on a failed confirm attempt, cleared on the first
  /// keystroke that leaves non-whitespace content (design.md §3.4).
  bool _showChangelogError = false;

  /// Whether the version field's semver-format error is currently shown.
  /// Only ever meaningful when [ReleaseDraft.detectedVersionFile] is
  /// non-`null` — the field doesn't exist otherwise.
  bool _showVersionError = false;

  bool get _hasVersionFile => widget.draft.detectedVersionFile != null;

  @override
  void initState() {
    super.initState();
    _changelogController = TextEditingController(
      text: widget.draft.changelogMarkdown,
    );
    _versionController = TextEditingController(
      text: widget.draft.suggestedVersion,
    );
    _changelogController.addListener(_handleChangelogChanged);
    _versionController.addListener(_handleVersionChanged);
  }

  @override
  void dispose() {
    _changelogController.dispose();
    _versionController.dispose();
    super.dispose();
  }

  void _handleChangelogChanged() {
    if (_showChangelogError && _changelogController.text.trim().isNotEmpty) {
      setState(() => _showChangelogError = false);
    }
  }

  void _handleVersionChanged() {
    if (_showVersionError &&
        _semverPattern.hasMatch(_versionController.text.trim())) {
      setState(() => _showVersionError = false);
    }
    // The derived tag name lives in the header/dialog copy below, always
    // recomputed live from the controller — no separate state to keep in
    // sync.
    setState(() {});
  }

  String get _tagName => 'v${_versionController.text.trim()}';

  /// Validates both fields, showing their error states if invalid.
  /// Returns whether the draft is confirmable as-is.
  bool _validate() {
    final changelogEmpty = _changelogController.text.trim().isEmpty;
    final versionInvalid =
        _hasVersionFile &&
        !_semverPattern.hasMatch(_versionController.text.trim());
    setState(() {
      _showChangelogError = changelogEmpty;
      _showVersionError = versionInvalid;
    });
    return !changelogEmpty && !versionInvalid;
  }

  Future<void> _handleConfirmTagPressed() async {
    if (!_validate()) return;

    if (_hasVersionFile) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: context.l10n.releaseDraftConfirmDialogTitle,
        message: context.l10n.releaseDraftConfirmDialogMessage(_tagName),
        confirmLabel: context.l10n.releaseDraftConfirmDialogAction,
        tone: ConfirmDialogTone.reversible,
      );
      if (confirmed != true || !mounted) return;
    }

    await _confirm();
  }

  Future<void> _confirm() async {
    setState(() {
      _confirming = true;
      _errorMessage = null;
    });
    final editedDraft = ReleaseDraft(
      releaseTicketId: widget.draft.releaseTicketId,
      linkedTicketIds: widget.draft.linkedTicketIds,
      changelogMarkdown: _changelogController.text.trim(),
      suggestedVersion: _versionController.text.trim(),
      detectedVersionFile: widget.draft.detectedVersionFile,
    );
    try {
      await context.read<TicketsCubit>().confirmRelease(editedDraft);
      if (!mounted) return;
      AppToast.show(
        context,
        context.l10n.releaseDraftSuccessToast(_tagName),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _handleBackPressed() async {
    final edited =
        _changelogController.text.trim() !=
            widget.draft.changelogMarkdown.trim() ||
        _versionController.text.trim() != widget.draft.suggestedVersion.trim();
    if (edited) {
      final discard = await showAppConfirmDialog(
        context,
        title: context.l10n.releaseDraftDiscardConfirmTitle,
        message: context.l10n.releaseDraftDiscardConfirmMessage,
        confirmLabel: context.l10n.releaseDraftDiscardConfirmAction,
        tone: ConfirmDialogTone.destructive,
      );
      if (discard != true || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          _Header(onBack: _confirming ? null : _handleBackPressed),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
              child: ContentMaxWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) ...[
                      _PushFailureBanner(
                        message: _errorMessage!,
                        onDismiss: () =>
                            setState(() => _errorMessage = null),
                      ),
                      const SizedBox(height: AionSpacing.sp20),
                    ],
                    Text(
                      context.l10n.releaseDraftChangelogLabel,
                      style: AionText.label.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(height: AionSpacing.sp8),
                    AppTextField(
                      controller: _changelogController,
                      maxLines: null,
                      hintText: context.l10n.releaseDraftChangelogPlaceholder,
                      isError: _showChangelogError,
                    ),
                    if (_showChangelogError) ...[
                      const SizedBox(height: AionSpacing.sp8),
                      _FieldError(
                        message: context.l10n.releaseDraftChangelogRequiredError,
                      ),
                    ],
                    const SizedBox(height: AionSpacing.sp20),
                    if (_hasVersionFile) ...[
                      Text(
                        context.l10n.releaseDraftVersionLabel,
                        style: AionText.label.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AionSpacing.sp8),
                      AppTextField(
                        controller: _versionController,
                        hintText: context.l10n.releaseDraftVersionPlaceholder,
                        isError: _showVersionError,
                      ),
                      if (_showVersionError) ...[
                        const SizedBox(height: AionSpacing.sp8),
                        _FieldError(
                          message: context.l10n.releaseDraftVersionInvalidError,
                        ),
                      ],
                    ] else
                      const _NoVersionFileNotice(),
                  ],
                ),
              ),
            ),
          ),
          _Footer(
            confirming: _confirming,
            hasVersionFile: _hasVersionFile,
            onCancel: _confirming ? null : _handleBackPressed,
            onConfirm: _confirming ? null : _handleConfirmTagPressed,
          ),
        ],
      ),
    );
  }
}

/// The screen's header — back button, title, per design.md §3.2.
class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Semantics(
            button: true,
            label: context.l10n.commonBack,
            child: GestureDetector(
              onTap: onBack,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceHover,
                  border: Border.all(color: c.border, width: 1),
                  borderRadius: BorderRadius.all(AionRadius.iconBtn),
                ),
                child: SizedBox(
                  width: 37,
                  height: 37,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.arrowLeftLight,
                      size: 20,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              context.l10n.releaseDraftScreenTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AionText.h2.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A field-level validation error line — leading warning glyph + message,
/// shared shape for the changelog/version fields (design.md §3.4/§3.5).
class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Row(
      children: [
        PhosphorIcon(
          PhosphorIcons.warningCircleLight,
          size: 13,
          color: c.danger,
        ),
        const SizedBox(width: 6),
        Text(message, style: AionText.bodySm.copyWith(color: c.danger)),
      ],
    );
  }
}

/// The "no version file detected" notice — replaces the version field
/// entirely when [ReleaseDraft.detectedVersionFile] is `null`. Per
/// design.md §6.
class _NoVersionFileNotice extends StatelessWidget {
  const _NoVersionFileNotice();

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.noticeFill(t.isDark),
        border: Border.all(color: c.noticeBorder(t.isDark), width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhosphorIcon(PhosphorIcons.infoLight, size: 15, color: c.textMuted),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.releaseDraftNoVersionFileTitle,
                    style: AionText.cardTitle.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.l10n.releaseDraftNoVersionFileMessage,
                    style: AionText.bodySm.copyWith(color: c.textSecondary),
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

/// The push-failure banner — shown when [TicketsCubit.confirmRelease]
/// throws. Stays mounted with the draft above the changelog field, is
/// not a toast/dialog. Per design.md §5. Deliberately shows [message] —
/// the raw propagated exception — verbatim rather than trying to
/// distinguish "committed and tagged locally, only the push failed" from
/// an earlier-stage failure: [TicketsCubit.confirmRelease] propagates a
/// plain exception with no structured step information to tell those
/// apart.
class _PushFailureBanner extends StatelessWidget {
  const _PushFailureBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.dangerTint(t.isDark),
        border: Border.all(color: c.dangerBorderTint(t.isDark), width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: PhosphorIcon(
                PhosphorIcons.warningCircleLight,
                size: 18,
                color: c.danger,
              ),
            ),
            const SizedBox(width: AionSpacing.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.releaseDraftPushFailedTitle,
                    style: AionText.cardTitle.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AionText.bodySm.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: context.l10n.commonDismiss,
              child: GestureDetector(
                onTap: onDismiss,
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.xLight,
                      size: 13,
                      color: c.textMuted,
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

/// The pinned footer actions — Cancel / Confirm & Tag (or Save changelog
/// when there's no detected version file). Per design.md §3.7.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.confirming,
    required this.hasVersionFile,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool confirming;
  final bool hasVersionFile;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final confirmLabel = confirming
        ? context.l10n.releaseDraftTaggingLabel
        : hasVersionFile
        ? context.l10n.releaseDraftConfirmButton
        : context.l10n.releaseDraftSaveChangelogButton;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cancel = AppButton(
              label: context.l10n.releaseDraftCancelButton,
              variant: AppButtonVariant.secondary,
              onPressed: onCancel,
            );
            final confirm = AppButton(
              label: confirmLabel,
              icon: confirming
                  ? null
                  : (hasVersionFile
                        ? PhosphorIcons.tagLight
                        : PhosphorIcons.floppyDiskLight),
              onPressed: onConfirm,
            );
            if (constraints.maxWidth < 420) {
              return Column(
                children: [
                  SizedBox(width: double.infinity, child: confirm),
                  const SizedBox(height: AionSpacing.sp8),
                  SizedBox(width: double.infinity, child: cancel),
                ],
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                cancel,
                const SizedBox(width: AionSpacing.sp12),
                confirm,
              ],
            );
          },
        ),
      ),
    );
  }
}
