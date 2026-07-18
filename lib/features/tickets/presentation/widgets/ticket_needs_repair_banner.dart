// presentation/widgets/ticket_needs_repair_banner.dart — TicketNeedsRepairBanner (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_repair_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_repair_state.dart';

/// Inline recovery banner shown at the top of `TicketDetailScreen`'s body
/// only while a `resource`/`page` ticket's `syncStatus` is `needsRepair`.
/// Not user-dismissible — it clears itself (via [onRepaired]) once the
/// underlying state resolves. Per design.md §3, both recovery actions
/// are presented as equally-weighted, non-destructive-feeling choices —
/// deliberately not `AppButton` primary/secondary, so neither out-ranks
/// the other.
///
/// Must be built under a [TicketRepairCubit] (`BlocProvider`) — this
/// widget only renders the UI and reacts to that cubit's state; it
/// doesn't construct one itself, since the cubit is scoped to a single
/// ticket/rootPath pair the parent screen already knows.
class TicketNeedsRepairBanner extends StatefulWidget {
  /// Creates a [TicketNeedsRepairBanner]. [isPage] selects the
  /// "page's"/"resource's" wording in the title. [onRepaired] fires
  /// after the success-confirmation hold + collapse animation finishes,
  /// so the parent screen can re-fetch the ticket and let the banner's
  /// conditional rendering (based on the now-`synced` status) remove it.
  const TicketNeedsRepairBanner({
    super.key,
    required this.isPage,
    required this.onRepaired,
  });

  /// Whether the ticket is a `page` (vs. `resource`) — selects wording.
  final bool isPage;

  /// Called once the success-confirmation sequence finishes.
  final VoidCallback onRepaired;

  @override
  State<TicketNeedsRepairBanner> createState() =>
      _TicketNeedsRepairBannerState();
}

class _TicketNeedsRepairBannerState extends State<TicketNeedsRepairBanner> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocConsumer<TicketRepairCubit, TicketRepairState>(
      listener: (context, state) {
        if (state is TicketRepairFailed) {
          AppToast.show(context, state.message);
        }
        if (state is TicketRepairCompleted) {
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (!mounted) return;
            setState(() => _collapsed = true);
          });
          Future.delayed(const Duration(milliseconds: 1420), () {
            if (!mounted) return;
            widget.onRepaired();
          });
        }
      },
      builder: (context, state) {
        final isSuccess = state is TicketRepairCompleted;
        final isInProgress = state is TicketRepairInProgress;
        final fill = isSuccess
            ? c.repairedTint(t.isDark)
            : c.needsRepairTint(t.isDark);
        final border = isSuccess
            ? c.repairedBorderTint(t.isDark)
            : c.needsRepairBorderTint(t.isDark);

        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInCubic,
          child: _collapsed
              ? const SizedBox.shrink()
              : AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _collapsed ? 0 : 1,
                  child: Container(
                    // Horizontal gutter is deliberately 0 here, not
                    // design.md's AionSpacing.sp20 — TicketDetailScreen
                    // already wraps its body content in a
                    // Padding(EdgeInsets.fromLTRB(20, 16, 20, 16)), so
                    // this banner sits inside that padded column rather
                    // than spanning it independently. Matching
                    // design.md's margin here would double the inset.
                    margin: const EdgeInsets.fromLTRB(0, 2, 0, 4),
                    padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
                    decoration: BoxDecoration(
                      color: fill,
                      border: Border.all(color: border),
                      borderRadius: const BorderRadius.all(AionRadius.lg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MessageRow(isSuccess: isSuccess, isPage: widget.isPage),
                        if (!isSuccess) ...[
                          const SizedBox(height: 13),
                          _ActionsRow(isInProgress: isInProgress, state: state),
                        ],
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.isSuccess, required this.isPage});

  final bool isSuccess;
  final bool isPage;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final noun = isPage ? "page's" : "resource's";

    if (isSuccess) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _IconChip(isSuccess: true),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'File repaired — back in sync',
                  style: AionText.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  'The banner clears on its own in a moment.',
                  style: AionText.bodySm.copyWith(
                    height: 1.5,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: _IconChip(isSuccess: false),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "This $noun file couldn't be read",
                style: AionText.bodySm.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: c.textPrimary,
                ),
              ),
              Text(
                "An external edit left the Markdown unparseable. Aion's "
                'own copy is safe — pick how to recover.',
                style: AionText.bodySm.copyWith(
                  height: 1.5,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.isSuccess});

  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSuccess
            ? c.repairedIconTint(t.isDark)
            : c.needsRepairIconTint(t.isDark),
        borderRadius: const BorderRadius.all(AionRadius.iconBtnSm),
      ),
      child: SizedBox(
        width: 26,
        height: 26,
        child: Center(
          child: PhosphorIcon(
            isSuccess ? PhosphorIcons.checkLight : PhosphorIcons.warningLight,
            size: isSuccess ? 14 : 13,
            color: isSuccess ? c.success : c.warning,
          ),
        ),
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.isInProgress, required this.state});

  final bool isInProgress;
  final TicketRepairState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TicketRepairCubit>();
    return Row(
      children: [
        Expanded(
          child: _RepairActionButton(
            label: 'Reformat',
            inProgressLabel: 'Reformatting',
            enabled: !isInProgress,
            onTap: cubit.reformat,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RepairActionButton(
            label: 'Restore last good',
            inProgressLabel: 'Restoring',
            enabled: !isInProgress,
            onTap: cubit.restoreFromLastKnownGood,
          ),
        ),
      ],
    );
  }
}

/// A peer-weighted recovery action, deliberately not `AppButton`
/// primary/secondary — both actions are equally valid, non-destructive
/// choices, so neither should read as more prominent than the other.
class _RepairActionButton extends StatefulWidget {
  const _RepairActionButton({
    required this.label,
    required this.inProgressLabel,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String inProgressLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_RepairActionButton> createState() => _RepairActionButtonState();
}

class _RepairActionButtonState extends State<_RepairActionButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _tappedThis = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final showInProgress = _tappedThis && !widget.enabled;

    final fill = _pressed ? c.border : (_hovered ? c.surfaceHover : c.surface);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.enabled
            ? () {
                setState(() {
                  _pressed = false;
                  _tappedThis = true;
                });
                widget.onTap();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.enabled || showInProgress
                  ? fill
                  : c.surface.withValues(alpha: 0.45),
              border: Border.all(color: c.borderStrong),
              borderRadius: const BorderRadius.all(AionRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: showInProgress
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppSpinner(size: 12),
                        const SizedBox(width: 7),
                        Text(
                          widget.inProgressLabel,
                          style: AionText.button.copyWith(
                            fontSize: 13.5,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: AionText.button.copyWith(
                        fontSize: 13.5,
                        color: c.textPrimary,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
