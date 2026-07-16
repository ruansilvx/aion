// presentation/screens/trash_screen.dart — Trash screen (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/core/design_system.dart';
import 'package:aion/features/tickets/presentation/cubit/trash_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/trash_state.dart';
import 'package:aion/features/tickets/presentation/widgets/trashed_ticket_tile.dart';

/// The `/tickets/trash` route: lists every trashed root ticket
/// (see [TrashLoaded]'s dartdoc for what "root" means here), with a
/// per-row Restore/Permanently-Delete pair and a screen-level "Empty
/// trash" action. Reached via the ticket list's header Trash-entry icon
/// button.
class TrashScreen extends StatelessWidget {
  /// Creates a [TrashScreen].
  const TrashScreen({super.key});

  Future<void> _confirmPermanentDelete(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirmed,
  }) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: context.l10n.ticketTrashPermanentDeleteAction,
      tone: ConfirmDialogTone.destructive,
    );
    if (confirmed) onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.background,
      child: Column(
        children: [
          BlocBuilder<TrashCubit, TrashState>(
            builder: (context, state) {
              final count = state is TrashLoaded ? state.tickets.length : 0;
              final isEmpty = state is TrashLoaded && state.tickets.isEmpty;

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _BackButton(onTap: () => context.go('/tickets')),
                    const SizedBox(width: 13),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.ticketTrashScreenTitle,
                          style: AionText.h2.copyWith(color: c.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.ticketTrashItemCount(count),
                          style: AionText.time.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _EmptyTrashAction(
                      enabled: !isEmpty,
                      onTap: isEmpty
                          ? null
                          : () => _confirmPermanentDelete(
                              context,
                              title: context.l10n.ticketTrashEmptyConfirmTitle,
                              message: context.l10n.ticketTrashEmptyConfirmMessage(
                                count,
                              ),
                              onConfirmed: () =>
                                  context.read<TrashCubit>().emptyTrash(),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
          BlocBuilder<TrashCubit, TrashState>(
            builder: (context, state) {
              if (state is TrashLoaded && state.tickets.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.primary.withValues(
                        alpha: t.isDark ? 0.10 : 0.06,
                      ),
                      border: Border.all(
                        color: c.primary.withValues(
                          alpha: t.isDark ? 0.30 : 0.20,
                        ),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.all(AionRadius.lg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PhosphorIcon(
                            PhosphorIcons.infoLight,
                            size: 14,
                            color: c.textSecondary,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              context.l10n.ticketTrashInfoBanner,
                              style: AionText.bodySm.copyWith(
                                color: c.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: ColoredBox(
              color: c.surface,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border, width: 1)),
                ),
                child: BlocBuilder<TrashCubit, TrashState>(
                  builder: (context, state) {
                    return switch (state) {
                      TrashLoading() => const Center(child: AppSpinner()),
                      TrashError(:final message) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message,
                              style: AionText.body.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AionSpacing.sp12),
                            AppButton(
                              label: context.l10n.commonRetry,
                              onPressed: () =>
                                  context.read<TrashCubit>().load(),
                            ),
                          ],
                        ),
                      ),
                      TrashLoaded(:final tickets) when tickets.isEmpty =>
                        _EmptyTrashState(colors: c),
                      TrashLoaded(:final tickets, :final descendantCounts) =>
                        ListView.builder(
                          itemCount: tickets.length,
                          itemBuilder: (context, index) {
                            final ticket = tickets[index];
                            return TrashedTicketTile(
                              ticket: ticket,
                              descendantCount:
                                  descendantCounts[ticket.id] ?? 0,
                              onRestore: () =>
                                  context.read<TrashCubit>().restore(
                                    ticket.id,
                                  ),
                              onPermanentlyDelete: () =>
                                  _confirmPermanentDelete(
                                    context,
                                    title: context
                                        .l10n
                                        .ticketTrashPermanentDeleteConfirmTitle,
                                    message: context.l10n
                                        .ticketTrashPermanentDeleteConfirmMessage(
                                          ticket.title,
                                        ),
                                    onConfirmed: () => context
                                        .read<TrashCubit>()
                                        .permanentlyDelete(ticket.id),
                                  ),
                            );
                          },
                        ),
                    };
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [TrashScreen]'s empty-trash body: a filled motif, a primary line, and
/// a secondary hint.
class _EmptyTrashState extends StatelessWidget {
  const _EmptyTrashState({required this.colors});

  final AionColors colors;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final fillAlpha = t.isDark ? fillAlphaObsidian : fillAlphaArctic;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: fillAlpha),
                borderRadius: BorderRadius.all(AionRadius.xl),
              ),
              child: SizedBox(
                width: 58,
                height: 58,
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIcons.trashFill,
                    size: 27,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AionSpacing.sp16),
            Text(
              context.l10n.ticketTrashEmptyState,
              textAlign: TextAlign.center,
              style: AionText.body.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.ticketTrashEmptyStateHint,
              textAlign: TextAlign.center,
              style: AionText.bodySm.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// [TrashScreen]'s header back button — pops to `/tickets`.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Semantics(
      button: true,
      label: context.l10n.commonBack,
      child: GestureDetector(
        onTap: onTap,
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
                PhosphorIcons.caretLeftLight,
                size: 20,
                color: c.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [TrashScreen]'s header "Empty trash" action.
class _EmptyTrashAction extends StatelessWidget {
  const _EmptyTrashAction({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: context.l10n.ticketTrashEmptyAction,
        child: GestureDetector(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: c.border, width: 1),
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    PhosphorIcons.trashLight,
                    size: 13,
                    color: c.danger,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.ticketTrashEmptyAction,
                    style: AionText.label.copyWith(
                      color: c.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
