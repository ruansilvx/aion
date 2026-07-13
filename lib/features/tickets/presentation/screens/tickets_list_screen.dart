// presentation/screens/tickets_list_screen.dart — Ticket list screen and row widgets (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/core/localization/context_localizations_x.dart';
import 'package:aion/core/theme/aion_radius.dart';
import 'package:aion/core/theme/aion_shadows.dart';
import 'package:aion/core/theme/aion_text.dart';
import 'package:aion/core/theme/theme_scope.dart';
import 'package:aion/core/widgets/app_button.dart';
import 'package:aion/core/widgets/app_spinner.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart';

/// The `/tickets` route: eyebrow + title header, search bar, the ticket
/// list body driven by [TicketsCubit], and an [AppFab] to create a new
/// ticket. Loads the list in [State.initState].
class TicketsListScreen extends StatefulWidget {
  /// Creates a [TicketsListScreen].
  const TicketsListScreen({super.key});

  @override
  State<TicketsListScreen> createState() => _TicketsListScreenState();
}

/// Which rendering [_TicketsListScreenState] uses for the loaded ticket
/// list. Local, non-persisted UI state — the screen always opens in
/// [list].
enum _TicketViewMode {
  /// The flat, chronologically-sorted [ListView] of every ticket.
  list,

  /// [TicketBoardView], grouped by status and filtered to task/story
  /// tickets.
  board,
}

class _TicketsListScreenState extends State<TicketsListScreen> {
  _TicketViewMode _viewMode = _TicketViewMode.list;

  @override
  void initState() {
    super.initState();
    context.read<TicketsCubit>().loadTickets();
  }

  /// Renders the loaded [tickets] as either the flat list or the board,
  /// depending on [_viewMode]. An empty (unfiltered) [tickets] list always
  /// shows the "No tickets yet" message regardless of view mode.
  Widget _buildTicketsBody(BuildContext context, List<Ticket> tickets) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    if (tickets.isEmpty) {
      return Center(
        child: Text(
          context.l10n.ticketsListEmptyState,
          style: AionText.body.copyWith(color: c.textMuted),
        ),
      );
    }

    if (_viewMode == _TicketViewMode.board) {
      final boardTickets = tickets
          .where((ticket) => ticket.type == TicketType.task || ticket.type == TicketType.story)
          .toList();
      return TicketBoardView(tickets: boardTickets);
    }

    return ListView.separated(
      itemCount: tickets.length,
      separatorBuilder: (context, index) => Container(color: c.border, height: 1),
      itemBuilder: (context, index) => TicketListTile(ticket: tickets[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return ColoredBox(
      color: c.background,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.ticketsListEyebrow,
                      style: AionText.caption.copyWith(color: c.textMuted),
                    ),
                    const SizedBox(height: AionSpacing.sp4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.ticketsListTitle,
                            style: AionText.h1.copyWith(color: c.textPrimary),
                          ),
                        ),
                        _ViewModeToggle(
                          mode: _viewMode,
                          onChanged: (mode) => setState(() => _viewMode = mode),
                        ),
                        const SizedBox(width: AionSpacing.sp12),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.surfaceHover,
                            border: Border.all(color: c.border, width: 1),
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(
                            width: 38,
                            height: 38,
                            child: Center(
                              child: Text('U', style: AionText.key.copyWith(color: c.textSecondary)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AionSpacing.sp12),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.border, width: 1),
                    borderRadius: BorderRadius.all(AionRadius.lg),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    child: Row(
                      children: [
                        PhosphorIcon(
                          PhosphorIcons.magnifyingGlassLight,
                          size: 16,
                          color: c.textMuted,
                        ),
                        const SizedBox(width: AionSpacing.sp8),
                        Text(
                          context.l10n.ticketsListSearchHint,
                          style: AionText.bodySm.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AionSpacing.sp4),
              Expanded(
                child: ColoredBox(
                  color: c.surface,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.border, width: 1)),
                    ),
                    child: BlocBuilder<TicketsCubit, TicketsState>(
                      builder: (context, state) {
                        return switch (state) {
                          TicketsLoading() => const Center(child: AppSpinner()),
                          TicketsError(:final message, :final reason) => Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    reason != null
                                        ? ticketsErrorMessage(context, reason)
                                        : message,
                                    style: AionText.body.copyWith(color: c.textSecondary),
                                  ),
                                  const SizedBox(height: AionSpacing.sp12),
                                  AppButton(
                                    label: context.l10n.commonRetry,
                                    onPressed: () => context.read<TicketsCubit>().loadTickets(),
                                  ),
                                ],
                              ),
                            ),
                          TicketsLoaded(:final tickets) ||
                          TicketCreating(:final tickets) ||
                          TicketCreated(:final tickets) ||
                          TicketStatusUpdating(:final tickets) ||
                          TicketStatusUpdated(:final tickets) =>
                            _buildTicketsBody(context, tickets),
                          _ => const SizedBox.shrink(),
                        };
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: 18,
            bottom: 24,
            child: AppFab(onTap: () => context.go('/tickets/new')),
          ),
        ],
      ),
    );
  }
}

/// The extended-pill floating action button used to start ticket creation.
class AppFab extends StatelessWidget {
  /// Creates an [AppFab] that calls [onTap] when pressed.
  const AppFab({super.key, required this.onTap});

  /// Called when the FAB is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Semantics(
      button: true,
      label: context.l10n.commonCreateTicket,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.primary,
            borderRadius: BorderRadius.all(AionRadius.xl),
            boxShadow: AionShadows.fab(c, t.isDark),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '+',
                  style: TextStyle(
                    fontSize: 18,
                    color: Color(0xFFFFFFFF), // white on primary
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AionSpacing.sp8),
                Text(
                  context.l10n.commonNewTicket,
                  style: AionText.button.copyWith(color: const Color(0xFFFFFFFF)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The list/board view switcher in [TicketsListScreen]'s header: two icon
/// buttons, the active one tinted [AionColors.primary]/`primarySubtle`.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode, required this.onChanged});

  /// The currently active view mode.
  final _TicketViewMode mode;

  /// Called with the newly selected mode when the user taps an icon.
  final ValueChanged<_TicketViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewModeIcon(
          icon: PhosphorIcons.listLight,
          label: context.l10n.ticketsListSwitchToListView,
          isActive: mode == _TicketViewMode.list,
          onTap: () => onChanged(_TicketViewMode.list),
        ),
        const SizedBox(width: AionSpacing.sp4),
        _ViewModeIcon(
          icon: PhosphorIcons.hexagonLight,
          label: context.l10n.ticketsListSwitchToBoardView,
          isActive: mode == _TicketViewMode.board,
          onTap: () => onChanged(_TicketViewMode.board),
        ),
      ],
    );
  }
}

/// A single icon button used by [_ViewModeToggle].
class _ViewModeIcon extends StatelessWidget {
  const _ViewModeIcon({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Semantics(
      button: true,
      label: label,
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isActive ? c.primarySubtle : null,
              borderRadius: BorderRadius.all(AionRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: PhosphorIcon(icon, size: 18, color: isActive ? c.primary : c.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single row in [TicketsListScreen]'s list: ID badge, title, priority
/// badge, type chip, and status indicator. Navigates to the ticket's detail
/// screen when tapped or activated via keyboard.
class TicketListTile extends StatelessWidget {
  /// Creates a [TicketListTile] rendering [ticket].
  const TicketListTile({super.key, required this.ticket});

  /// The ticket this row represents.
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Semantics(
      label: '${ticket.ticketId} ${ticket.title}',
      button: true,
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              context.go('/tickets/${ticket.id}');
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: () => context.go('/tickets/${ticket.id}'),
          child: ColoredBox(
            color: c.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surfaceHover,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            ticket.ticketId,
                            style: AionText.key.copyWith(color: c.textSecondary, fontSize: 10.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: AionSpacing.sp12),
                      Expanded(
                        child: Text(
                          ticket.title,
                          style: AionText.cardTitle.copyWith(color: c.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ticket.priority != TicketPriority.none) ...[
                        const SizedBox(width: AionSpacing.sp12),
                        PriorityBadge(priority: ticket.priority),
                      ],
                    ],
                  ),
                  const SizedBox(height: AionSpacing.sp8),
                  Row(
                    children: [
                      TypeChip(type: ticket.type),
                      const SizedBox(width: AionSpacing.sp12),
                      StatusIndicator(status: ticket.status),
                      LinkCountLabel(ticketId: ticket.id),
                    ],
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

/// A small badge showing a ticket's priority. Renders nothing when
/// [priority] is [TicketPriority.none] — priority is hidden, not shown as
/// an empty slot.
class PriorityBadge extends StatelessWidget {
  /// Creates a [PriorityBadge] for [priority].
  const PriorityBadge({super.key, required this.priority, this.isRow = true});

  /// The priority to render.
  final TicketPriority priority;

  /// Whether to use the compact ticket-row sizing (`true`, default) or the
  /// larger ticket-detail sizing (`false`).
  final bool isRow;

  @override
  Widget build(BuildContext context) {
    if (priority == TicketPriority.none) return const SizedBox.shrink();

    final t = ThemeScope.of(context);
    final c = t.colors.priority;
    final (bg, fg) = switch (priority) {
      TicketPriority.critical => (c.criticalBg, c.criticalFg),
      TicketPriority.high => (c.highBg, c.highFg),
      TicketPriority.medium => (c.mediumBg, c.mediumFg),
      TicketPriority.low => (c.lowBg, c.lowFg),
      TicketPriority.none => (c.lowBg, c.lowFg),
    };

    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Padding(
        padding: isRow
            ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
            : const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        child: Text(
          ticketPriorityLabel(context, priority).toUpperCase(),
          style: (isRow ? AionText.prioritySm : AionText.priorityBig).copyWith(color: fg),
        ),
      ),
    );
  }
}

/// A small chip showing a ticket's type as a colored square + uppercase
/// label. Color is derived from [type] via [AionColors.typeTask]/
/// [AionColors.typeStory]/[AionColors.typeEpic].
class TypeChip extends StatelessWidget {
  /// Creates a [TypeChip] for [type].
  const TypeChip({super.key, required this.type, this.isRow = true});

  /// The ticket type to render.
  final TicketType type;

  /// Whether to use the compact ticket-row sizing (`true`, default) or the
  /// larger ticket-detail sizing (`false`).
  final bool isRow;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final typeColor = switch (type) {
      TicketType.story => c.typeStory,
      TicketType.epic => c.typeEpic,
      _ => c.typeTask,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: t.fillAlpha),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: isRow
            ? const EdgeInsets.fromLTRB(5, 2, 7, 2)
            : const EdgeInsets.fromLTRB(6, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: typeColor, borderRadius: BorderRadius.circular(2)),
              child: SizedBox(width: isRow ? 9 : 11, height: isRow ? 9 : 11),
            ),
            const SizedBox(width: 5),
            Text(
              ticketTypeLabel(context, type).toUpperCase(),
              style: AionText.chip.copyWith(color: typeColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dot + label showing a ticket's workflow status.
class StatusIndicator extends StatelessWidget {
  /// Creates a [StatusIndicator] for [status].
  const StatusIndicator({super.key, required this.status});

  /// The status to render.
  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final dotColor = switch (status) {
      TicketStatus.backlog => c.textMuted,
      TicketStatus.inProgress => c.primary,
      TicketStatus.done => c.success,
      _ => c.textMuted,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          child: const SizedBox(width: 7, height: 7),
        ),
        const SizedBox(width: 7),
        Text(
          ticketStatusLabel(context, status),
          style: AionText.label.copyWith(
            color: c.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// A meta-row indicator showing how many other tickets [ticketId] is linked
/// to (via `ticket_links`, [TicketLinkRepository.getLinksForTicket]).
/// Renders nothing while the count is loading or is zero.
class LinkCountLabel extends StatelessWidget {
  /// Creates a [LinkCountLabel] for the ticket with internal id [ticketId].
  const LinkCountLabel({super.key, required this.ticketId});

  /// Internal UUID of the ticket to count links for.
  final String ticketId;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return FutureBuilder<List<TicketLinkData>>(
      future: context.read<TicketLinkRepository>().getLinksForTicket(ticketId),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(left: AionSpacing.sp12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(PhosphorIcons.linkLight, size: 11, color: c.textMuted),
              const SizedBox(width: 3),
              Text(
                '$count',
                style: AionText.label.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
