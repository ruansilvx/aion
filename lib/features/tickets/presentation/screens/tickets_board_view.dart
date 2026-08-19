// presentation/screens/tickets_board_view.dart — Kanban board view widgets (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';
import 'package:aion/features/providers/presentation/cubit/execution_scheduling_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/execution_scheduling_state.dart';
import 'package:aion/features/tickets/domain/entities/default_workflow_statuses.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/utils/sibling_cluster.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_selection_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart';
import 'package:aion/features/tickets/presentation/widgets/execution_cancel_control.dart';
import 'package:aion/features/tickets/presentation/widgets/resume_runs_prompt.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_overflow_menu.dart';
import 'package:aion/features/tickets/presentation/widgets/token_count_label.dart';

/// Fixed width of a single [BoardColumn].
const double _kColumnWidth = 280.0;

/// The default baseline preset's status names, in
/// [WorkflowStatus.sortOrder] order — the fixed column order every board
/// still renders in. Board/list column ordering does not yet follow a
/// project's live reconfigured status set (see
/// `aion-arch/changes/configurable-ticket-workflow`'s "Known limitation"
/// note in `proposal.md`); a project that reorders/renames/adds statuses
/// via the new Workflow settings screen changes what `Ticket.status`
/// itself is written as, and every gate/trigger honors that, but the
/// Board/List/Filters/Columns UI in this file still assumes this fixed
/// default set until a follow-up change threads `WorkflowConfigCubit`
/// through it.
final List<String> _defaultStatusOrder = [
  for (final s in defaultWorkflowStatuses) s.name,
];

/// Returns the display label for [status] (e.g. `"In progress"`). Shared by
/// [StatusIndicator] (`tickets_list_screen.dart`) and [BoardColumn]'s
/// header. Localizes the 6 default baseline preset names via `l10n`;
/// falls back to a humanized form of [status] itself (e.g.
/// `"needsRepro"` → `"Needs repro"`) for a project-renamed/added status
/// name, so a customized project still gets a readable label rather than
/// a crash. Was a total `switch` over the fixed `TicketStatus` enum
/// before `aion-arch/changes/configurable-ticket-workflow`.
String ticketStatusLabel(BuildContext context, String status) {
  final l10n = context.l10n;
  return switch (status) {
    'backlog' => l10n.ticketStatusBacklog,
    'todo' => l10n.ticketStatusToDo,
    'inProgress' => l10n.ticketStatusInProgress,
    'inReview' => l10n.ticketStatusInReview,
    'done' => l10n.ticketStatusDone,
    'cancelled' => l10n.ticketStatusCancelled,
    _ => _humanizeStatusName(status),
  };
}

/// Converts a raw status name (e.g. `needsRepro`, `needs_repro`) into a
/// readable label (`Needs repro`) — inserts a space before each internal
/// uppercase letter and each underscore, then capitalizes the first
/// letter. Used only as [ticketStatusLabel]'s fallback for a status name
/// outside the default baseline preset.
String _humanizeStatusName(String status) {
  final spaced = status
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ');
  if (spaced.isEmpty) return spaced;
  return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
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

/// Returns the localized display message for a classified [reason]. See
/// [TicketsErrorReason].
String ticketsErrorMessage(BuildContext context, TicketsErrorReason reason) {
  final l10n = context.l10n;
  return switch (reason) {
    TicketsErrorReason.notFound => l10n.ticketsErrorNotFound,
    TicketsErrorReason.invalidParent => l10n.ticketInvalidParentError,
    TicketsErrorReason.sddStagePreconditionNotMet =>
      l10n.ticketSddStagePreconditionNotMetError,
    TicketsErrorReason.codingExecutionBlocked =>
      l10n.ticketCodingExecutionBlockedError,
    TicketsErrorReason.executionBudgetOverageDetected =>
      l10n.executionBudgetOverageDetectedToast,
    TicketsErrorReason.executionVerificationFailed =>
      l10n.executionVerificationFailedToast,
    TicketsErrorReason.sddStageAdvanceFailed => l10n.sddStageAdvanceFailedToast,
    TicketsErrorReason.blockedByOpenDependency =>
      l10n.ticketBlockedByOpenDependencyError,
  };
}

/// The `/tickets` board view: tickets grouped into one column per
/// [TicketStatus], in declaration order — every column not in
/// [hiddenStatuses] renders, including when a visible status has no
/// tickets; column *order* is unaffected by [hiddenStatuses], only which
/// columns appear at all. [tickets] must already be filtered by the
/// caller (e.g. to task/story types); this widget only groups by status
/// and applies visibility, it does not filter by type. Pins
/// [ResumeRunsPrompt] above the columns whenever
/// `TicketsLoaded.pendingResumePrompt` is non-empty. Added for
/// `aion-arch/changes/parallel-work`; [hiddenStatuses] added for
/// `aion-arch/changes/list-board-view-and-column-visibility`.
class TicketBoardView extends StatelessWidget {
  /// Creates a [TicketBoardView] rendering [tickets] grouped by status,
  /// skipping every status in [hiddenStatuses].
  const TicketBoardView({
    super.key,
    required this.tickets,
    required this.hiddenStatuses,
  });

  /// The tickets to render, already filtered to the desired ticket types.
  final List<Ticket> tickets;

  /// Status names whose column is currently hidden — see
  /// `TicketsCubit.hiddenBoardColumns`. A display preference only: a
  /// ticket can still be moved into a hidden status via
  /// [MoveToStatusMenu], it simply won't be visible on the board until
  /// that column is shown again.
  final Set<String> hiddenStatuses;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Ticket>>{
      for (final status in _defaultStatusOrder)
        status: tickets.where((t) => t.status == status).toList(),
    };
    final pendingResumePrompt = context.select(
      (TicketsCubit cubit) => switch (cubit.state) {
        TicketsLoaded(:final pendingResumePrompt) => pendingResumePrompt,
        _ => const <Ticket>[],
      },
    );

    return Column(
      children: [
        if (pendingResumePrompt.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AionSpacing.sp20,
              AionSpacing.sp16,
              AionSpacing.sp20,
              0,
            ),
            child: ResumeRunsPrompt(tickets: pendingResumePrompt),
          ),
        Expanded(
          child: _BoardColumns(grouped: grouped, hiddenStatuses: hiddenStatuses),
        ),
      ],
    );
  }
}

/// The horizontal, per-status-column region of [TicketBoardView] —
/// hoisted out so [TicketBoardView.build] can wrap it with
/// [ResumeRunsPrompt] above without nesting the whole column list one
/// level deeper. Added for `aion-arch/changes/parallel-work`. Renders
/// [_NoColumnsVisibleHint] instead of the column scroller when every
/// status is in [hiddenStatuses] — added for
/// `aion-arch/changes/list-board-view-and-column-visibility`.
class _BoardColumns extends StatelessWidget {
  const _BoardColumns({required this.grouped, required this.hiddenStatuses});

  final Map<String, List<Ticket>> grouped;
  final Set<String> hiddenStatuses;

  @override
  Widget build(BuildContext context) {
    final visibleStatuses = _defaultStatusOrder
        .where((s) => !hiddenStatuses.contains(s))
        .toList();
    if (visibleStatuses.isEmpty) {
      return const _NoColumnsVisibleHint();
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AionSpacing.sp20,
        vertical: AionSpacing.sp16,
      ),
      itemCount: visibleStatuses.length,
      separatorBuilder: (context, index) =>
          const SizedBox(width: AionSpacing.sp12),
      itemBuilder: (context, index) {
        final status = visibleStatuses[index];
        return SizedBox(
          width: _kColumnWidth,
          child: BoardColumn(status: status, tickets: grouped[status]!),
        );
      },
    );
  }
}

/// Centered empty-state content shown in place of [_BoardColumns]'
/// horizontal scroller when every [TicketStatus] column is currently
/// hidden (the user unchecked every row in `TicketColumnsPopover`).
/// Distinct from `TicketsListScreen`'s "No tickets match your search"/
/// "No tickets yet" empty states, which are about ticket *content*, not
/// column *visibility* — reachable only through deliberate user action,
/// and just as reachable back out of via the still-available Columns
/// trigger above. Added for
/// `aion-arch/changes/list-board-view-and-column-visibility`; see that
/// change's design.md §6 and Component Spec §4.
class _NoColumnsVisibleHint extends StatelessWidget {
  const _NoColumnsVisibleHint();

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.primaryWash(isDark),
                borderRadius: BorderRadius.all(AionRadius.xl),
                border: Border.all(
                  color: c.columnsMotifBorderTint(isDark),
                  width: 1,
                ),
              ),
              child: SizedBox(
                width: 60,
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.columnsMotifBarTint,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const SizedBox(width: 6, height: 24),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.ticketsListNoColumnsVisibleTitle,
              textAlign: TextAlign.center,
              style: AionText.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              context.l10n.ticketsListNoColumnsVisibleHint,
              textAlign: TextAlign.center,
              style: AionText.bodySm.copyWith(color: c.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single status column on [TicketBoardView]: a header (status label +
/// ticket count) and a [DragTarget] accepting dropped [Ticket]s, moving
/// them to [status] via [TicketsCubit.updateTicketStatus]. Under
/// [ExecutionSchedulingMode.hybrid], applies [clusterSiblingsAdjacently]
/// to [tickets] so the sibling serialization that mode enforces is
/// visible on the Board, not just inferred from behavior — every other
/// mode renders [tickets] in its given order unchanged. Added for
/// `aion-arch/changes/parallel-work`; see that change's design.md §9.
class BoardColumn extends StatelessWidget {
  /// Creates a [BoardColumn] for [status], rendering [tickets].
  const BoardColumn({super.key, required this.status, required this.tickets});

  /// The status this column represents.
  final String status;

  /// The tickets currently in [status], in the Board's own primary sort
  /// order.
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isHybrid = context.select(
      (ExecutionSchedulingCubit cubit) =>
          cubit.state is ExecutionSchedulingReady &&
          (cubit.state as ExecutionSchedulingReady).mode ==
              ExecutionSchedulingMode.hybrid,
    );
    final displayedTickets = isHybrid
        ? clusterSiblingsAdjacently(tickets)
        : tickets;

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
                          itemCount: displayedTickets.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: AionSpacing.sp8),
                          // Keyed by ticket id (not left to Flutter's
                          // positional default) so a ticket's own
                          // subtree — its `context.select` subscriptions,
                          // its `MoveToStatusMenu`/`SelectionMenu`
                          // Overlay+LayerLink state, its Draggable — stays
                          // bound to that ticket's identity rather than to
                          // a list slot. Under rapid successive
                          // `TicketsLoaded` re-emissions (concurrent
                          // scheduling's more frequent emissions) plus
                          // Hybrid's `clusterSiblingsAdjacently`
                          // reordering, an unkeyed list lets Flutter
                          // reuse one ticket's Element for a different
                          // ticket mid-flight, corrupting `InheritedElement`
                          // dependent tracking and the render tree — this
                          // was the root cause of the intermittent
                          // `RenderFlex overflowed`/`Duplicate GlobalKey`/
                          // `'_dependents.isEmpty': is not true` crashes
                          // flagged in tasks.md T50. `TicketsListScreen`
                          // sidesteps the same class of bug by keying its
                          // whole body on the joined ticket-id list; this
                          // is the equivalent fix scoped to each card.
                          itemBuilder: (context, index) => TicketBoardCard(
                            key: ValueKey(displayedTickets[index].id),
                            ticket: displayedTickets[index],
                          ),
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

/// Compact per-card status derived from [TicketsLoaded]'s in-flight
/// fields (see
/// `aion-arch/changes/board-execution-indicators-and-notifications/design.md`
/// §1.4) for a specific ticket. `none` when the cubit's current state
/// isn't [TicketsLoaded] (e.g. a detail screen is the last thing that
/// ran) or nothing about that ticket is in flight. Renders as
/// [_BoardCardStatusBadge] in [_CardVisual].
enum _CardExecutionState { none, running, queued, advancing }

/// Resolves [t]'s [_CardExecutionState] (plus, for `queued`, its 1-based
/// queue position) from cubit state [s]. Task/Bug cards resolve to
/// `running`/`queued`/`none`; Epic/Story cards resolve to
/// `advancing`/`none` — the two families never co-occur on one card, so
/// checking all three fields unconditionally is safe. Added for
/// `aion-arch/changes/board-execution-indicators-and-notifications`.
(_CardExecutionState, int?) _cardExecutionState(TicketsState s, Ticket t) {
  if (s is! TicketsLoaded) return (_CardExecutionState.none, null);
  if (s.inFlightExecutionIds.contains(t.id)) {
    return (_CardExecutionState.running, null);
  }
  final queuePos = s.executionQueuePositions[t.id];
  if (queuePos != null) return (_CardExecutionState.queued, queuePos);
  if (s.inFlightAdvanceIds.contains(t.id)) {
    return (_CardExecutionState.advancing, null);
  }
  return (_CardExecutionState.none, null);
}

/// Whether [t] currently has an unresolved `blocks`/`blockedBy`
/// dependency, per [TicketsLoaded.blockedTicketIds]. `false` whenever
/// the cubit's current state isn't [TicketsLoaded] — mirrors
/// [_cardExecutionState]'s same no-signal-outside-`TicketsLoaded` floor.
/// Added for `aion-arch/changes/board-task-ordering-indication`.
bool _cardIsBlocked(TicketsState s, Ticket t) =>
    s is TicketsLoaded && s.blockedTicketIds.contains(t.id);

/// Resolves [t]'s token-count figures for [_CardVisual]'s meta-chip row,
/// or `null` when nothing should render — mirrors [_cardExecutionState]'s
/// same no-signal-outside-`TicketsLoaded` floor, and its own record-return
/// shape (rather than a [TokenCountLabel] instance directly, which would
/// defeat `context.select`'s narrow-rebuild scoping — [StatelessWidget]
/// has no value equality of its own, but a Dart record does). `null` for
/// every ticket type other than [TicketType.task]/[TicketType.bug]
/// (Component Spec §2.4 — coding execution, and therefore token spend, is
/// a Task/Bug-only mechanism). Implements this change's display-
/// precedence rule
/// (`aion-arch/changes/token-cost-prediction/design.md` §5): a running
/// total (from [TicketsLoaded.executionTokenTotals]) takes precedence
/// over the persisted prediction whenever present; otherwise, the
/// prediction shows only if [t] isn't currently running or queued — the
/// queued-state carve-out (design.md §5, Component Spec §2.1) suppresses
/// a stale leftover prediction for the entire window between a run being
/// triggered and its first turn completing, not just while literally
/// queued.
({TokenCountMode mode, int? low, int? high, int? total})? _cardTokenLabel(
  TicketsState s,
  Ticket t,
) {
  if (t.type != TicketType.task && t.type != TicketType.bug) return null;
  if (s is! TicketsLoaded) return null;

  final total = s.executionTokenTotals[t.id];
  if (total != null) {
    return (mode: TokenCountMode.total, low: null, high: null, total: total);
  }

  final (execState, _) = _cardExecutionState(s, t);
  if (execState == _CardExecutionState.running ||
      execState == _CardExecutionState.queued) {
    return null;
  }

  final low = t.predictedExecutionTokensLow;
  final high = t.predictedExecutionTokensHigh;
  if (low == null || high == null) return null;
  return (mode: TokenCountMode.range, low: low, high: high, total: null);
}

/// The visual card body shared by [TicketBoardCard]'s in-place, drag
/// feedback, and drag-placeholder renderings. Also renders a trailing
/// [_BoardCardStatusBadge] in the meta-chip row (beside [TypeChip]/
/// [PriorityBadge]) reflecting [ticket]'s live [_cardExecutionState], and
/// (inserted right after [PriorityBadge], before that trailing badge) a
/// [_BlockedBadge] reflecting [_cardIsBlocked] — both via a
/// `context.select` scoped to [ticket]'s own id so a card only rebuilds
/// when *its own* status/blocked state changes, not on every board-wide
/// emission. Also renders a [RollupBadge] (right-aligned, before
/// [_BoardCardStatusBadge]) when [ticket] has a live-children rollup —
/// see
/// `aion-arch/changes/estimate-timespent-rollup-for-ticket-hierarchy/design.md`
/// §2.5. Also renders a [TokenCountLabel] (right after [RollupBadge],
/// before [_BoardCardStatusBadge]) reflecting [_cardTokenLabel] — see
/// that helper's dartdoc for the display-precedence rule. The trailing
/// cluster (`RollupBadge` → `TokenCountLabel` → `_BoardCardStatusBadge`
/// [+ `ExecutionCancelControl`]) sits inside a right-aligned `Wrap`
/// (`spacing`/`runSpacing` 8, `Expanded` to preserve right-alignment on
/// a single line) rather than a plain `Row`, so a busy card wraps to a
/// second meta line instead of overflowing — Component Spec §2.3
/// (`aion-arch/changes/token-cost-prediction/design.md`). Added for
/// `aion-arch/changes/board-execution-indicators-and-notifications`,
/// `aion-arch/changes/board-task-ordering-indication`, and
/// `aion-arch/changes/token-cost-prediction`.
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
    final (execState, queuePosition) = context.select(
      (TicketsCubit cubit) => _cardExecutionState(cubit.state, ticket),
    );
    final isBlocked = context.select(
      (TicketsCubit cubit) => _cardIsBlocked(cubit.state, ticket),
    );
    final tokenLabel = context.select(
      (TicketsCubit cubit) => _cardTokenLabel(cubit.state, ticket),
    );
    // design.md §2.5: cards have no selection background variant, so
    // `RollupBadge` always uses its default fill here — no
    // `onSelectedRow` passed.
    final hasRollup =
        ticket.estimateRollup != null || ticket.timeSpentRollup != null;

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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TypeChip(type: ticket.type),
                if (ticket.priority != TicketPriority.none) ...[
                  const SizedBox(width: AionSpacing.sp8),
                  PriorityBadge(priority: ticket.priority),
                ],
                if (isBlocked) ...[
                  const SizedBox(width: AionSpacing.sp8),
                  const _BlockedBadge(),
                ],
                if (hasRollup ||
                    tokenLabel != null ||
                    execState != _CardExecutionState.none)
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AionSpacing.sp8,
                      runSpacing: AionSpacing.sp8,
                      children: [
                        if (hasRollup) RollupBadge(ticket: ticket),
                        if (tokenLabel != null)
                          tokenLabel.mode == TokenCountMode.total
                              ? TokenCountLabel.total(
                                  total: tokenLabel.total!,
                                  variant: TokenCountVariant.compact,
                                )
                              : TokenCountLabel.range(
                                  low: tokenLabel.low!,
                                  high: tokenLabel.high!,
                                  variant: TokenCountVariant.compact,
                                ),
                        if (execState != _CardExecutionState.none)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _BoardCardStatusBadge(
                                status: execState,
                                queuePosition: queuePosition,
                              ),
                              if (interactive &&
                                  (execState ==
                                          _CardExecutionState.running ||
                                      execState ==
                                          _CardExecutionState.queued)) ...[
                                const SizedBox(width: AionSpacing.sp4),
                                ExecutionCancelControl(
                                  placement: CancelPlacement.boardBadge,
                                  onCancel: () => context
                                      .read<TicketsCubit>()
                                      .cancelCodingExecution(ticket),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact, non-interactive filled pill rendering [status] on
/// [TicketBoardCard] — `running`/`queued` for a Task/Bug's coding-
/// execution state, `advancing` for an Epic/Story's stage-advance
/// state. `none` never reaches this widget ([_CardVisual] omits it from
/// the row entirely in that case). No hover/focused/pressed/disabled/
/// error states — the only motion is `running`'s rotating gear glyph
/// (static under reduced motion). Per Component Spec §1
/// (`aion-arch/changes/board-execution-indicators-and-notifications/design.md`).
class _BoardCardStatusBadge extends StatefulWidget {
  const _BoardCardStatusBadge({required this.status, this.queuePosition});

  /// Which state to render — must not be [_CardExecutionState.none].
  final _CardExecutionState status;

  /// The 1-based coding-execution queue position, required iff [status]
  /// is [_CardExecutionState.queued]; renders as `"Queued #N"`.
  final int? queuePosition;

  @override
  State<_BoardCardStatusBadge> createState() => _BoardCardStatusBadgeState();
}

class _BoardCardStatusBadgeState extends State<_BoardCardStatusBadge>
    with SingleTickerProviderStateMixin {
  // Nullable, created on demand rather than a `late final` field — most
  // badges (`queued`/`advancing`) never rotate at all, and a `late`
  // field's deferred-until-first-read semantics would otherwise construct
  // (and immediately try to look up the `vsync` ancestor for) the
  // controller for the first time inside `dispose()`, which throws
  // ("Looking up a deactivated widget's ancestor is unsafe").
  AnimationController? _gearController;

  bool _startedSpinning = false;

  AnimationController _ensureGearController() {
    return _gearController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.status == _CardExecutionState.running &&
        !_startedSpinning &&
        !MediaQuery.of(context).disableAnimations) {
      _startedSpinning = true;
      _ensureGearController().repeat();
    }
  }

  @override
  void dispose() {
    _gearController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    final (
      IconData glyph,
      String label,
      Color fg,
      Color fill,
      Color? border,
    ) = switch (widget.status) {
      _CardExecutionState.running => (
        PhosphorIcons.gearSixLight,
        context.l10n.ticketDetailBoardBadgeRunning,
        c.primary,
        c.pendingTint(isDark),
        null,
      ),
      _CardExecutionState.queued => (
        PhosphorIcons.stackLight,
        context.l10n.ticketDetailBoardBadgeQueuedNth(widget.queuePosition!),
        c.secondary,
        c.secondary.withValues(alpha: t.fillAlpha),
        c.secondary.withValues(alpha: isDark ? 0.24 : 0.18),
      ),
      _CardExecutionState.advancing => (
        PhosphorIcons.pencilSimpleLight,
        context.l10n.ticketDetailBoardBadgeAdvancing,
        c.primary,
        c.pendingTint(isDark),
        null,
      ),
      _CardExecutionState.none => (
        PhosphorIcons.gearSixLight,
        '',
        c.primary,
        c.pendingTint(isDark),
        null,
      ),
    };

    final icon = PhosphorIcon(glyph, size: 11, color: fg);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.all(AionRadius.pill),
        border: border != null ? Border.all(color: border, width: 1) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            widget.status == _CardExecutionState.running
                ? RotationTransition(
                    turns: _ensureGearController(),
                    child: icon,
                  )
                : icon,
            const SizedBox(width: 4),
            Text(
              label,
              style: AionText.chip.copyWith(
                color: fg,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small, non-interactive "Blocked" pill shown in [_CardVisual]'s
/// meta-chip row whenever the card's ticket id is in
/// [TicketsLoaded.blockedTicketIds] — purely informational, no gate on
/// drag/status-change (per the idea file's resolved Q4). Rendered right
/// after [PriorityBadge] and before the trailing [Spacer] +
/// [_BoardCardStatusBadge], in the same row
/// `board-execution-indicators-and-notifications` left room for. Static
/// (no animation, unlike [_BoardCardStatusBadge]'s spinning-gear
/// `running` state) — a broken-link glyph + "Blocked" label in the
/// `danger` tint family, distinct from [_BoardCardStatusBadge]'s neutral
/// `pendingTint`/`secondary` fills, since an open dependency reads as a
/// caution state rather than an active/queued one. Per Component Spec
/// §2 (`aion-arch/changes/board-task-ordering-indication/design.md`).
/// Added for `aion-arch/changes/board-task-ordering-indication`.
class _BlockedBadge extends StatelessWidget {
  /// Creates a [_BlockedBadge].
  const _BlockedBadge();

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isDark = t.isDark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.dangerTint(isDark),
        borderRadius: BorderRadius.all(AionRadius.pill),
        border: Border.all(color: c.dangerBorderTint(isDark), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PhosphorIcon(
              PhosphorIcons.linkBreakLight,
              size: 11,
              color: c.danger,
            ),
            const SizedBox(width: 4),
            Text(
              context.l10n.ticketDetailBoardBadgeBlocked,
              style: AionText.chip.copyWith(
                color: c.danger,
                letterSpacing: 0.2,
                height: 1.0,
              ),
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
/// [TicketBoardCard]. Each status row in the opened overlay is itself
/// keyboard-focusable and `Enter`/`Space`-activatable, via
/// `OverlayMenuItem` — not just the trigger.
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
    final otherStatuses = _defaultStatusOrder
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
                  children: otherStatuses.asMap().entries.map((entry) {
                    final index = entry.key;
                    final status = entry.value;
                    return OverlayMenuItem(
                      onTap: () {
                        context.read<TicketsCubit>().updateTicketStatus(
                          widget.ticket.id,
                          status,
                        );
                        _removeOverlay();
                      },
                      semanticsLabel: ticketStatusLabel(context, status),
                      // First row in the list — claims keyboard focus on
                      // open.
                      autofocus: index == 0,
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
