// presentation/screens/tickets_board_view.dart — Kanban board view widgets (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_selection_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_overflow_menu.dart';

/// Fixed width of a single [BoardColumn].
const double _kColumnWidth = 280.0;

/// Returns the display label for [status] (e.g. `"In progress"`). Shared by
/// [StatusIndicator] (`tickets_list_screen.dart`) and [BoardColumn]'s
/// header so the 6-case status→label mapping lives in exactly one place.
String ticketStatusLabel(BuildContext context, TicketStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    TicketStatus.backlog => l10n.ticketStatusBacklog,
    TicketStatus.todo => l10n.ticketStatusToDo,
    TicketStatus.inProgress => l10n.ticketStatusInProgress,
    TicketStatus.inReview => l10n.ticketStatusInReview,
    TicketStatus.done => l10n.ticketStatusDone,
    TicketStatus.cancelled => l10n.ticketStatusCancelled,
  };
}

/// Returns the display label for [priority] (e.g. `"Critical"`). Same
/// one-place-mapping rationale as [ticketStatusLabel]; callers that need
/// the all-caps badge treatment apply `.toUpperCase()` themselves.
String ticketPriorityLabel(BuildContext context, TicketPriority priority) {
  final l10n = context.l10n;
  return switch (priority) {
    TicketPriority.critical => l10n.ticketPriorityCritical,
    TicketPriority.high => l10n.ticketPriorityHigh,
    TicketPriority.medium => l10n.ticketPriorityMedium,
    TicketPriority.low => l10n.ticketPriorityLow,
    TicketPriority.none => l10n.ticketPriorityNone,
  };
}

/// Returns the display label for [type] (e.g. `"Story"`). Same
/// one-place-mapping rationale as [ticketStatusLabel].
String ticketTypeLabel(BuildContext context, TicketType type) {
  final l10n = context.l10n;
  return switch (type) {
    TicketType.epic => l10n.ticketTypeEpic,
    TicketType.story => l10n.ticketTypeStory,
    TicketType.task => l10n.ticketTypeTask,
    TicketType.resource => l10n.ticketTypeResource,
    TicketType.page => l10n.ticketTypePage,
    TicketType.chat => l10n.ticketTypeChat,
  };
}

/// Returns the localized display message for a classified [reason]. See
/// [TicketsErrorReason].
String ticketsErrorMessage(BuildContext context, TicketsErrorReason reason) {
  final l10n = context.l10n;
  return switch (reason) {
    TicketsErrorReason.notFound => l10n.ticketsErrorNotFound,
    TicketsErrorReason.invalidParent => l10n.ticketInvalidParentError,
  };
}

/// The `/tickets` board view: tickets grouped into one column per
/// [TicketStatus], in declaration order — all 6 columns always render,
/// including when a status has no tickets. [tickets] must already be
/// filtered by the caller (e.g. to task/story types); this widget only
/// groups by status, it does not filter by type.
class TicketBoardView extends StatelessWidget {
  /// Creates a [TicketBoardView] rendering [tickets] grouped by status.
  const TicketBoardView({super.key, required this.tickets});

  /// The tickets to render, already filtered to the desired ticket types.
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    final grouped = <TicketStatus, List<Ticket>>{
      for (final status in TicketStatus.values)
        status: tickets.where((t) => t.status == status).toList(),
    };

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AionSpacing.sp20,
        vertical: AionSpacing.sp16,
      ),
      itemCount: TicketStatus.values.length,
      separatorBuilder: (context, index) =>
          const SizedBox(width: AionSpacing.sp12),
      itemBuilder: (context, index) {
        final status = TicketStatus.values[index];
        return SizedBox(
          width: _kColumnWidth,
          child: BoardColumn(status: status, tickets: grouped[status]!),
        );
      },
    );
  }
}

/// A single status column on [TicketBoardView]: a header (status label +
/// ticket count) and a [DragTarget] accepting dropped [Ticket]s, moving
/// them to [status] via [TicketsCubit.updateTicketStatus].
class BoardColumn extends StatelessWidget {
  /// Creates a [BoardColumn] for [status], rendering [tickets].
  const BoardColumn({super.key, required this.status, required this.tickets});

  /// The status this column represents.
  final TicketStatus status;

  /// The tickets currently in [status].
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AionSpacing.sp4,
            vertical: AionSpacing.sp8,
          ),
          child: Row(
            children: [
              Text(
                ticketStatusLabel(context, status).toUpperCase(),
                style: AionText.caption.copyWith(color: c.textMuted),
              ),
              const SizedBox(width: AionSpacing.sp8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceHover,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  child: Text(
                    '${tickets.length}',
                    style: AionText.key.copyWith(
                      color: c.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AionSpacing.sp4),
        Expanded(
          child: DragTarget<Ticket>(
            onWillAcceptWithDetails: (details) => true,
            onAcceptWithDetails: (details) {
              if (details.data.status != status) {
                context.read<TicketsCubit>().updateTicketStatus(
                  details.data.id,
                  status,
                );
              }
            },
            builder: (context, candidateData, rejectedData) {
              final isHovering = candidateData.isNotEmpty;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: isHovering ? c.primarySubtle : null,
                  borderRadius: BorderRadius.all(AionRadius.lg),
                ),
                child: SizedBox.expand(
                  child: tickets.isEmpty
                      ? Center(
                          child: Text(
                            context.l10n.ticketsBoardEmptyColumn,
                            style: AionText.bodySm.copyWith(color: c.textMuted),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            vertical: AionSpacing.sp4,
                          ),
                          itemCount: tickets.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: AionSpacing.sp8),
                          itemBuilder: (context, index) =>
                              TicketBoardCard(ticket: tickets[index]),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A single draggable ticket card on [TicketBoardView]. Wrapped in
/// [Draggable] on desktop/web or [LongPressDraggable] on mobile — mobile
/// needs the long-press gate so an ordinary vertical swipe still scrolls
/// the column instead of picking up the card — via [isMobile]
/// (`core/utils/platform_utils.dart`). Both carry [ticket] as drag data;
/// dropping on a [BoardColumn] calls [TicketsCubit.updateTicketStatus],
/// the same method [MoveToStatusMenu] calls, so drag and its
/// keyboard/screen-reader fallback are provably equivalent rather than
/// parallel logic that can drift.
///
/// Tapping (not dragging) the card navigates to the ticket's detail
/// screen, same as `TicketListTile`. Distinguishing a tap from a drag is
/// resolved by Flutter's gesture arena — verify this interactively via
/// `flutter run` (see `tasks.md` T15); `flutter analyze`/`flutter test`
/// cannot catch a gesture-arena regression here.
///
/// While `TicketsListScreen`'s selection mode ([TicketSelectionCubit]) is
/// active, dragging is disabled outright — the card renders as a plain,
/// non-draggable tap target that toggles selection instead of navigating.
class TicketBoardCard extends StatelessWidget {
  /// Creates a [TicketBoardCard] rendering [ticket].
  const TicketBoardCard({super.key, required this.ticket});

  /// The ticket this card represents.
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final isSelectionActive = context.select(
      (TicketSelectionCubit cubit) => cubit.state.isActive,
    );
    final isSelected = context.select(
      (TicketSelectionCubit cubit) =>
          cubit.state.selectedIds.contains(ticket.id),
    );

    void handleTap() {
      if (isSelectionActive) {
        context.read<TicketSelectionCubit>().toggle(ticket.id);
      } else {
        context.go(ticketDetailRoute(ticket));
      }
    }

    final card = Semantics(
      label:
          '${ticket.ticketId} ${ticket.title}, status: ${ticketStatusLabel(context, ticket.status)}',
      button: true,
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              handleTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: handleTap,
          child: _CardVisual(
            ticket: ticket,
            elevated: false,
            isSelectionActive: isSelectionActive,
            isSelected: isSelected,
          ),
        ),
      ),
    );

    // Dragging is disabled outright while selection mode is active — it
    // shares mobile's long-press gesture with entering a drag, and the
    // two must not compete.
    if (isSelectionActive) {
      return card;
    }

    final feedback = SizedBox(
      width: _kColumnWidth - AionSpacing.sp16,
      child: Opacity(
        opacity: 0.9,
        child: _CardVisual(ticket: ticket, elevated: true, interactive: false),
      ),
    );
    final placeholder = Opacity(
      opacity: 0.35,
      child: _CardVisual(ticket: ticket, elevated: false, interactive: false),
    );

    return isMobile
        ? LongPressDraggable<Ticket>(
            data: ticket,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: card,
          )
        : Draggable<Ticket>(
            data: ticket,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: card,
          );
  }
}

/// The visual card body shared by [TicketBoardCard]'s in-place, drag
/// feedback, and drag-placeholder renderings.
class _CardVisual extends StatelessWidget {
  const _CardVisual({
    required this.ticket,
    required this.elevated,
    this.interactive = true,
    this.isSelectionActive = false,
    this.isSelected = false,
  });

  /// The ticket to render.
  final Ticket ticket;

  /// Whether to use the stronger "lifted" shadow (drag feedback) instead
  /// of the resting card shadow.
  final bool elevated;

  /// Whether to render [TicketOverflowMenu] and [MoveToStatusMenu] —
  /// omitted for the drag feedback and placeholder renderings, which
  /// aren't meant to be interactive.
  final bool interactive;

  /// Whether `TicketsListScreen`'s selection mode is active. When `true`,
  /// a leading [AppCheckbox] replaces [TicketOverflowMenu]/
  /// [MoveToStatusMenu] in the header row. Always `false` for the drag
  /// feedback/placeholder renderings (never shown while selecting, since
  /// [TicketBoardCard] disables dragging outright in that mode).
  final bool isSelectionActive;

  /// Whether [ticket] is currently selected — drives the selected-card
  /// fill/border treatment.
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected ? c.primarySubtle : c.surface,
        borderRadius: BorderRadius.all(AionRadius.lg),
        border: Border.all(
          color: isSelected ? c.primary : c.border,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: elevated
            ? AionShadows.fab(c, t.isDark)
            : AionShadows.card(c, t.isDark),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AionSpacing.sp12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isSelectionActive) ...[
                  AppCheckbox(
                    value: isSelected,
                    onChanged: (_) =>
                        context.read<TicketSelectionCubit>().toggle(ticket.id),
                  ),
                  const SizedBox(width: AionSpacing.sp8),
                ],
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surfaceHover,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      ticket.ticketId,
                      style: AionText.key.copyWith(
                        color: c.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (interactive && !isSelectionActive) ...[
                  TicketOverflowMenu(ticket: ticket, compact: true),
                  const SizedBox(width: AionSpacing.sp4),
                  MoveToStatusMenu(ticket: ticket),
                ],
              ],
            ),
            const SizedBox(height: AionSpacing.sp8),
            Text(
              ticket.title,
              style: AionText.cardTitle.copyWith(color: c.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AionSpacing.sp8),
            Row(
              children: [
                TypeChip(type: ticket.type),
                if (ticket.priority != TicketPriority.none) ...[
                  const SizedBox(width: AionSpacing.sp8),
                  PriorityBadge(priority: ticket.priority),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon-button trigger opening an overlay list of every [TicketStatus]
/// other than [ticket]'s current one. The keyboard/screen-reader-
/// accessible equivalent of dragging a [TicketBoardCard] — selecting an
/// item calls the exact same [TicketsCubit.updateTicketStatus] the drag
/// path calls, so board status changes are never drag-only. Uses a
/// status-swap glyph (not `dots-three`) so it reads distinctly from the
/// adjacent [TicketOverflowMenu] trigger, which also renders on
/// [TicketBoardCard].
class MoveToStatusMenu extends StatefulWidget {
  /// Creates a [MoveToStatusMenu] that can move [ticket] to a different
  /// status.
  const MoveToStatusMenu({super.key, required this.ticket});

  /// The ticket this menu can move to a different status.
  final Ticket ticket;

  @override
  State<MoveToStatusMenu> createState() => _MoveToStatusMenuState();
}

class _MoveToStatusMenuState extends State<MoveToStatusMenu> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    // Removing here (rather than relying on the barrier tap) guards
    // against the overlay outliving this widget, e.g. if the card is
    // removed from the tree (board refresh) while the menu is open.
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _showOverlay() {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final overlay = Overlay.of(context);
    final otherStatuses = TicketStatus.values
        .where((s) => s != widget.ticket.status)
        .toList();

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 4),
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.all(AionRadius.lg),
                  border: Border.all(color: c.borderStrong, width: 1),
                  boxShadow: AionShadows.card(c, t.isDark),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: otherStatuses.map((status) {
                    return GestureDetector(
                      onTap: () {
                        context.read<TicketsCubit>().updateTicketStatus(
                          widget.ticket.id,
                          status,
                        );
                        _removeOverlay();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 14,
                        ),
                        child: Text(
                          ticketStatusLabel(context, status),
                          style: AionText.bodySm.copyWith(color: c.textPrimary),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        button: true,
        label: context.l10n.ticketsBoardMoveTicketLabel(widget.ticket.ticketId),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _showOverlay();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: _showOverlay,
            child: PhosphorIcon(
              PhosphorIcons.arrowsDownUpLight,
              size: 16,
              color: c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
