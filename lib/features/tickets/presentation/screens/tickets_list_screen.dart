// presentation/screens/tickets_list_screen.dart — Ticket list screen and row widgets (presentation layer).

import 'dart:async';

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
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_selection_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_board_view.dart';
import 'package:aion/features/tickets/presentation/widgets/baseline_upgrade_banner.dart';
import 'package:aion/features/tickets/presentation/widgets/codebase_analysis_banner.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_filter_popover.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_overflow_menu.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_selection_bar.dart';

/// The `/tickets` route: eyebrow + title header, a functioning search
/// field + status/type/priority filter row, the ticket list body driven
/// by [TicketsCubit], and an [AppFab] to create a new ticket. Loads the
/// unfiltered first page in [State.initState]. The flat list loads
/// further pages automatically as the user scrolls near the bottom (via
/// [TicketsCubit.loadMoreTickets]); board mode, which has no single
/// scroll container to hook that trigger onto, exposes an explicit
/// [_BoardLoadMoreButton] instead. When `ActiveProjectCubit`'s current
/// project was just created from an already-git-tracked directory, shows
/// a one-time [CodebaseAnalysisBanner] between the header and the
/// search/filter row (consumed via
/// `ActiveProjectCubit.consumeCodebaseAnalysisOffer` in [State.initState]
/// so it never reappears) — see `aion-arch/changes/
/// new-project-onboarding/design.md` §4.2. When the active project's
/// pinned baseline version isn't the latest bundled one, also shows a
/// [BaselineUpgradeBanner] above [CodebaseAnalysisBanner] (consumed via
/// `ActiveProjectCubit.consumeBaselineUpgradeOffer`) — unlike
/// [CodebaseAnalysisBanner]'s persisted-once-only offer, this one can
/// reappear on a later open for as long as a newer version remains
/// available. See `aion-arch/changes/baseline-version-upgrade-flow/
/// design.md` §4.1.
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

  /// Whether to show [CodebaseAnalysisBanner] — set once in [initState]
  /// from `ActiveProjectProvider.offerCodebaseAnalysis`, then owned
  /// locally so dismissing it doesn't depend on the provider's state
  /// (which is already consumed/cleared by the time the user dismisses).
  bool _showCodebaseAnalysisOffer = false;

  /// Whether to show [BaselineUpgradeBanner] — set once in [initState]
  /// from `ActiveProjectProvider.offerBaselineUpgrade`, then owned
  /// locally, same rationale as [_showCodebaseAnalysisOffer].
  bool _showBaselineUpgradeOffer = false;

  /// The latest bundled baseline version, fetched asynchronously in
  /// [initState] once [_showBaselineUpgradeOffer] is set — `null` until
  /// that fetch resolves, in which case [BaselineUpgradeBanner] isn't
  /// built yet.
  String? _baselineUpgradeTargetVersion;

  /// Controls and reads the search field's text.
  final TextEditingController _searchController = TextEditingController();

  /// Focus node for the search field, used only to drive the leading
  /// icon's color per design.md §2's per-state treatment.
  final FocusNode _searchFocusNode = FocusNode();

  /// Pending debounce timer for search-text-driven re-searches. Filter
  /// changes re-search immediately (via `TicketsCubit`'s toggle methods)
  /// and don't go through this.
  Timer? _searchDebounce;

  /// Drives the flat list's `ListView.separated`. Its listener
  /// ([_handleScroll]) triggers [TicketsCubit.loadMoreTickets] when the
  /// user scrolls within 400px of the bottom (design.md §4).
  final ScrollController _scrollController = ScrollController();

  /// Whether a search query or a non-default filter is currently active —
  /// used to pick between the "No tickets yet" and "No tickets match your
  /// search" empty states, and to drive the search icon's "active" color.
  /// Reads `TicketsCubit`'s selection getters instead of local fields —
  /// selection state now lives entirely in the cubit.
  bool get _hasActiveFilter {
    final cubit = context.read<TicketsCubit>();
    return _searchController.text.trim().isNotEmpty ||
        cubit.selectedStatuses.isNotEmpty ||
        cubit.selectedTypes.isNotEmpty ||
        cubit.selectedPriorities.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final activeProjectProvider = context.read<ActiveProjectProvider>();
    if (activeProjectProvider.offerCodebaseAnalysis) {
      _showCodebaseAnalysisOffer = true;
      activeProjectProvider.consumeCodebaseAnalysisOffer();
    }
    if (activeProjectProvider.offerBaselineUpgrade) {
      _showBaselineUpgradeOffer = true;
      activeProjectProvider.consumeBaselineUpgradeOffer();
      unawaited(_loadBaselineUpgradeTargetVersion());
    }
    _searchController.addListener(_handleSearchTextChanged);
    _scrollController.addListener(_handleScroll);
    unawaited(_initializeAndSearch());
  }

  /// Awaits [TicketsCubit.loadPersistedFilters] (restoring this project's
  /// saved filter selection, if any, into the cubit's remembered-filter
  /// fields), then runs [_runSearch] — so the very first search after
  /// opening the ticket list already reflects the persisted selection
  /// instead of flashing an unfiltered list first. Called via
  /// `unawaited(...)` from [initState], same fire-and-forget precedent
  /// this file already uses for [_loadBaselineUpgradeTargetVersion].
  Future<void> _initializeAndSearch() async {
    await context.read<TicketsCubit>().loadPersistedFilters();
    if (!mounted) return;
    _runSearch();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_handleSearchTextChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Fetches the latest bundled baseline version for
  /// [BaselineUpgradeBanner]'s target-version display, storing it in
  /// [_baselineUpgradeTargetVersion] once resolved. `BaselineRepository`
  /// is read directly rather than through `ActiveProjectProvider`
  /// (`core/contracts/`), matching `TicketsCubit`'s existing direct
  /// `BaselineRepository` dependency for asset content — it isn't part
  /// of the "what project is active" cross-feature contract Pattern 1
  /// covers.
  Future<void> _loadBaselineUpgradeTargetVersion() async {
    final versions = await context
        .read<BaselineRepository>()
        .getAvailableBaselineVersions();
    if (!mounted) return;
    setState(() => _baselineUpgradeTargetVersion = versions.last);
  }

  /// Triggers [TicketsCubit.loadMoreTickets] once the flat list has been
  /// scrolled within 400 logical pixels of the bottom, so the next page is
  /// already in flight before the user hits the physical end of the list
  /// (design.md §4). [TicketsCubit.loadMoreTickets] itself guards against
  /// this firing repeatedly while a page is already loading or none
  /// remains — no debounce timer needed here.
  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      context.read<TicketsCubit>().loadMoreTickets();
    }
  }

  /// Restarts the search debounce timer on every keystroke. Deliberately
  /// does not `setState` on every keystroke — the search field's leading
  /// icon (the only thing that needs to react per-keystroke) is handled
  /// by the `AnimatedBuilder` in [build] that listens to
  /// [_searchController]/[_searchFocusNode] directly, so typing doesn't
  /// rebuild the whole screen (including the `BlocBuilder`-driven ticket
  /// list) on every character.
  ///
  /// The debounced callback itself still calls `setState` once, before
  /// [_runSearch]: `TicketsCubit.searchTickets` emits `TicketsLoaded`,
  /// which is `Equatable`-based, so two consecutive searches that both
  /// return an empty list are equal states — `Cubit.emit` silently skips
  /// notifying `BlocBuilder` for a state equal to the current one. Without
  /// this `setState`, going from "no filter, zero tickets" to "a filter
  /// active, still zero matches" would leave [_buildTicketsBody] showing
  /// the stale "No tickets yet" message instead of "No tickets match your
  /// search", since [_hasActiveFilter] is widget-local state that
  /// `BlocBuilder` has no reason to re-read on its own.
  void _handleSearchTextChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      setState(() {});
      _runSearch();
    });
  }

  /// Re-runs the ticket search query against [TicketsCubit], combining
  /// the search text with the cubit's own remembered filter selection
  /// (`selectedStatuses`/`selectedTypes`/`selectedPriorities`). Called on
  /// init (via [_initializeAndSearch]), after the search-text debounce
  /// fires, and by the error state's Retry button — so retrying
  /// re-applies whatever search/filters were active rather than
  /// resetting them. Not called by the Filters popover's toggle
  /// handlers — `TicketsCubit.toggleStatusFilter`/etc. already re-search
  /// internally on every toggle.
  void _runSearch() {
    final cubit = context.read<TicketsCubit>();
    cubit.searchTickets(
      query: _searchController.text,
      statuses: cubit.selectedStatuses,
      types: cubit.selectedTypes,
      priorities: cubit.selectedPriorities,
    );
  }

  /// Extracts the currently loaded ticket list from any list-shaped
  /// [state], or an empty list otherwise. Shared by the header (Select
  /// toggle visibility), the body switch, and the selection bar's
  /// select-all wiring, so all three agree on "what's currently on
  /// screen." Excludes `resource`/`page` tickets — those moved to the
  /// Documentation section and are no longer shown here, in either list
  /// or board mode.
  List<Ticket> _currentTickets(TicketsState state) {
    final tickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreating(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdating(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsBatchTrashed(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => const <Ticket>[],
    };
    return tickets
        .where(
          (t) => t.type != TicketType.resource && t.type != TicketType.page,
        )
        .toList();
  }

  /// Whether at least one more page exists beyond the tickets currently on
  /// screen — drives both the flat list's scroll-triggered loading (via
  /// the presence of a footer) and the board mode's "Load more" button.
  /// `false` while a page is already loading ([TicketsLoadingMore]) or
  /// for any non-list state, since neither has anything new to trigger.
  bool _hasMore(TicketsState state) => switch (state) {
    TicketsLoaded(:final hasMore) => hasMore,
    TicketCreated(:final hasMore) => hasMore,
    TicketStatusUpdated(:final hasMore) => hasMore,
    TicketsBatchTrashed(:final hasMore) => hasMore,
    TicketsLoadMoreFailed(:final hasMore) => hasMore,
    _ => false,
  };

  /// Narrows [tickets] to whatever [_viewMode] actually renders as
  /// selectable rows/cards — the board view only shows story/task/bug
  /// types, so "select all" while on the board must not silently include
  /// ids for tickets that have no checkbox on screen.
  List<Ticket> _visibleTickets(List<Ticket> tickets) {
    if (_viewMode == _TicketViewMode.board) {
      return tickets
          .where(
            (t) => t.type == TicketType.story || t.type.isExecutable,
          )
          .toList();
    }
    return tickets;
  }

  /// Previews the cascade (per [TicketsCubit.previewTrashCount]), confirms
  /// via [showAppConfirmDialog], and — if confirmed — trashes every id in
  /// [selectedIds] via [TicketsCubit.trashTickets]. Shared onDelete
  /// handler for [TicketSelectionBar].
  Future<void> _confirmAndTrashSelection(
    BuildContext context,
    Set<String> selectedIds,
  ) async {
    final ids = selectedIds.toList();
    final total = await context.read<TicketsCubit>().previewTrashCount(ids);
    if (!context.mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.ticketBulkTrashConfirmTitle(ids.length),
      message: context.l10n.ticketTrashConfirmMessage(total),
      confirmLabel: context.l10n.ticketSelectionDeleteAction,
      tone: ConfirmDialogTone.reversible,
    );
    if (confirmed && context.mounted) {
      context.read<TicketsCubit>().trashTickets(ids);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocListener<TicketsCubit, TicketsState>(
      listener: (context, state) {
        if (state is TicketsBatchTrashed) {
          AppToast.show(
            context,
            context.l10n.ticketBulkTrashSummaryToast(state.trashedCount),
          );
          context.read<TicketSelectionCubit>().clear();
        }
      },
      child: BlocBuilder<TicketsCubit, TicketsState>(
        builder: (context, state) {
          final tickets = _currentTickets(state);
          final visibleTickets = _visibleTickets(tickets);
          final selection = context.watch<TicketSelectionCubit>().state;

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
                            style: AionText.caption.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                          const SizedBox(height: AionSpacing.sp4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  context.l10n.ticketsListTitle,
                                  style: AionText.h1.copyWith(
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                              _ViewModeToggle(
                                mode: _viewMode,
                                onChanged: (mode) =>
                                    setState(() => _viewMode = mode),
                              ),
                              if (tickets.isNotEmpty) ...[
                                const SizedBox(width: AionSpacing.sp8),
                                const _SelectModeToggle(),
                              ],
                            ],
                          ),
                          const SizedBox(height: AionSpacing.sp12),
                        ],
                      ),
                    ),
                    if (_showBaselineUpgradeOffer &&
                        _baselineUpgradeTargetVersion != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        child: BaselineUpgradeBanner(
                          currentVersion: context
                              .read<ActiveProjectProvider>()
                              .activeProject!
                              .baselineVersion,
                          targetVersion: _baselineUpgradeTargetVersion!,
                          onDismiss: () =>
                              setState(() => _showBaselineUpgradeOffer = false),
                        ),
                      ),
                    if (_showCodebaseAnalysisOffer)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        child: CodebaseAnalysisBanner(
                          onDismiss: () =>
                              setState(() => _showCodebaseAnalysisOffer = false),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _searchController,
                              _searchFocusNode,
                            ]),
                            builder: (context, _) {
                              return AppTextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                hintText: context.l10n.ticketsListSearchHint,
                                prefixIcon: PhosphorIcon(
                                  PhosphorIcons.magnifyingGlassLight,
                                  size: 18,
                                  color: _searchFocusNode.hasFocus
                                      ? c.primary
                                      : (_searchController.text
                                                .trim()
                                                .isNotEmpty
                                            ? c.textSecondary
                                            : c.textMuted),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          const _TicketFilterSection(),
                        ],
                      ),
                    ),
                    const SizedBox(height: AionSpacing.sp4),
                    Expanded(
                      child: ColoredBox(
                        color: c.surface,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: c.border, width: 1),
                            ),
                          ),
                          child: switch (state) {
                            TicketsLoading() => const Center(
                              child: AppSpinner(),
                            ),
                            TicketTrashing() => const Center(
                              child: AppSpinner(),
                            ),
                            TicketsBatchTrashing() => const Center(
                              child: AppSpinner(),
                            ),
                            TicketsError(:final message, :final reason) =>
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      reason != null
                                          ? ticketsErrorMessage(context, reason)
                                          : message,
                                      style: AionText.body.copyWith(
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: AionSpacing.sp12),
                                    AppButton(
                                      label: context.l10n.commonRetry,
                                      onPressed: _runSearch,
                                    ),
                                  ],
                                ),
                              ),
                            TicketsLoaded() ||
                            TicketCreating() ||
                            TicketCreated() ||
                            TicketStatusUpdating() ||
                            TicketStatusUpdated() ||
                            TicketsBatchTrashed() ||
                            TicketsLoadingMore() ||
                            TicketsLoadMoreFailed() => AnimatedSwitcher(
                              duration: const Duration(milliseconds: 120),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(opacity: anim, child: child),
                              child: KeyedSubtree(
                                key: ValueKey(
                                  tickets.map((t) => t.id).join(','),
                                ),
                                child: _TicketsBody(
                                  tickets: tickets,
                                  state: state,
                                  viewMode: _viewMode,
                                  hasActiveFilter: _hasActiveFilter,
                                  scrollController: _scrollController,
                                ),
                              ),
                            ),
                            _ => const SizedBox.shrink(),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                if (!selection.isActive)
                  Positioned(
                    right: 18,
                    bottom: 24,
                    child: AppFab(
                      onTap: () => context.go('/workspace/tickets/new'),
                    ),
                  )
                else
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: TicketSelectionBar(
                      selectedCount: selection.selectedIds.length,
                      allSelected:
                          visibleTickets.isNotEmpty &&
                          visibleTickets.every(
                            (t) => selection.selectedIds.contains(t.id),
                          ),
                      onCancel: () =>
                          context.read<TicketSelectionCubit>().clear(),
                      onSelectAll: () => context
                          .read<TicketSelectionCubit>()
                          .selectAll(visibleTickets.map((t) => t.id).toList()),
                      onDelete: () => _confirmAndTrashSelection(
                        context,
                        selection.selectedIds,
                      ),
                    ),
                  ),
                if (_viewMode == _TicketViewMode.board &&
                    (_hasMore(state) || state is TicketsLoadingMore) &&
                    !selection.isActive)
                  Positioned(
                    left: 18,
                    bottom: 24,
                    child: _BoardLoadMoreButton(
                      isLoading: state is TicketsLoadingMore,
                      onTap: () =>
                          context.read<TicketsCubit>().loadMoreTickets(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Renders the loaded ticket list as either the flat list or the board,
/// depending on [viewMode]. An empty [tickets] list shows "No tickets
/// match your search" when [hasActiveFilter], otherwise the generic "No
/// tickets yet" message. [state] drives the flat list's scroll-triggered
/// loading footer (design.md §1/§2) — nothing beyond [tickets] itself is
/// needed in board mode, which uses the separate "Load more" button in
/// `TicketsListScreen.build` instead (design.md §3).
class _TicketsBody extends StatelessWidget {
  const _TicketsBody({
    required this.tickets,
    required this.state,
    required this.viewMode,
    required this.hasActiveFilter,
    required this.scrollController,
  });

  final List<Ticket> tickets;
  final TicketsState state;
  final _TicketViewMode viewMode;
  final bool hasActiveFilter;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    if (tickets.isEmpty) {
      if (hasActiveFilter) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: t.fillAlpha),
                    borderRadius: BorderRadius.all(AionRadius.xl),
                  ),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Center(
                      child: PhosphorIcon(
                        PhosphorIcons.magnifyingGlassLight,
                        size: 28,
                        color: c.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AionSpacing.sp16),
                Text(
                  context.l10n.ticketsListNoResultsState,
                  textAlign: TextAlign.center,
                  style: AionText.body.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.ticketsListNoResultsHint,
                  textAlign: TextAlign.center,
                  style: AionText.bodySm.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Text(
          context.l10n.ticketsListEmptyState,
          style: AionText.body.copyWith(color: c.textMuted),
        ),
      );
    }

    if (viewMode == _TicketViewMode.board) {
      final boardTickets = tickets
          .where(
            (ticket) =>
                ticket.type == TicketType.story || ticket.type.isExecutable,
          )
          .toList();
      return TicketBoardView(tickets: boardTickets);
    }

    final isLoadingMore = state is TicketsLoadingMore;
    final loadMoreFailed = state is TicketsLoadMoreFailed;
    final showFooter = isLoadingMore || loadMoreFailed;

    return ContentMaxWidth(
      variant: ContentWidthVariant.reading,
      child: ListView.separated(
        controller: scrollController,
        itemCount: tickets.length + (showFooter ? 1 : 0),
        separatorBuilder: (context, index) =>
            Container(color: c.border, height: 1),
        itemBuilder: (context, index) {
          if (index >= tickets.length) {
            return _TicketListFooter(
              isLoadingMore: isLoadingMore,
              onRetry: () => context.read<TicketsCubit>().loadMoreTickets(),
            );
          }
          return TicketListTile(ticket: tickets[index]);
        },
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
                  style: AionText.button.copyWith(
                    color: const Color(0xFFFFFFFF),
                  ),
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
              child: PhosphorIcon(
                icon,
                size: 18,
                color: isActive ? c.primary : c.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header icon button toggling [TicketSelectionCubit]'s selection mode on.
/// Not the exit path once active — [TicketSelectionBar]'s Cancel control
/// handles that — so taps while already active are inert; the button
/// simply renders in its active (`primarySubtle`-tinted) look.
class _SelectModeToggle extends StatefulWidget {
  const _SelectModeToggle();

  @override
  State<_SelectModeToggle> createState() => _SelectModeToggleState();
}

class _SelectModeToggleState extends State<_SelectModeToggle> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isActive = context.watch<TicketSelectionCubit>().state.isActive;

    void enter() {
      if (!isActive) context.read<TicketSelectionCubit>().enter();
    }

    final fill = _isPressed
        ? c.border
        : isActive
        ? c.primarySubtle
        : (_isHovered ? c.surfaceHover : const Color(0x00000000));
    final iconColor = isActive
        ? c.primary
        : (_isHovered ? c.textPrimary : c.textSecondary);
    final boxShadow = _isFocused
        ? [
            BoxShadow(
              color: c.primary.withValues(alpha: t.isDark ? 0.30 : 0.16),
              spreadRadius: 3,
            ),
          ]
        : const <BoxShadow>[];

    return Semantics(
      button: true,
      label: context.l10n.ticketSelectionToggleLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
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
            onTap: enter,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.96 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.all(AionRadius.iconBtn),
                  boxShadow: boxShadow,
                ),
                child: SizedBox(
                  width: 37,
                  height: 37,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIcons.checkSquareLight,
                      size: 20,
                      color: iconColor,
                    ),
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

/// Composes the "Filters" trigger row (§1.2) and the conditional chip row
/// (§5) below it: reads `TicketsCubit`'s selection getters
/// ([TicketsCubit.selectedStatuses]/[TicketsCubit.selectedTypes]/
/// [TicketsCubit.selectedPriorities]) for both the popover's checked
/// state and the chip row's content, and wires each toggle handler
/// directly to the matching `TicketsCubit.toggleXFilter` method — no
/// local `setState` for selection itself, only for
/// [TicketFilterPopover]'s own open/closed visual state (fed back via
/// [TicketFilterPopover.onOpenChanged]). The chip row renders zero
/// height (no reserved space, no gap above it) when every selection set
/// is empty.
class _TicketFilterSection extends StatefulWidget {
  const _TicketFilterSection();

  @override
  State<_TicketFilterSection> createState() => _TicketFilterSectionState();
}

class _TicketFilterSectionState extends State<_TicketFilterSection> {
  bool _isPopoverOpen = false;
  bool _isTriggerFocused = false;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<TicketsCubit>();
    final selectedStatuses = cubit.selectedStatuses;
    final selectedTypes = cubit.selectedTypes;
    final selectedPriorities = cubit.selectedPriorities;
    final activeCount =
        selectedStatuses.length +
        selectedTypes.length +
        selectedPriorities.length;
    final hasChips = activeCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TicketFilterPopover(
            trigger: _FilterTriggerButton(
              activeCount: activeCount,
              isOpen: _isPopoverOpen,
              isFocused: _isTriggerFocused,
            ),
            selectedStatuses: selectedStatuses,
            selectedTypes: selectedTypes,
            selectedPriorities: selectedPriorities,
            onToggleStatus: context.read<TicketsCubit>().toggleStatusFilter,
            onToggleType: context.read<TicketsCubit>().toggleTypeFilter,
            onTogglePriority: context
                .read<TicketsCubit>()
                .togglePriorityFilter,
            onOpenChanged: (isOpen) =>
                setState(() => _isPopoverOpen = isOpen),
            onFocusChanged: (isFocused) =>
                setState(() => _isTriggerFocused = isFocused),
          ),
        ),
        if (hasChips) ...[
          const SizedBox(height: AionSpacing.sp8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in selectedStatuses)
                AppFilterChip(
                  label: ticketStatusLabel(context, s),
                  onRemove: () =>
                      context.read<TicketsCubit>().toggleStatusFilter(s),
                  removeSemanticsLabel: context.l10n
                      .ticketsListFilterChipRemoveSemantics(
                        ticketStatusLabel(context, s),
                      ),
                ),
              for (final t in selectedTypes)
                AppFilterChip(
                  label: ticketTypeLabel(context, t),
                  onRemove: () =>
                      context.read<TicketsCubit>().toggleTypeFilter(t),
                  removeSemanticsLabel: context.l10n
                      .ticketsListFilterChipRemoveSemantics(
                        ticketTypeLabel(context, t),
                      ),
                ),
              for (final p in selectedPriorities)
                AppFilterChip(
                  label: ticketPriorityLabel(context, p),
                  onRemove: () =>
                      context.read<TicketsCubit>().togglePriorityFilter(p),
                  removeSemanticsLabel: context.l10n
                      .ticketsListFilterChipRemoveSemantics(
                        ticketPriorityLabel(context, p),
                      ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The "Filters" trigger button that opens [TicketFilterPopover]. Two
/// visual sub-states — idle (no filters active) and active
/// ([activeCount] ≥ 1) — mapped onto `AppDropdown`'s inactive/`isActive`
/// color language for visual continuity with the three-dropdown row this
/// replaces, plus a trailing count badge shown only in the active
/// sub-state. Purely presentational — [TicketFilterPopover] (which wraps
/// this as its `trigger`) owns the actual tap/keyboard-activation
/// handling; [isOpen] and [isFocused] are fed back in via
/// [TicketFilterPopover.onOpenChanged]/[TicketFilterPopover.onFocusChanged]
/// so this can render "open" and "focused" looks the same way [isActive]
/// renders an "active" one. Per design.md §3.2, a keyboard-focused trigger
/// and an open trigger share the same emphasized appearance (border +
/// glow ring) — [isOpen] and [isFocused] are treated identically here.
class _FilterTriggerButton extends StatefulWidget {
  const _FilterTriggerButton({
    required this.activeCount,
    required this.isOpen,
    required this.isFocused,
  });

  /// Total number of selected values across all three filter fields.
  /// Zero means the idle sub-state; any other value means active, with
  /// the count shown in a trailing badge.
  final int activeCount;

  /// Whether [TicketFilterPopover]'s overlay is currently open — rendered
  /// as the same emphasized look as keyboard focus.
  final bool isOpen;

  /// Whether this trigger currently holds keyboard focus — rendered as
  /// the same emphasized look as [isOpen], independent of whether the
  /// popover has actually been activated yet (design.md §3.2's
  /// `Focused` sub-state).
  final bool isFocused;

  @override
  State<_FilterTriggerButton> createState() => _FilterTriggerButtonState();
}

class _FilterTriggerButtonState extends State<_FilterTriggerButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isActive = widget.activeCount > 0;
    final showRing = widget.isOpen || widget.isFocused;
    final emphasized = isActive || showRing;

    final Color fill = isActive ? c.primarySubtle : c.surface;
    final Color border = isActive
        ? c.primary
        : (showRing ? c.primary : (_isHovered ? c.borderStrong : c.border));
    final Color foreground = isActive
        ? c.primary
        : (showRing ? c.primary : c.textSecondary);
    final Color labelColor = isActive || showRing
        ? (isActive ? c.primary : c.textPrimary)
        : c.textPrimary;

    return Semantics(
      button: true,
      label: context.l10n.ticketsListFilterTriggerSemantics(
        widget.activeCount,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.all(AionRadius.lg),
            border: Border.all(color: border, width: emphasized ? 1.5 : 1),
            boxShadow: showRing
                ? [
                    BoxShadow(
                      color: c.primary.withValues(
                        alpha: t.isDark ? 0.30 : 0.16,
                      ),
                      spreadRadius: 3,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIcons.funnelLight,
                size: 16,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.ticketsListFilterTriggerLabel,
                style: AionText.button.copyWith(color: labelColor),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.all(AionRadius.pill),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.activeCount >= 10 ? 5 : 0,
                      vertical: 1,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Center(
                        child: Text(
                          '${widget.activeCount}',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The last item appended to [TicketsListScreen]'s flat `ListView` while
/// [TicketsCubit.loadMoreTickets] is fetching the next page, or after it
/// has failed. Renders a centered [AppSpinner] while loading (design.md
/// §1), or a tappable retry row when the last attempt failed (design.md
/// §2). The caller only includes this in `itemCount` when one of those
/// two conditions holds — it's never built otherwise.
class _TicketListFooter extends StatelessWidget {
  /// Creates a [_TicketListFooter]. [isLoadingMore] selects the loading
  /// spinner; otherwise the retry row is shown, calling [onRetry] when
  /// tapped or keyboard-activated.
  const _TicketListFooter({required this.isLoadingMore, required this.onRetry});

  /// Whether a page fetch is currently in flight.
  final bool isLoadingMore;

  /// Called when the retry row is tapped or keyboard-activated. Never
  /// invoked while [isLoadingMore] is true (no retry row is shown then).
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: AppSpinner(size: 22)),
      );
    }
    return _LoadMoreRetryRow(onRetry: onRetry);
  }
}

/// The tappable "couldn't load more — tap to retry" row shown by
/// [_TicketListFooter] after a failed [TicketsCubit.loadMoreTickets]
/// attempt (design.md §2). A soft, recoverable inline failure — `danger`
/// is used restrained (icon/text tint, soft wash on hover/press) rather
/// than a heavy blocking error treatment. Manages its own hover/press/
/// focus visual state, matching this file's other interactive primitives
/// (e.g. [_SelectModeToggleState]). Uses a `danger`-toned focus ring
/// rather than the design system's default `primary` ring, since every
/// other visual on this control is already `danger`-toned (design.md §2.5).
class _LoadMoreRetryRow extends StatefulWidget {
  /// Creates a [_LoadMoreRetryRow] that calls [onRetry] when activated.
  const _LoadMoreRetryRow({required this.onRetry});

  /// Called when tapped or keyboard-activated.
  final VoidCallback onRetry;

  @override
  State<_LoadMoreRetryRow> createState() => _LoadMoreRetryRowState();
}

class _LoadMoreRetryRowState extends State<_LoadMoreRetryRow> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final fill = _isPressed
        ? c.danger.withValues(alpha: t.fillAlpha + 0.06)
        : (_isHovered
              ? c.danger.withValues(alpha: t.fillAlpha)
              : const Color(0x00000000));
    final boxShadow = _isFocused
        ? [
            BoxShadow(
              color: c.danger.withValues(alpha: t.isDark ? 0.30 : 0.16),
              spreadRadius: 3,
            ),
          ]
        : const <BoxShadow>[];

    return Semantics(
      button: true,
      label: context.l10n.ticketsListLoadMoreRetry,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onRetry();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: widget.onRetry,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
                    boxShadow: boxShadow,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        PhosphorIcon(
                          PhosphorIcons.arrowClockwiseLight,
                          size: 16,
                          color: c.danger,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          context.l10n.ticketsListLoadMoreRetry,
                          style: AionText.bodySm.copyWith(color: c.danger),
                        ),
                      ],
                    ),
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

/// Floating "Load more" button shown in board mode when
/// [TicketsCubit.loadMoreTickets] has another page available, and kept
/// mounted through an in-flight fetch triggered from either the board
/// button or the flat list's scroll trigger (design.md §3, §3.8) — a
/// `TicketsLoadingMore` state always implies the prior snapshot had
/// `hasMore: true` (see [TicketsCubit.loadMoreTickets]'s guard), so
/// [_TicketsListScreenState.build] builds this widget whenever
/// `_hasMore(state) || state is TicketsLoadingMore`, avoiding the
/// layout shift design.md §3.8 calls out. Anchored bottom-left so it
/// never collides with [AppFab] (bottom-right) or [TicketSelectionBar]
/// (which already hides both via the same `selection.isActive`
/// visibility rule). Takes a secondary/outlined treatment (surface
/// fill, `borderStrong` outline) rather than [AppFab]'s solid `primary`
/// fill, so the create action stays the single visually-dominant
/// floating control. Deliberately has no disabled variant — it's simply
/// absent when no next page exists and nothing is loading.
class _BoardLoadMoreButton extends StatefulWidget {
  /// Creates a [_BoardLoadMoreButton]. Shows a small [AppSpinner] in
  /// place of the leading icon while [isLoading] is true (a board-
  /// triggered page fetch is in flight, design.md §3.8); calls [onTap]
  /// when tapped or keyboard-activated.
  const _BoardLoadMoreButton({required this.isLoading, required this.onTap});

  /// Whether a board-triggered page fetch is currently in flight.
  final bool isLoading;

  /// Called when tapped or keyboard-activated.
  final VoidCallback onTap;

  @override
  State<_BoardLoadMoreButton> createState() => _BoardLoadMoreButtonState();
}

class _BoardLoadMoreButtonState extends State<_BoardLoadMoreButton> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    final fill = (_isPressed || _isHovered) ? c.surfaceHover : c.surface;
    final borderColor = _isFocused ? c.primary : c.borderStrong;
    final borderWidth = _isFocused ? 1.5 : 1.0;
    final restingShadow = t.isDark
        ? const <BoxShadow>[]
        : [
            BoxShadow(
              color: c.textPrimary.withValues(alpha: 0.22),
              blurRadius: 20,
              spreadRadius: -8,
              offset: const Offset(0, 8),
            ),
          ];
    final focusRing = _isFocused
        ? [
            BoxShadow(
              color: c.primary.withValues(alpha: t.isDark ? 0.30 : 0.16),
              spreadRadius: 3,
            ),
          ]
        : const <BoxShadow>[];

    return Semantics(
      button: true,
      label: context.l10n.ticketsBoardLoadMoreLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.all(AionRadius.pill),
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: [...restingShadow, ...focusRing],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 18,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      widget.isLoading
                          ? const AppSpinner(size: 15)
                          : PhosphorIcon(
                              PhosphorIcons.arrowDownLight,
                              size: 15,
                              color: c.textSecondary,
                            ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.ticketsBoardLoadMoreLabel,
                        style: AionText.button.copyWith(color: c.textPrimary),
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

/// A single row in [TicketsListScreen]'s list: ID badge, title, priority
/// badge, [TicketOverflowMenu] trigger, type chip, and status indicator —
/// or, while [TicketSelectionCubit]'s selection mode is active, a leading
/// [AppCheckbox] in place of the overflow trigger, with tapping the row
/// toggling selection instead of navigating. Navigates to the ticket's
/// detail screen when tapped or activated via keyboard, when selection
/// mode is inactive.
class TicketListTile extends StatelessWidget {
  /// Creates a [TicketListTile] rendering [ticket].
  const TicketListTile({super.key, required this.ticket});

  /// The ticket this row represents.
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
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

    return Semantics(
      label: '${ticket.ticketId} ${ticket.title}',
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isSelected ? c.primarySubtle : c.surface,
              border: isSelected
                  ? Border(left: BorderSide(color: c.primary, width: 3))
                  : null,
            ),
            child: Padding(
              padding: isSelectionActive
                  ? const EdgeInsets.fromLTRB(16, 12, 20, 12)
                  : const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isSelectionActive) ...[
                        AppCheckbox(
                          value: isSelected,
                          onChanged: (_) => context
                              .read<TicketSelectionCubit>()
                              .toggle(ticket.id),
                        ),
                        const SizedBox(width: AionSpacing.sp12),
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
                      const SizedBox(width: AionSpacing.sp12),
                      Expanded(
                        child: Text(
                          ticket.title,
                          style: AionText.cardTitle.copyWith(
                            color: c.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ticket.priority != TicketPriority.none) ...[
                        const SizedBox(width: AionSpacing.sp12),
                        PriorityBadge(priority: ticket.priority),
                      ],
                      if (!isSelectionActive) ...[
                        const SizedBox(width: AionSpacing.sp8),
                        TicketOverflowMenu(ticket: ticket, compact: true),
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
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: isRow
            ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
            : const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        child: Text(
          ticketPriorityLabel(context, priority).toUpperCase(),
          style: (isRow ? AionText.prioritySm : AionText.priorityBig).copyWith(
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// A small chip showing a ticket's type as a colored square + uppercase
/// label. Color is derived from [type] via [AionColors.typeTask]/
/// [AionColors.typeStory]/[AionColors.typeEpic]/[AionColors.typeResource]/
/// [AionColors.typePage].
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
              PhosphorIcon(
                PhosphorIcons.linkLight,
                size: 11,
                color: c.textMuted,
              ),
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
