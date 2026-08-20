// presentation/screens/trash_screen.dart — Trash screen (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_selection_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/trash_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/trash_state.dart';
import 'package:aion/features/tickets/presentation/widgets/trash_selection_bar.dart';
import 'package:aion/features/tickets/presentation/widgets/trashed_ticket_tile.dart';

/// The `/tickets/trash` route: lists every trashed root ticket
/// (see [TrashLoaded]'s dartdoc for what "root" means here), with a
/// per-row Restore/Permanently-Delete pair and screen-level "Purge old"
/// and "Empty trash" actions. Reached via the ticket list's header
/// Trash-entry icon button.
///
/// Also drives [TicketSelectionCubit]'s selection mode (entered via the
/// header's Select toggle): while active, each row gains a leading
/// checkbox (see [TrashedTicketTile]) and a floating [TrashSelectionBar]
/// offers bulk Restore (no confirmation) and bulk Delete forever
/// (confirmed, stating the aggregate selected-plus-descendant count);
/// the header's "Purge old"/"Empty trash" actions hide for the duration,
/// to avoid an ambiguous "act on my selection vs. act on everything"
/// affordance clash.
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

  /// [TrashSelectionBar]'s `onRestore` handler: restores every ticket in
  /// [ids] via [TrashCubit.restoreTickets] — no confirmation dialog,
  /// matching the existing single-row Restore's frictionless, reversible
  /// precedent regardless of selection size. On success, shows a
  /// summary toast and exits selection mode. A `false` result means
  /// [TrashError] was already emitted and is already visible via the
  /// screen's existing error-state rendering — no toast in that case.
  Future<void> _bulkRestore(BuildContext context, Set<String> ids) async {
    final success = await context.read<TrashCubit>().restoreTickets(
      ids.toList(),
    );
    if (!success || !context.mounted) return;
    AppToast.show(
      context,
      context.l10n.ticketTrashBulkRestoreSummaryToast(ids.length),
    );
    context.read<TicketSelectionCubit>().clear();
  }

  /// [TrashSelectionBar]'s `onDeleteForever` handler: computes the
  /// aggregate ticket count — [ids] plus each selected root's already-
  /// loaded [descendantCounts] entry (no new query), opens
  /// [_confirmPermanentDelete] stating that total, and on confirm calls
  /// [TrashCubit.permanentlyDeleteTickets]. On success, shows a summary
  /// toast and exits selection mode.
  Future<void> _bulkPermanentlyDelete(
    BuildContext context,
    Set<String> ids,
    Map<String, int> descendantCounts,
  ) async {
    final total =
        ids.length +
        ids.fold<int>(0, (sum, id) => sum + (descendantCounts[id] ?? 0));
    await _confirmPermanentDelete(
      context,
      title: context.l10n.ticketTrashPermanentDeleteConfirmTitle,
      message: context.l10n.ticketTrashBulkPermanentDeleteConfirmMessage(total),
      onConfirmed: () async {
        final success = await context
            .read<TrashCubit>()
            .permanentlyDeleteTickets(ids.toList());
        if (!success || !context.mounted) return;
        AppToast.show(
          context,
          context.l10n.ticketTrashBulkPermanentDeleteSummaryToast(total),
        );
        context.read<TicketSelectionCubit>().clear();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final selection = context.watch<TicketSelectionCubit>().state;

    return ColoredBox(
      color: c.background,
      child: Stack(
        children: [
          Column(
            children: [
              BlocBuilder<TrashCubit, TrashState>(
                builder: (context, state) {
                  final count = state is TrashLoaded ? state.tickets.length : 0;
                  final isEmpty = state is TrashLoaded && state.tickets.isEmpty;
                  final purgeEligibleCount = state is TrashLoaded
                      ? state.purgeEligibleCount
                      : 0;
                  final isSelectionActive = context
                      .watch<TicketSelectionCubit>()
                      .state
                      .isActive;

                  final selectToggle = _TrashSelectModeToggle(isEmpty: isEmpty);
                  final purgeAction = _PurgeOldAction(
                    enabled: purgeEligibleCount > 0,
                    onTap: purgeEligibleCount == 0
                        ? null
                        : () => _confirmPermanentDelete(
                            context,
                            title: context.l10n.ticketTrashPurgeOldConfirmTitle,
                            message: context.l10n
                                .ticketTrashPurgeOldConfirmMessage(
                                  purgeEligibleCount,
                                  TrashCubit.purgeAgeThreshold.inDays,
                                ),
                            onConfirmed: () =>
                                context.read<TrashCubit>().purgeOldTrash(),
                          ),
                  );
                  final emptyAction = _EmptyTrashAction(
                    enabled: !isEmpty,
                    onTap: isEmpty
                        ? null
                        : () => _confirmPermanentDelete(
                            context,
                            title: context.l10n.ticketTrashEmptyConfirmTitle,
                            message: context.l10n
                                .ticketTrashEmptyConfirmMessage(count),
                            onConfirmed: () =>
                                context.read<TrashCubit>().emptyTrash(),
                          ),
                  );
                  final titleColumn = Column(
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
                  );

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      // Below this width the back button + title/count block
                      // plus the header's text-labelled ghost buttons no
                      // longer fit on one row — reflow the actions onto
                      // their own row. Widened from the original 380 (sized
                      // for just Purge old/Empty trash) to fit the Select
                      // toggle's own added width when selection mode is off
                      // and all three header actions render together.
                      final isNarrow = constraints.maxWidth <= 560;

                      final backTitleRow = Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _BackButton(
                            onTap: () => context.go('/workspace/tickets'),
                          ),
                          const SizedBox(width: 13),
                          titleColumn,
                          const Spacer(),
                          if (!isNarrow) ...[
                            selectToggle,
                            if (!isSelectionActive) ...[
                              const SizedBox(width: AionSpacing.sp8),
                              purgeAction,
                              const SizedBox(width: AionSpacing.sp8),
                              emptyAction,
                            ],
                          ],
                        ],
                      );

                      if (!isNarrow) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                          child: backTitleRow,
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            backTitleRow,
                            const SizedBox(height: AionSpacing.sp8),
                            // Wrap, not Row+Spacer: three ghost buttons (or
                            // one, while selecting) no longer reliably fit
                            // on one line at every width this branch covers
                            // (down to very narrow desktop windows) — Wrap
                            // flows overflow onto a second line instead of
                            // clipping/overflowing horizontally.
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: AionSpacing.sp8,
                              runSpacing: AionSpacing.sp8,
                              children: [
                                selectToggle,
                                if (!isSelectionActive) ...[
                                  purgeAction,
                                  emptyAction,
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
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
                      border: Border(
                        top: BorderSide(color: c.border, width: 1),
                      ),
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
                          TrashLoaded(
                            :final tickets,
                            :final descendantCounts,
                          ) =>
                            ListView.builder(
                              itemCount: tickets.length,
                              itemBuilder: (context, index) {
                                final ticket = tickets[index];
                                return TrashedTicketTile(
                                  ticket: ticket,
                                  descendantCount:
                                      descendantCounts[ticket.id] ?? 0,
                                  onRestore: () => context
                                      .read<TrashCubit>()
                                      .restore(ticket.id),
                                  onPermanentlyDelete: () => _confirmPermanentDelete(
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
          if (selection.isActive)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: BlocBuilder<TrashCubit, TrashState>(
                builder: (context, state) {
                  final tickets = state is TrashLoaded
                      ? state.tickets
                      : const <Ticket>[];
                  final descendantCounts = state is TrashLoaded
                      ? state.descendantCounts
                      : const <String, int>{};
                  return TrashSelectionBar(
                    selectedCount: selection.selectedIds.length,
                    allSelected:
                        tickets.isNotEmpty &&
                        tickets.every(
                          (t) => selection.selectedIds.contains(t.id),
                        ),
                    onCancel: () =>
                        context.read<TicketSelectionCubit>().clear(),
                    onSelectAll: () => context
                        .read<TicketSelectionCubit>()
                        .selectAll(tickets.map((t) => t.id).toList()),
                    onRestore: () =>
                        _bulkRestore(context, selection.selectedIds),
                    onDeleteForever: () => _bulkPermanentlyDelete(
                      context,
                      selection.selectedIds,
                      descendantCounts,
                    ),
                  );
                },
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

/// [TrashScreen]'s header "Purge old" action — permanently deletes every
/// trashed ticket older than [TrashCubit.purgeAgeThreshold]. Styled like
/// [_EmptyTrashAction] (bordered ghost button, danger-tinted icon +
/// label, disabled via [Opacity]), with a distinct icon so it reads as a
/// separate, age-based bulk action rather than "delete everything".
class _PurgeOldAction extends StatelessWidget {
  /// Creates a [_PurgeOldAction]. Disabled (and non-tappable) when
  /// [enabled] is `false`, i.e. when no trashed ticket currently
  /// qualifies for purge.
  const _PurgeOldAction({required this.enabled, required this.onTap});

  /// Whether at least one trashed ticket is old enough to purge.
  final bool enabled;

  /// Called when the action is tapped. `null` when [enabled] is `false`.
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
        label: context.l10n.ticketTrashPurgeOldAction,
        child: GestureDetector(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: c.border, width: 1),
              borderRadius: BorderRadius.all(AionRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    PhosphorIcons.clockCounterClockwiseLight,
                    size: 14,
                    color: c.danger,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.ticketTrashPurgeOldAction,
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

/// [TrashScreen]'s header Select-mode toggle — enters
/// [TicketSelectionCubit]'s selection mode on tap. Same active/inactive
/// visual pattern as `TicketsListScreen`'s private `_SelectModeToggle`
/// (duplicated, not shared — that widget is private to its own file):
/// tapping while already active is inert, since the toggle isn't the
/// exit path (`TrashSelectionBar`'s Cancel control handles that).
/// Disabled (reduced opacity, non-tappable, excluded from focus) when
/// Trash has nothing to select.
class _TrashSelectModeToggle extends StatefulWidget {
  /// Creates a [_TrashSelectModeToggle]. Disabled when [isEmpty] is
  /// `true` — nothing to select.
  const _TrashSelectModeToggle({required this.isEmpty});

  /// Whether the currently loaded trash list has no tickets.
  final bool isEmpty;

  @override
  State<_TrashSelectModeToggle> createState() => _TrashSelectModeToggleState();
}

class _TrashSelectModeToggleState extends State<_TrashSelectModeToggle> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isActive = context.watch<TicketSelectionCubit>().state.isActive;
    final enabled = !widget.isEmpty;

    void enter() {
      if (enabled && !isActive) context.read<TicketSelectionCubit>().enter();
    }

    final Color fill;
    final Color border;
    final Color content;
    if (!enabled) {
      fill = const Color(0x00000000);
      border = c.border;
      content = c.textMuted;
    } else if (isActive) {
      fill = c.primarySubtle;
      border = c.primary;
      content = c.primary;
    } else if (_isHovered) {
      fill = c.surfaceHover;
      border = c.borderStrong;
      content = c.textPrimary;
    } else {
      fill = const Color(0x00000000);
      border = c.border;
      content = c.textSecondary;
    }

    final boxShadow = _isFocused && enabled
        ? AionShadows.focus(c, t.isDark)
        : const <BoxShadow>[];

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: context.l10n.ticketSelectionToggleLabel,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: enabled ? (_) => setState(() => _isHovered = true) : null,
          onExit: enabled ? (_) => setState(() => _isHovered = false) : null,
          child: FocusableActionDetector(
            enabled: enabled,
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  enter();
                  return null;
                },
              ),
            },
            onShowFocusHighlight: (value) => setState(() => _isFocused = value),
            child: GestureDetector(
              onTap: enabled ? enter : null,
              onTapDown: enabled
                  ? (_) => setState(() => _isPressed = true)
                  : null,
              onTapUp: enabled
                  ? (_) => setState(() => _isPressed = false)
                  : null,
              onTapCancel: enabled
                  ? () => setState(() => _isPressed = false)
                  : null,
              child: AnimatedScale(
                scale: _isPressed ? 0.97 : 1.0,
                duration: const Duration(milliseconds: 80),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: fill,
                    border: Border.all(color: border, width: 1),
                    borderRadius: BorderRadius.all(AionRadius.md),
                    boxShadow: boxShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        PhosphorIcons.checkSquareLight,
                        size: 15,
                        color: content,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        context.l10n.ticketSelectionToggleLabel,
                        style: AionText.button.copyWith(
                          fontSize: 12.5,
                          color: content,
                        ),
                      ),
                    ],
                  ),
                ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
