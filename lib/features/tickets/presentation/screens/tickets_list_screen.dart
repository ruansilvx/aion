// presentation/screens/tickets_list_screen.dart — Ticket list screen and row widgets (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

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
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';

/// The `/tickets` route: eyebrow + title header, search bar, the ticket
/// list body driven by [TicketsCubit], and an [AppFab] to create a new
/// ticket. Loads the list in [State.initState].
class TicketsListScreen extends StatefulWidget {
  /// Creates a [TicketsListScreen].
  const TicketsListScreen({super.key});

  @override
  State<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends State<TicketsListScreen> {
  @override
  void initState() {
    super.initState();
    context.read<TicketsCubit>().loadTickets();
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
                    Text('AION · MAIN', style: AionText.caption.copyWith(color: c.textMuted)),
                    const SizedBox(height: AionSpacing.sp4),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Tickets', style: AionText.h1.copyWith(color: c.textPrimary)),
                        ),
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
                        Text('Search tickets', style: AionText.bodySm.copyWith(color: c.textMuted)),
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
                          TicketsError(:final message) => Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(message, style: AionText.body.copyWith(color: c.textSecondary)),
                                  const SizedBox(height: AionSpacing.sp12),
                                  AppButton(
                                    label: 'Retry',
                                    onPressed: () => context.read<TicketsCubit>().loadTickets(),
                                  ),
                                ],
                              ),
                            ),
                          TicketsLoaded(:final tickets) when tickets.isEmpty => Center(
                              child: Text(
                                'No tickets yet',
                                style: AionText.body.copyWith(color: c.textMuted),
                              ),
                            ),
                          TicketsLoaded(:final tickets) => ListView.separated(
                              itemCount: tickets.length,
                              separatorBuilder: (context, index) =>
                                  Container(color: c.border, height: 1),
                              itemBuilder: (context, index) => TicketListTile(ticket: tickets[index]),
                            ),
                          TicketCreating(:final tickets) || TicketCreated(:final tickets) =>
                            ListView.separated(
                              itemCount: tickets.length,
                              separatorBuilder: (context, index) =>
                                  Container(color: c.border, height: 1),
                              itemBuilder: (context, index) => TicketListTile(ticket: tickets[index]),
                            ),
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
      label: 'Create ticket',
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
                  'New ticket',
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
          priority.name.toUpperCase(),
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
              type.name.toUpperCase(),
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
          _statusLabel(status),
          style: AionText.label.copyWith(
            color: c.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  String _statusLabel(TicketStatus status) {
    return switch (status) {
      TicketStatus.backlog => 'Backlog',
      TicketStatus.todo => 'To do',
      TicketStatus.inProgress => 'In progress',
      TicketStatus.inReview => 'In review',
      TicketStatus.done => 'Done',
      TicketStatus.cancelled => 'Cancelled',
    };
  }
}
