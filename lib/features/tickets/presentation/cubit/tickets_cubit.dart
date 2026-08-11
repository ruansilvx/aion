// presentation/cubit/tickets_cubit.dart — TicketsCubit business logic (presentation layer).

import 'dart:math' show max;

import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';
import 'package:aion/core/build/project_stack_detector.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/core/git/github_cli_client.dart';
import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/execution_context_cap_repository.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/domain/entities/linked_ticket_ref.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_filters.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/summarization_depth.dart';
import 'package:aion/features/tickets/domain/enums/ticket_complexity.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_severity.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_filter_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_sort_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/domain/utils/ticket_link_direction.dart';
import 'package:aion/features/tickets/domain/utils/ticket_rollup_calculator.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/codebase_analysis_status.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_rollup_counts.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_rollup_recomputer.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';

/// Loads, lists, and creates tickets via [TicketRepository]. Root-scoped —
/// provided once at the app root, not per-screen. Every list-shaped
/// repository query also resolves and passes a [TicketListSort] (see
/// [currentSort]/[setSort]/[_lastSort]) — an explicit user choice if one
/// has been made, otherwise an implicit query-aware default — so the
/// list, board, and Trash all render in the same order. See
/// `aion-arch/changes/ticket-sort-control-and-board-as-default-view`.
class TicketsCubit extends Cubit<TicketsState> {
  /// Creates a [TicketsCubit] backed by [_repository]. [_embeddingProvider],
  /// [_gitProjector], [_projectRootPath], [_providerRegistry], and
  /// [_commentRepository] are optional — when any is `null` (the
  /// default, and every existing call site/test), the embedding-regen,
  /// git-projection, and stage-chat-spawning side effects documented on
  /// [createTicket]/[updateTicket]/[updateTicketStatus]/
  /// [changeTicketStatus]/[trashTicket]/[trashTickets]/[advanceSddStage]
  /// simply no-op, rather than requiring every one of ~40 existing
  /// construction sites to be updated for a feature most of them don't
  /// exercise. Real usage (`app_router.dart`) supplies [_providerRegistry]/
  /// [_commentRepository] so [advanceSddStage] always spawns its chat.
  /// [_automationSettingsRepository] follows the same optional-dependency
  /// pattern — `null` leaves a finished coding-execution run's status
  /// untouched (never auto-flips to `inReview`) until a caller supplies
  /// one; real usage (`app_router.dart`) always does.
  /// [_modelRoutingRepository] follows the same optional-dependency
  /// pattern too — `null` makes every stage-chat/coding-execution model
  /// resolution fall back to the first registered provider's first model
  /// (see [_resolveModel]), today's pre-per-phase-routing default; real
  /// usage (`app_router.dart`) always supplies one.
  /// [_gitClient]/[_gitHubClient] follow the same optional-dependency
  /// pattern too — `null` makes [_runCodingExecution] no-op entirely
  /// (same guard as [_providerRegistry]/[_commentRepository]), since a
  /// worktree-isolated, verify-gated run can't proceed without them;
  /// real usage (`app_router.dart`) always supplies them. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`.
  /// [_baselineRepository]/[_projectId]/[_baselineVersion] follow the
  /// same pattern again — `null` on any of them also no-ops
  /// [_runCodingExecution], since resolving the effective `skills/
  /// verify`/`conventions/architecture-conventions` content
  /// ([_effectiveAssetContent]) needs all three; real usage always
  /// supplies them too. Added for `aion-arch/changes/project-type-
  /// aware-conventions-and-verification` (replaces the prior
  /// `FlutterVerifier`-based mechanical verify gate with an agentic one
  /// — see [_assembleVerificationContext]).
  /// [_projectName] follows the same optional-dependency pattern once
  /// more — `null` falls back to a generic title in
  /// [runCodebaseSummarization]'s spawned run ticket; real usage
  /// (`app_router.dart`) supplies the active `Project.name`. Added for
  /// `aion-arch/changes/new-project-onboarding`.
  /// [_executionContextCapRepository] follows the same optional-dependency
  /// pattern once more — `null` (every existing construction site except
  /// `app_router.dart`) makes [_effectiveExecutionContextCap] always
  /// resolve to the execution-phase model's real
  /// `AgentModelDescriptor.contextWindowTokens` with no user override
  /// available — the handoff mechanism itself still works, only the
  /// user-configurable lowering of the threshold doesn't. Added for
  /// `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-trigger`.
  /// [_filterRepository] follows the same optional-dependency pattern once
  /// more — `null` makes [toggleStatusFilter]/[toggleTypeFilter]/
  /// [togglePriorityFilter] skip persistence (the in-memory toggle and
  /// re-search still work) and [loadPersistedFilters] a no-op; real usage
  /// (`app_router.dart`) always supplies one. Added for
  /// `aion-arch/changes/multi-select-ticket-list-filters`.
  /// [_sortRepository] follows the same optional-dependency pattern once
  /// more — `null` makes [setSort] skip persistence (the in-memory
  /// override still works) and [loadPersistedSort] a no-op; real usage
  /// (`app_router.dart`) always supplies one, alongside the existing
  /// [_filterRepository]/[_projectId]. Added for
  /// `aion-arch/changes/ticket-sort-control-and-board-as-default-view`.
  // The public param names below (embeddingProvider/gitProjector/
  // projectRootPath/providerRegistry/commentRepository/
  // automationSettingsRepository/modelRoutingRepository/gitClient/
  // gitHubClient/baselineRepository/projectId/baselineVersion/
  // projectName/filterRepository/sortRepository) intentionally differ
  // from their private backing fields; a private identifier can't be
  // used as an external named-parameter label from another library, so
  // `this._foo` shorthand isn't usable here.
  TicketsCubit(
    this._repository, {
    EmbeddingProvider? embeddingProvider,
    TicketGitProjector? gitProjector,
    String? projectRootPath,
    TicketLinkRepository? linkRepository,
    ProviderRegistry? providerRegistry,
    CommentRepository? commentRepository,
    AutomationSettingsRepository? automationSettingsRepository,
    ModelRoutingRepository? modelRoutingRepository,
    GitRepositoryClient? gitClient,
    GitHubCliClient? gitHubClient,
    BaselineRepository? baselineRepository,
    String? projectId,
    String? baselineVersion,
    String? projectName,
    ExecutionContextCapRepository? executionContextCapRepository,
    TicketListFilterRepository? filterRepository,
    TicketListSortRepository? sortRepository,
  }) : super(const TicketsInitial()) {
    _embeddingProvider = embeddingProvider;
    _gitProjector = gitProjector;
    _projectRootPath = projectRootPath;
    _linkRepository = linkRepository;
    _providerRegistry = providerRegistry;
    _commentRepository = commentRepository;
    _automationSettingsRepository = automationSettingsRepository;
    _modelRoutingRepository = modelRoutingRepository;
    _gitClient = gitClient;
    _gitHubClient = gitHubClient;
    _baselineRepository = baselineRepository;
    _projectId = projectId;
    _baselineVersion = baselineVersion;
    _projectName = projectName;
    _executionContextCapRepository = executionContextCapRepository;
    _filterRepository = filterRepository;
    _sortRepository = sortRepository;
    _rollupRecomputer = TicketRollupRecomputer(
      _repository,
      gitProjector: gitProjector,
      projectRootPath: projectRootPath,
    );
  }

  final TicketRepository _repository;
  late final EmbeddingProvider? _embeddingProvider;
  late final TicketGitProjector? _gitProjector;
  late final String? _projectRootPath;
  /// Shared estimate/timeSpent rollup-recompute walk — see
  /// [TicketRollupRecomputer]. Wired to the same [_repository]/
  /// [_gitProjector]/[_projectRootPath] this cubit already holds.
  late final TicketRollupRecomputer _rollupRecomputer;
  late final TicketLinkRepository? _linkRepository;
  late final ProviderRegistry? _providerRegistry;
  late final CommentRepository? _commentRepository;
  late final AutomationSettingsRepository? _automationSettingsRepository;
  late final ModelRoutingRepository? _modelRoutingRepository;
  late final GitRepositoryClient? _gitClient;
  late final GitHubCliClient? _gitHubClient;
  late final BaselineRepository? _baselineRepository;
  late final String? _projectId;
  late final String? _baselineVersion;
  late final String? _projectName;
  late final ExecutionContextCapRepository? _executionContextCapRepository;
  late final TicketListFilterRepository? _filterRepository;
  late final TicketListSortRepository? _sortRepository;
  static const _uuid = Uuid();

  /// Broadcasts [CodebaseAnalysisStatus] updates as
  /// [runCodebaseSummarization] progresses. A broadcast controller (not
  /// tied to [state]) since `CodebaseAnalysisBanner` is the only
  /// subscriber and this is a transient, first-open-only concern
  /// unrelated to the ticket list's own filter/sort/pagination state.
  /// Added for `aion-arch/changes/new-project-onboarding`.
  final _codebaseAnalysisController =
      StreamController<CodebaseAnalysisStatus>.broadcast();

  /// See [_codebaseAnalysisController]'s dartdoc.
  Stream<CodebaseAnalysisStatus> get codebaseAnalysisStatus =>
      _codebaseAnalysisController.stream;

  /// The active project's display name, if this cubit was constructed
  /// with one (`app_router.dart` always supplies it). Read by
  /// `CodebaseAnalysisBanner` to name the codebase in its offer copy —
  /// `null` falls back to generic wording. Added for
  /// `aion-arch/changes/new-project-onboarding`.
  String? get projectName => _projectName;

  @override
  Future<void> close() {
    _codebaseAnalysisController.close();
    return super.close();
  }

  /// Cap on automatic corrective turns (verification fails → feed the
  /// reason back → re-implement) when the effective
  /// `AutomationContext.codingExecutionRetry` confidence is `auto`. Once
  /// exhausted, the failure is treated as `gated` regardless of the
  /// configured confidence — mirrors
  /// [_effectiveCodingExecutionConfidence]'s existing overage-forces-
  /// `gated` precedent. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`.
  static const _maxVerifyRetries = 2;

  /// The Task id of the coding-execution run currently in flight, or
  /// `null` if none is running. In-memory only — does not survive an app
  /// restart (see proposal.md's Out of scope).
  String? _inFlightExecutionTaskId;

  /// Task ids waiting behind [_inFlightExecutionTaskId], FIFO — index 0
  /// runs next.
  final List<String> _executionQueue = [];

  /// Epic/Story ids currently mid-advance (their [advanceSddStage] chat
  /// spawn hasn't finished its stage-chat turn yet), plus — once known —
  /// the id of the chat ticket that spawn is running against. Both ids
  /// for the same in-flight advance are added/removed together, so
  /// [getTicketById] can compute `isAdvancingStage` uniformly whether the
  /// currently loaded ticket is the Epic/Story itself or its freshly
  /// spawned stage chat. Unlike [_inFlightExecutionTaskId], this is a
  /// `Set`, not a single nullable id plus a FIFO queue — stage chats
  /// share no exclusive resource (no git worktree, unlike
  /// coding-execution), so multiple Epic/Story advances can run fully
  /// concurrently. In-memory only, does not survive an app restart
  /// (mirrors [_inFlightExecutionTaskId]). Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  final Set<String> _inFlightStageAdvanceIds = {};

  /// Whether an `AgentOverageDetectedEvent` has fired during any
  /// coding-execution run this session — once `true`, every subsequent
  /// completion is treated as [AutomationConfidence.gated] regardless of
  /// the configured confidence, per proposal.md's reactive-only budget
  /// handling.
  bool _overageDetectedThisSession = false;

  /// Tickets fetched per page, for both [searchTickets] and
  /// [loadMoreTickets].
  static const _pageSize = 50;

  /// The query/filters the most recent [searchTickets] call used —
  /// remembered so [loadMoreTickets] and the mutation-refresh methods
  /// below don't need the screen to pass them again.
  String? _lastQuery;
  Set<TicketStatus> _lastStatuses = const {};
  Set<TicketType> _lastTypes = const {};
  Set<TicketPriority> _lastPriorities = const {};

  /// The user's explicit sort choice for this project, once made — `null`
  /// means no explicit choice yet, so every search resolves the sort
  /// implicitly from [_implicitSort] instead. Loaded once via
  /// [loadPersistedSort], updated by [setSort]. See
  /// `aion-arch/changes/ticket-sort-control-and-board-as-default-view`.
  TicketListSort? _explicitSort;

  /// The [TicketListSort] actually used by the most recent [searchTickets]
  /// call — remembered (like [_lastQuery]/[_lastStatuses]) so
  /// [loadMoreTickets] and the mutation-refresh methods below reuse the
  /// same resolved sort rather than each re-deriving it, keeping a page's
  /// `ORDER BY` stable across a `loadMoreTickets` call.
  TicketListSort _lastSort = _implicitSort(null);

  /// The currently active sort — what the Sort control should render as
  /// selected. Resolves the same way [searchTickets] does: [_explicitSort]
  /// if one exists, otherwise the implicit query-aware default for the
  /// last-searched query.
  TicketListSort get currentSort => _explicitSort ?? _implicitSort(_lastQuery);

  /// [TicketSortField.relevance] (only meaningful with a query) while
  /// [query] is non-empty, otherwise `createdAt` descending — today's
  /// exact pre-existing default ordering, now expressed as a concrete
  /// [TicketListSort] value instead of being implicit in the repository.
  static TicketListSort _implicitSort(String? query) {
    final hasQuery = query?.trim().isNotEmpty ?? false;
    return hasQuery
        ? const TicketListSort(
            field: TicketSortField.relevance,
            // Ignored for relevance — see TicketSortField.relevance.
            direction: TicketSortDirection.descending,
          )
        : const TicketListSort(
            field: TicketSortField.createdAt,
            direction: TicketSortDirection.descending,
          );
  }

  /// Bumped on every call that replaces the list wholesale ([searchTickets],
  /// [createTicket], [updateTicketStatus], [trashTicket], [trashTickets]).
  /// A [loadMoreTickets] call in flight discards its result if this
  /// changes before it resolves — guards against a stale in-flight
  /// load-more silently appending onto a list that's since been replaced
  /// by a filter change or another mutation.
  int _searchGeneration = 0;

  /// The [TicketStatus] values currently selected in the ticket list's
  /// Filters popover — mirrors [_lastStatuses], exposed read-only for the
  /// screen/popover to render checked state and the chip row against.
  Set<TicketStatus> get selectedStatuses => _lastStatuses;

  /// The [TicketType] values currently selected in the ticket list's
  /// Filters popover. See [selectedStatuses].
  Set<TicketType> get selectedTypes => _lastTypes;

  /// The [TicketPriority] values currently selected in the ticket list's
  /// Filters popover. See [selectedStatuses].
  Set<TicketPriority> get selectedPriorities => _lastPriorities;

  /// Returns [current] with [value] toggled: removed if already present,
  /// added if absent. Shared by [toggleStatusFilter]/[toggleTypeFilter]/
  /// [togglePriorityFilter].
  Set<T> _toggleFilter<T>(Set<T> current, T value) {
    final updated = Set<T>.from(current);
    if (!updated.remove(value)) {
      updated.add(value);
    }
    return updated;
  }

  /// Persists [statuses]/[types]/[priorities] (each defaulting to the
  /// current [selectedStatuses]/[selectedTypes]/[selectedPriorities] when
  /// omitted) via [_filterRepository], scoped to [_projectId]. No-ops if
  /// either is `null` — persistence is an optional dependency, same as
  /// every other optional constructor param (see the constructor's
  /// dartdoc).
  Future<void> _persistFilters({
    Set<TicketStatus>? statuses,
    Set<TicketType>? types,
    Set<TicketPriority>? priorities,
  }) async {
    final repo = _filterRepository;
    final projectId = _projectId;
    if (repo == null || projectId == null) return;
    await repo.setFilters(
      projectId,
      TicketListFilters(
        statuses: statuses ?? _lastStatuses,
        types: types ?? _lastTypes,
        priorities: priorities ?? _lastPriorities,
      ),
    );
  }

  /// Toggles [status] in the ticket list's status filter selection —
  /// removes it if already selected, adds it if not. Persists the
  /// updated selection (see [_persistFilters]), then re-runs
  /// [searchTickets] with the updated statuses and [selectedTypes]/
  /// [selectedPriorities] unchanged, reusing the last text query.
  Future<void> toggleStatusFilter(TicketStatus status) async {
    final updated = _toggleFilter(_lastStatuses, status);
    await _persistFilters(statuses: updated);
    await searchTickets(
      query: _lastQuery,
      statuses: updated,
      types: _lastTypes,
      priorities: _lastPriorities,
    );
  }

  /// Toggles [type] in the ticket list's type filter selection — removes
  /// it if already selected, adds it if not. Persists the updated
  /// selection (see [_persistFilters]), then re-runs [searchTickets] with
  /// the updated types and [selectedStatuses]/[selectedPriorities]
  /// unchanged, reusing the last text query.
  Future<void> toggleTypeFilter(TicketType type) async {
    final updated = _toggleFilter(_lastTypes, type);
    await _persistFilters(types: updated);
    await searchTickets(
      query: _lastQuery,
      statuses: _lastStatuses,
      types: updated,
      priorities: _lastPriorities,
    );
  }

  /// Toggles [priority] in the ticket list's priority filter selection —
  /// removes it if already selected, adds it if not. Persists the
  /// updated selection (see [_persistFilters]), then re-runs
  /// [searchTickets] with the updated priorities and [selectedStatuses]/
  /// [selectedTypes] unchanged, reusing the last text query.
  Future<void> togglePriorityFilter(TicketPriority priority) async {
    final updated = _toggleFilter(_lastPriorities, priority);
    await _persistFilters(priorities: updated);
    await searchTickets(
      query: _lastQuery,
      statuses: _lastStatuses,
      types: _lastTypes,
      priorities: updated,
    );
  }

  /// Reads this project's persisted [TicketListFilters] (via
  /// [_filterRepository]/[_projectId]) into [_lastStatuses]/[_lastTypes]/
  /// [_lastPriorities], without emitting a state — meant to be awaited
  /// once, before the screen's own first [searchTickets] call, so that
  /// first call already carries the restored selection instead of
  /// flashing an unfiltered list first. No-ops if [_filterRepository] or
  /// [_projectId] is `null`.
  Future<void> loadPersistedFilters() async {
    final repo = _filterRepository;
    final projectId = _projectId;
    if (repo == null || projectId == null) return;
    final filters = await repo.getFilters(projectId);
    _lastStatuses = filters.statuses;
    _lastTypes = filters.types;
    _lastPriorities = filters.priorities;
  }

  /// Sets [sort] as this project's explicit sort override, persists it
  /// (see [_sortRepository]/[_projectId] — no-ops the persistence half if
  /// either is `null`, same optional-dependency pattern as
  /// [_persistFilters]), then re-runs [searchTickets] with the current
  /// query/filters unchanged so the reordered list reflects immediately.
  Future<void> setSort(TicketListSort sort) async {
    _explicitSort = sort;
    final repo = _sortRepository;
    final projectId = _projectId;
    if (repo != null && projectId != null) {
      await repo.setSort(projectId, sort);
    }
    await searchTickets(
      query: _lastQuery,
      statuses: _lastStatuses,
      types: _lastTypes,
      priorities: _lastPriorities,
    );
  }

  /// Reads this project's persisted [TicketListSort] (if any) into
  /// [_explicitSort], without emitting a state — same
  /// load-before-first-search precedent as [loadPersistedFilters], called
  /// alongside it from `TicketsListScreen._initializeAndSearch`. No-ops if
  /// [_sortRepository] or [_projectId] is `null`, or nothing was
  /// persisted yet (leaves [_explicitSort] `null`, i.e. implicit default).
  Future<void> loadPersistedSort() async {
    final repo = _sortRepository;
    final projectId = _projectId;
    if (repo == null || projectId == null) return;
    _explicitSort = await repo.getSort(projectId);
  }

  /// Pulls the current tickets and [TicketsState]-carried `hasMore` out of
  /// [s], for every state [loadMoreTickets] can sensibly extend. Returns
  /// `null` for [TicketsLoadingMore] (a load-more is already in flight —
  /// this is what makes [loadMoreTickets] a no-op while one is pending,
  /// with no separate debounce timer needed) and for every non-list state.
  ({List<Ticket> tickets, bool hasMore})? _listSnapshot(TicketsState s) =>
      switch (s) {
        TicketsLoaded(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        TicketCreated(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        TicketStatusUpdated(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        TicketsBatchTrashed(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        TicketsLoadMoreFailed(:final tickets, :final hasMore) => (
          tickets: tickets,
          hasMore: hasMore,
        ),
        _ => null,
      };

  /// Fetches the first page of tickets matching every filter — see
  /// [TicketRepository.searchTickets] for the OR-within-field/AND-across-
  /// field semantics. Called with no arguments, this is equivalent to
  /// fetching every ticket (most recent first). Remembers [query]/
  /// [statuses]/[types]/[priorities] internally for [loadMoreTickets] and
  /// the mutation-refresh methods below, and bumps the internal
  /// generation counter so a [loadMoreTickets] call already in flight
  /// from a previous filter state is discarded (not appended onto the
  /// new list) when it resolves. Also resolves [_lastSort] — [_explicitSort]
  /// if the user has made a choice, otherwise [_implicitSort] applied to
  /// [query] — and passes it to the repository call, so the effective
  /// sort always matches [currentSort]. Emits [TicketsLoading] first only when
  /// nothing is on screen yet ([TicketsInitial]/[TicketsError]/
  /// [TicketTrashed]) — once a ticket list is already showing, the
  /// previous list stays visible until the new results arrive, so
  /// re-searching/re-filtering doesn't flash a spinner over the existing
  /// list on every keystroke. Emits [TicketsLoaded] on success (with
  /// [TicketsLoaded.blockedTicketIds] freshly computed via
  /// [_computeBlockedTicketIds]), [TicketsError] if the repository call
  /// throws.
  Future<void> searchTickets({
    String? query,
    Set<TicketStatus> statuses = const {},
    Set<TicketType> types = const {},
    Set<TicketPriority> priorities = const {},
  }) async {
    final generation = ++_searchGeneration;
    _lastQuery = query;
    _lastStatuses = statuses;
    _lastTypes = types;
    _lastPriorities = priorities;
    _lastSort = _explicitSort ?? _implicitSort(query);

    final hasVisibleList = switch (state) {
      TicketsLoaded() ||
      TicketCreating() ||
      TicketCreated() ||
      TicketStatusUpdating() ||
      TicketStatusUpdated() ||
      TicketsBatchTrashed() ||
      TicketsLoadingMore() ||
      TicketsLoadMoreFailed() => true,
      _ => false,
    };
    if (!hasVisibleList) emit(const TicketsLoading());

    try {
      final page = await _repository.searchTickets(
        query: query,
        statuses: statuses,
        types: types,
        priorities: priorities,
        sort: _lastSort,
        limit: _pageSize,
      );
      if (generation != _searchGeneration) return;
      final blockedTicketIds = await _computeBlockedTicketIds(page.tickets);
      if (generation != _searchGeneration) return;
      emit(
        TicketsLoaded(
          page.tickets,
          hasMore: page.hasMore,
          blockedTicketIds: blockedTicketIds,
        ),
      );
    } catch (e) {
      if (generation != _searchGeneration) return;
      emit(TicketsError(e.toString()));
    }
  }

  /// Fetches the next page for whatever query/filters/[_lastSort]
  /// [searchTickets] was last called with, appending to the currently
  /// loaded list — reusing [_lastSort] rather than re-resolving it keeps
  /// a page's `ORDER BY` stable across the scroll. No-ops if
  /// the cubit isn't in a settled list-shaped state with more results
  /// available (covers: nothing loaded yet, a load-more already in
  /// flight, or the last page already reached the end) — this doubles as
  /// the concurrency guard against a fast/bouncy scroll firing the
  /// trigger multiple times before the first request resolves. Emits
  /// [TicketsLoadingMore] (carrying the tickets loaded so far)
  /// immediately, then [TicketsLoaded] (carrying the combined list, with
  /// [TicketsLoaded.blockedTicketIds] freshly computed via
  /// [_computeBlockedTicketIds]) on success, or [TicketsLoadMoreFailed]
  /// (carrying the tickets loaded so far, unchanged) if the repository
  /// call throws — the existing rows are never discarded by a failed
  /// load-more.
  Future<void> loadMoreTickets() async {
    final snapshot = _listSnapshot(state);
    if (snapshot == null || !snapshot.hasMore) return;

    final currentTickets = snapshot.tickets;
    final generation = _searchGeneration;
    emit(TicketsLoadingMore(currentTickets));

    try {
      final page = await _repository.searchTickets(
        query: _lastQuery,
        statuses: _lastStatuses,
        types: _lastTypes,
        priorities: _lastPriorities,
        sort: _lastSort,
        limit: _pageSize,
        offset: currentTickets.length,
      );
      if (generation != _searchGeneration) return;
      final combined = [...currentTickets, ...page.tickets];
      final blockedTicketIds = await _computeBlockedTicketIds(combined);
      if (generation != _searchGeneration) return;
      emit(
        TicketsLoaded(
          combined,
          hasMore: page.hasMore,
          blockedTicketIds: blockedTicketIds,
        ),
      );
    } catch (e) {
      if (generation != _searchGeneration) return;
      emit(TicketsLoadMoreFailed(currentTickets, hasMore: snapshot.hasMore));
    }
  }

  /// Creates a new ticket of [type] with [title], then reloads the list.
  ///
  /// [status] always starts at [TicketStatus.backlog]. [complexity]
  /// defaults to `null` (unset), matching [Ticket.complexity]'s own
  /// default. [severity]/[stepsToReproduce]/[expectedBehavior]/
  /// [actualBehavior] are meaningful only when [type] is
  /// [TicketType.bug]; `null` (unset) for every other type, matching
  /// [Ticket.severity] etc.'s own defaults. Emits
  /// [TicketCreating] (carrying the list as it was before this call) then
  /// [TicketCreated] (carrying the refreshed page) on success, or
  /// [TicketsError] if the repository call throws. The refresh re-applies
  /// the filters [searchTickets] was last called with (rather than
  /// fetching every ticket) and requests at least as many tickets as were
  /// already loaded, so this doesn't silently drop an active search/filter
  /// or collapse an infinite-scrolled list back down to one page.
  ///
  /// @returns the persisted ticket (with its generated `ticketId`) on
  /// success. Existing callers (`CreateTicketScreen`) are unaffected by
  /// this return value and may continue to ignore it — added so
  /// `PageTicketProviderImpl.createPage` can hand the created ticket back
  /// through `PageTicketProvider` without a second query. Rethrows the
  /// original exception after emitting [TicketsError] on failure, so a
  /// caller that does await this (e.g. `PageTicketProviderImpl`) sees the
  /// failure rather than a value of the wrong type.
  Future<Ticket> createTicket({
    required TicketType type,
    required String title,
    String? description,
    TicketPriority priority = TicketPriority.none,
    String? parentId,
    TicketComplexity? complexity,
    TicketSeverity? severity,
    String? stepsToReproduce,
    String? expectedBehavior,
    String? actualBehavior,
  }) async {
    _searchGeneration++;
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreating(:final tickets) => tickets,
      TicketStatusUpdating(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };

    emit(TicketCreating(currentTickets));
    try {
      final now = DateTime.now();
      final ticket = Ticket(
        id: _uuid.v4(),
        ticketId: '',
        complexity: complexity,
        severity: severity,
        stepsToReproduce: stepsToReproduce,
        expectedBehavior: expectedBehavior,
        actualBehavior: actualBehavior,
        type: type,
        title: title,
        description: description,
        status: TicketStatus.backlog,
        priority: priority,
        parentId: parentId,
        createdAt: now,
        updatedAt: now,
      );

      await _repository.createTicket(ticket);
      final persisted = await _repository.getTicketById(ticket.id);
      if (persisted != null) {
        // Always regenerate on create (no prior title/description to
        // compare against), fire-and-forget.
        unawaited(_triggerEmbeddingRegen(persisted));
        unawaited(_triggerGitProjection(persisted, 'created'));
      }
      final page = await _repository.searchTickets(
        query: _lastQuery,
        statuses: _lastStatuses,
        types: _lastTypes,
        priorities: _lastPriorities,
        sort: _lastSort,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(TicketCreated(page.tickets, hasMore: page.hasMore));
      return persisted ?? ticket;
    } catch (e) {
      emit(TicketsError(e.toString()));
      rethrow;
    }
  }

  /// Moves ticket [id] to [status]. Emits [TicketStatusUpdating] (carrying
  /// the list with [id]'s status optimistically replaced) immediately,
  /// then [TicketStatusUpdated] (carrying the re-fetched page) once the
  /// repository call succeeds, or [TicketsError] if it throws. The
  /// refresh re-applies the filters [searchTickets] was last called with
  /// and requests at least as many tickets as were already loaded, so a
  /// background status update (e.g. a board drag) never collapses an
  /// infinite-scrolled list back down to one page. Moving [id] to
  /// [TicketStatus.inProgress] first runs
  /// [_interceptBlockedDependencyTrigger] — every ticket type is
  /// rejected if it has an unresolved `blocks`/`blockedBy` dependency —
  /// then, if [id] is a Task or Bug (see
  /// `TicketTypeHierarchy.isExecutable`), [_interceptTaskExecutionTrigger].
  /// A rejection from either skips the write entirely (emitting the
  /// classified error + a re-emitted detail state instead of the usual
  /// list-shaped states); an allowed transition proceeds as normal, then
  /// [_triggerOrQueueCodingExecution] starts (or queues) the
  /// coding-execution run once the write succeeds. Also calls
  /// [_refreshBlockedBoardState] on success, since [id] may be another
  /// ticket's blocker.
  Future<void> updateTicketStatus(String id, TicketStatus status) async {
    // Only fetch the ticket up front when the status is the one the
    // interceptors can actually reject (inProgress) — every other
    // transition returns true immediately, so skip the extra round trip
    // other status changes (e.g. a plain board drag) don't need.
    if (status == TicketStatus.inProgress) {
      final target = await _repository.getTicketById(id);
      if (target != null) {
        if (!(await _interceptBlockedDependencyTrigger(target, status))) {
          return;
        }
        if (!(await _interceptTaskExecutionTrigger(target, status))) {
          return;
        }
      }
    }

    _searchGeneration++;
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdating(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };

    final optimistic = [
      for (final t in currentTickets)
        if (t.id == id) t.copyWith(status: status) else t,
    ];
    emit(TicketStatusUpdating(optimistic));

    try {
      await _repository.updateTicketStatus(id, status);
      final updated = await _repository.getTicketById(id);
      if (updated != null) {
        unawaited(_triggerGitProjection(updated, 'status-changed'));
        if (updated.type.isExecutable && status == TicketStatus.inProgress) {
          unawaited(_triggerOrQueueCodingExecution(updated));
        }
      }
      final page = await _repository.searchTickets(
        query: _lastQuery,
        statuses: _lastStatuses,
        types: _lastTypes,
        priorities: _lastPriorities,
        sort: _lastSort,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(TicketStatusUpdated(page.tickets, hasMore: page.hasMore));
      unawaited(_refreshBlockedBoardState());
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Persists every editable field of [ticket] via
  /// [TicketRepository.updateTicket], then re-fetches and emits
  /// [TicketDetailLoaded] with the refreshed ticket. Emits [TicketsError]
  /// on failure. Unlike [updateTicketStatus], this does not emit an
  /// optimistic intermediate state — the calling `InlineEditableField`/
  /// `SelectionMenu` already renders the new value locally before the
  /// repository round trip completes, so no separate "Updating" state is
  /// needed here.
  ///
  /// @returns the refreshed ticket on success. Existing callers
  /// (`TicketDetailScreen`) are unaffected by this return value and may
  /// continue to ignore it — added so `PageTicketProviderImpl.updatePage`
  /// can hand the updated ticket back through `PageTicketProvider`
  /// without a second query. Rethrows the original exception after
  /// emitting [TicketsError] on failure, so a caller that does await
  /// this (e.g. `PageTicketProviderImpl`) sees the failure rather than a
  /// value of the wrong type.
  ///
  /// Also fires a fire-and-forget rollup recompute (see
  /// [_recomputeRollupChain]) whenever [Ticket.estimate]/[Ticket.timeSpent]
  /// actually changed — starting at [refreshed]'s own id, since an edited
  /// ticket with its own children needs its own rollup recomputed too
  /// before the walk continues upward to its ancestors.
  Future<Ticket> updateTicket(Ticket ticket) async {
    try {
      final previous = await _repository.getTicketById(ticket.id);
      await _repository.updateTicket(ticket);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
        // Only regenerate when title/description actually changed — not
        // on every field edit (e.g. a priority-only change shouldn't
        // trigger this). Git projection is deliberately not triggered
        // here — design.md's trigger events are create/status-change/
        // trash/restore, not every content edit (would be a commit
        // storm).
        if (previous == null ||
            previous.title != refreshed.title ||
            previous.description != refreshed.description) {
          unawaited(_triggerEmbeddingRegen(refreshed));
        }
        if (previous != null &&
            (previous.estimate != refreshed.estimate ||
                previous.timeSpent != refreshed.timeSpent)) {
          unawaited(_recomputeRollupChain({refreshed.id}, 'rollup updated'));
        }
      }
      return refreshed ?? ticket;
    } catch (e) {
      emit(TicketsError(e.toString()));
      rethrow;
    }
  }

  /// Changes [ticket]'s status from the ticket-detail screen. Persists via
  /// the same [TicketRepository.updateTicketStatus] the board's drag/
  /// `MoveToStatusMenu` path calls, then re-fetches and emits
  /// [TicketDetailLoaded] with the refreshed ticket — unlike
  /// [updateTicketStatus], which emits list-shaped optimistic states built
  /// for the board and would fall through `TicketDetailScreen`'s state
  /// switch. Emits [TicketsError] on failure. Moving [ticket] to
  /// [TicketStatus.inProgress] first runs
  /// [_interceptBlockedDependencyTrigger] — every ticket type is
  /// rejected if it has an unresolved `blocks`/`blockedBy` dependency —
  /// then, if [ticket] is a Task or Bug (see
  /// `TicketTypeHierarchy.isExecutable`), [_interceptTaskExecutionTrigger].
  /// A rejection from either skips the write entirely; an allowed
  /// transition proceeds as normal, then [_triggerOrQueueCodingExecution]
  /// starts (or queues) the coding-execution run once the write succeeds.
  Future<void> changeTicketStatus(Ticket ticket, TicketStatus status) async {
    if (!(await _interceptBlockedDependencyTrigger(ticket, status))) return;
    if (!(await _interceptTaskExecutionTrigger(ticket, status))) return;
    try {
      await _repository.updateTicketStatus(ticket.id, status);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
        unawaited(_triggerGitProjection(refreshed, 'status-changed'));
        if (refreshed.type.isExecutable && status == TicketStatus.inProgress) {
          unawaited(_triggerOrQueueCodingExecution(refreshed));
        }
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Returns every ticket that [ticket] could validly be reparented under:
  /// all tickets except [ticket] itself, any of its descendants
  /// (reachable by walking `parentId` forward, since either would create a
  /// cycle), and any candidate whose type cannot structurally parent
  /// [ticket]'s type per [TicketTypeHierarchy.canParent]. Performs a query
  /// only — does not emit a state, since this feeds a picker overlay
  /// rather than driving the detail screen's own render state.
  Future<List<Ticket>> getValidParentCandidates(Ticket ticket) async {
    final all = await _repository.getAllTickets();
    final descendantIds = _descendantIds(ticket.id, all);
    return all
        .where(
          (t) =>
              t.id != ticket.id &&
              !descendantIds.contains(t.id) &&
              t.type.canParent(ticket.type),
        )
        .toList();
  }

  /// Returns every ticket in the workspace, for pickers that need the
  /// full candidate set with no self/descendant exclusion (e.g. the
  /// create-ticket parent field, where the ticket being created doesn't
  /// exist yet). Performs a query only — does not emit a state.
  Future<List<Ticket>> getAllTickets() => _repository.getAllTickets();

  /// Returns every ticket whose type may structurally parent [childType]
  /// per [TicketTypeHierarchy.canParent], for the create-ticket parent
  /// field — where the ticket being created doesn't exist yet, so there is
  /// no id to derive self/descendant exclusions from. Performs a query
  /// only — does not emit a state.
  Future<List<Ticket>> getValidParentCandidatesForType(
    TicketType childType,
  ) async {
    final all = await _repository.getAllTickets();
    return all.where((t) => t.type.canParent(childType)).toList();
  }

  /// Reassigns [ticket]'s parent to [newParentId] (`null` clears it).
  /// Rejects self-parenting and cycles locally — without calling the
  /// repository — by re-deriving the same descendant set
  /// [getValidParentCandidates] would, then emits
  /// [TicketsError] with [TicketsErrorReason.invalidParent] followed
  /// immediately by a re-emitted [TicketDetailLoaded] (same pattern as
  /// [deleteTicket]'s `hasChildren` handling), so the detail screen shows
  /// a toast rather than collapsing to the generic error view. Also
  /// rejects any attempt to set a non-null parent on a ticket whose type
  /// is always a subtree root ([TicketType.epic], [TicketType.signal], or
  /// [TicketType.release] — see [TicketTypeHierarchy.isAlwaysRoot]) — and
  /// any candidate parent whose type cannot structurally parent [ticket]'s
  /// type per [TicketTypeHierarchy.canParent], via the same rejection
  /// path. A second, instance-level (not type-level) rejection applies to
  /// an Inbox-spawned chat: a ticket with `type == TicketType.chat` and a
  /// non-null `Ticket.inboxPurpose` is also rejected for any non-null
  /// [newParentId], since [TicketTypeHierarchy.isAlwaysRoot] has no way to
  /// express "only when this specific ticket came from the Inbox" — every
  /// other `chat` ticket keeps its existing, unrestricted reparent
  /// behavior. On a valid reparent, persists via
  /// [TicketRepository.updateTicketParent] and emits the refreshed
  /// [TicketDetailLoaded]. Also fires a fire-and-forget rollup recompute
  /// (see [_recomputeRollupChain]) seeded from `{ticket.id, oldParentId}`
  /// — walking up from `ticket.id` against the post-write tree reaches
  /// the *new* parent chain (its `parentId` now points there), while
  /// `oldParentId` (captured before the write) is walked separately to
  /// reach the *old* parent chain directly, since post-write nothing else
  /// points there anymore.
  Future<void> updateTicketParent(Ticket ticket, String? newParentId) async {
    final oldParentId = ticket.parentId;
    if (newParentId != null) {
      if (newParentId == ticket.id) {
        await _emitInvalidParent(ticket.id);
        return;
      }
      if (ticket.type.isAlwaysRoot) {
        await _emitInvalidParent(ticket.id);
        return;
      }
      if (ticket.type == TicketType.chat && ticket.inboxPurpose != null) {
        await _emitInvalidParent(ticket.id);
        return;
      }
      final all = await _repository.getAllTickets();
      final descendantIds = _descendantIds(ticket.id, all);
      if (descendantIds.contains(newParentId)) {
        await _emitInvalidParent(ticket.id);
        return;
      }
      final candidateParent = await _repository.getTicketById(newParentId);
      if (candidateParent == null ||
          !candidateParent.type.canParent(ticket.type)) {
        await _emitInvalidParent(ticket.id);
        return;
      }
    }

    try {
      await _repository.updateTicketParent(ticket.id, newParentId);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
      }
      unawaited(
        _recomputeRollupChain({
          ticket.id,
          ?oldParentId,
        }, 'rollup updated'),
      );
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Emits the rejected-reparent error for ticket [ticketId], then
  /// re-emits its unchanged [TicketDetailLoaded] so the detail screen
  /// shows a toast instead of collapsing to the generic error view.
  Future<void> _emitInvalidParent(String ticketId) async {
    emit(const TicketsError('', reason: TicketsErrorReason.invalidParent));
    final ticket = await _repository.getTicketById(ticketId);
    if (ticket != null) {
      emit(TicketDetailLoaded(ticket));
    }
  }

  /// Advances [ticket]'s [Ticket.sddStage] to the next stage, after
  /// checking that stage's precondition. Rejects (emits
  /// [TicketsError] with [TicketsErrorReason.sddStagePreconditionNotMet],
  /// then re-emits [TicketDetailLoaded], mirroring [_emitInvalidParent])
  /// if `ticket.type` is not [TicketType.epic]/[TicketType.story], the
  /// ticket has already reached [SddStage.archived], or the precondition
  /// for the current → next transition isn't met yet:
  ///
  /// - `null` → [SddStage.exploring]: no precondition, any epic/story may
  ///   start.
  /// - [SddStage.exploring] → [SddStage.proposed]: the ticket's most
  ///   recently created `chat` child has at least one [CommentAuthorType.ai]
  ///   comment (i.e. isn't mid-run).
  /// - [SddStage.proposed] → [SddStage.verifying]: every direct child at
  ///   the next rank down (Tasks for a story, Stories for an epic) has
  ///   reached a terminal state ([TicketStatus.done] for a Task,
  ///   [SddStage.archived] for a Story) — and at least one such child
  ///   exists.
  /// - [SddStage.verifying] → [SddStage.archived]: same chat-reply check
  ///   as exploring → proposed, against the most recent `chat` child.
  ///
  /// On success: persists the new stage via
  /// [TicketRepository.updateTicketSddStage], re-emits
  /// [TicketDetailLoaded] (so the tracker/current-stage line updates
  /// immediately), then creates the next stage's chat (see
  /// [_createStageChat]) and backgrounds its AI turn (see
  /// [_runStageChatTurn]) unless the new stage is [SddStage.archived]
  /// (nothing to spawn after Archival). No-ops (returns `null` without
  /// starting a second concurrent spawn) if [ticket.id] is already in
  /// [_inFlightStageAdvanceIds] — a double-tap/rebuild race.
  ///
  /// @returns the spawned chat ticket's id once it has been persisted,
  /// so a caller (`TicketDetailScreen`'s Advance button handlers) can
  /// navigate straight to it; `null` when nothing was spawned (the new
  /// stage is [SddStage.archived]) or nothing to advance (a rejection
  /// already emitted [TicketsError]). Unlike before
  /// `aion-arch/changes/board-execution-indicators-and-notifications`,
  /// this now resolves once the chat ticket exists — **not** once its
  /// first AI reply has landed; [isAdvancingStage] stays `true` on both
  /// the Epic/Story and the freshly created chat ticket until
  /// [_runStageChatTurn] finishes.
  Future<String?> advanceSddStage(Ticket ticket) async {
    if (ticket.type != TicketType.epic && ticket.type != TicketType.story) {
      await _emitSddStagePreconditionNotMet(ticket.id);
      return null;
    }
    if (_inFlightStageAdvanceIds.contains(ticket.id)) {
      return null;
    }

    final nextStage = await _nextSddStage(ticket);
    if (nextStage == null) {
      await _emitSddStagePreconditionNotMet(ticket.id);
      return null;
    }
    if (!(await _sddStageAdvanceCheck(ticket)).canAdvance) {
      await _emitSddStagePreconditionNotMet(ticket.id);
      return null;
    }

    try {
      await _repository.updateTicketSddStage(ticket.id, nextStage);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed == null) return null;
      if (nextStage == SddStage.archived) {
        emit(TicketDetailLoaded(refreshed));
        return null;
      }

      _inFlightStageAdvanceIds.add(ticket.id);
      emit(TicketDetailLoaded(refreshed, isAdvancingStage: true));
      _refreshInFlightBoardState();

      final chatId = await _createStageChat(refreshed, nextStage);
      if (chatId == null) {
        _inFlightStageAdvanceIds.remove(ticket.id);
        _refreshInFlightBoardState();
        return null;
      }
      _inFlightStageAdvanceIds.add(chatId);
      unawaited(_runStageChatTurn(refreshed, nextStage, chatId));
      return chatId;
    } catch (e) {
      _inFlightStageAdvanceIds.remove(ticket.id);
      emit(TicketsError(e.toString()));
      return null;
    }
  }

  /// Promotes [signal] into an epic or a bug (per [targetType]): if
  /// [existingTicketId] is given, links [signal] to that ticket via
  /// [TicketLinkRepository.createLink] (as [TicketLinkType.relatesTo]);
  /// otherwise creates a new [targetType] ticket copying
  /// `signal.title`/`description`, then links the two the same way. Does
  /// not delete or change [signal]'s own type or status — promotion is a
  /// link, not a conversion, consistent with `release`'s existing
  /// cross-cutting-link precedent. Emits [TicketsError] (raw message, no
  /// classified reason — these guards are defensive, since the UI only
  /// ever calls this for a `signal` ticket with [targetType] set to
  /// [TicketType.epic] or [TicketType.bug]) if `signal.type` isn't
  /// [TicketType.signal], or if [targetType] is neither
  /// [TicketType.epic] nor [TicketType.bug]. No-ops (does not touch the
  /// repository) if constructed without a [TicketLinkRepository] (see
  /// the constructor's dartdoc).
  Future<void> promoteSignal(
    Ticket signal, {
    required TicketType targetType,
    String? existingTicketId,
  }) async {
    if (signal.type != TicketType.signal) {
      emit(TicketsError('Only signal tickets can be promoted.'));
      final ticket = await _repository.getTicketById(signal.id);
      if (ticket != null) {
        emit(TicketDetailLoaded(ticket));
      }
      return;
    }
    if (targetType != TicketType.epic && targetType != TicketType.bug) {
      emit(TicketsError('Signals can only be promoted to an epic or a bug.'));
      final ticket = await _repository.getTicketById(signal.id);
      if (ticket != null) {
        emit(TicketDetailLoaded(ticket));
      }
      return;
    }

    final linkRepo = _linkRepository;
    if (linkRepo == null) return;

    try {
      String targetId;
      if (existingTicketId != null) {
        targetId = existingTicketId;
      } else {
        final now = DateTime.now();
        final target = Ticket(
          id: _uuid.v4(),
          ticketId: '',
          type: targetType,
          title: signal.title,
          description: signal.description,
          status: TicketStatus.backlog,
          createdAt: now,
          updatedAt: now,
        );
        await _repository.createTicket(target);
        targetId = target.id;
      }
      await linkRepo.createLink(
        sourceTicketId: signal.id,
        targetTicketId: targetId,
        linkType: TicketLinkType.relatesTo,
      );
      final refreshed = await _repository.getTicketById(signal.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Re-runs [SddStage.designSync]'s validation in place, after the
  /// human has edited the linked design Page to address a `DESIGN GATE:
  /// PENDING` verdict. Re-assembles fresh context (the Page's *current*
  /// content — unlike a plain user chat reply, which wouldn't
  /// automatically pick up an edit made outside the chat) and posts
  /// another turn to the existing [designSyncChat], via the same
  /// [ChatCubit.runChatTurn] helper [_spawnStageChat] uses. No-ops
  /// (returns without posting) if [designSyncChat] isn't a `chat`
  /// ticket, its parent isn't at [SddStage.designSync], or the cubit was
  /// constructed without a [ProviderRegistry]/[CommentRepository] (see
  /// the constructor's dartdoc). Added for
  /// `aion-arch/changes/sdd-design-gate`.
  Future<void> retryDesignSync(Ticket designSyncChat) async {
    if (designSyncChat.type != TicketType.chat) return;
    final providerRegistry = _providerRegistry;
    final commentRepo = _commentRepository;
    if (providerRegistry == null || commentRepo == null) return;
    final parentId = designSyncChat.parentId;
    if (parentId == null) return;
    final parent = await _repository.getTicketById(parentId);
    if (parent == null || parent.sddStage != SddStage.designSync) return;

    final context = await _assembleStageContext(parent, SddStage.designSync);
    await commentRepo.addComment(
      TicketComment(
        id: '',
        ticketId: designSyncChat.id,
        content: context,
        authorType: CommentAuthorType.system,
        createdAt: DateTime.now(),
      ),
    );
    final (model, provider) = await _resolveModelAndProvider(
      SddStage.designSync.modelPhase,
    );
    await ChatCubit.runChatTurn(
      client: provider.client,
      provider: provider,
      commentRepo: commentRepo,
      chatTicketId: designSyncChat.id,
      prompt: context,
      model: model,
    );
  }

  /// Emits the rejected-stage-advance error for ticket [ticketId], then
  /// re-emits its unchanged [TicketDetailLoaded] so the detail screen
  /// shows a toast instead of collapsing to the generic error view.
  /// Mirrors [_emitInvalidParent].
  Future<void> _emitSddStagePreconditionNotMet(String ticketId) async {
    emit(
      const TicketsError(
        '',
        reason: TicketsErrorReason.sddStagePreconditionNotMet,
      ),
    );
    final ticket = await _repository.getTicketById(ticketId);
    if (ticket != null) {
      emit(TicketDetailLoaded(ticket));
    }
  }

  /// The next [SddStage] after [ticket]'s current one, or `null` if
  /// already [SddStage.archived] (nothing further to advance to). Async
  /// because the `proposed → ?` branch must inspect [ticket]'s child
  /// Tasks (via [TicketRepository.getTicketsByParent]) to decide between
  /// [SddStage.designBrief] and [SddStage.verifying] for a `story` —
  /// see [_storyNeedsDesignReview]. An `epic` always skips straight to
  /// [SddStage.verifying], since [SddStage.designBrief]/
  /// [SddStage.designSync] only ever apply to `story` tickets. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  Future<SddStage?> _nextSddStage(Ticket ticket) async {
    switch (ticket.sddStage) {
      case null:
        return SddStage.exploring;
      case SddStage.exploring:
        return SddStage.proposed;
      case SddStage.proposed:
        if (ticket.type != TicketType.story) return SddStage.verifying;
        final tasks = await _repository.getTicketsByParent(
          ticket.id,
          types: TicketTypeHierarchy.executableTypes,
        );
        return _storyNeedsDesignReview(tasks)
            ? SddStage.designBrief
            : SddStage.verifying;
      case SddStage.designBrief:
        return SddStage.designSync;
      case SddStage.designSync:
        return SddStage.verifying;
      case SddStage.verifying:
        return SddStage.archived;
      case SddStage.archived:
        return null;
    }
  }

  /// Whether any of [tasks] indicates UI work, using the same keyword
  /// heuristic `/propose`'s own design-gate block already applies to a
  /// change's touched files — here applied to each Task/Bug's title +
  /// description instead of a file path. Case-insensitive substring
  /// match against: "widget", "screen", "component", "ui". Computed
  /// fresh every time, not persisted — mirrors how the existing
  /// `proposed` precondition already re-fetches children on every check
  /// rather than caching. Added for `aion-arch/changes/sdd-design-gate`.
  bool _storyNeedsDesignReview(List<Ticket> tasks) {
    const keywords = ['widget', 'screen', 'component', 'ui'];
    return tasks.any((t) {
      final text = '${t.title} ${t.description ?? ''}'.toLowerCase();
      return keywords.any(text.contains);
    });
  }

  /// Whether [advanceSddStage] would currently succeed for [ticket],
  /// alongside — when it wouldn't — why, as an [SddStageBlockReason] for
  /// the "Not ready" hint row (`_SddStageSection`, see
  /// `aion-arch/changes/sdd-ticket-execution/design.md` §2.2). Shared by
  /// [advanceSddStage]'s own check and [getTicketById]'s
  /// [TicketDetailLoaded.canAdvanceSddStage]/
  /// [TicketDetailLoaded.sddStageBlockReason] computation, so the two
  /// can't disagree. `canAdvance` is `false` with `blockReason: null` for
  /// any type other than [TicketType.epic]/[TicketType.story], or once
  /// [SddStage.archived] is reached (nothing left to advance to, not a
  /// "blocked" state).
  Future<({bool canAdvance, SddStageBlockReason? blockReason})>
  _sddStageAdvanceCheck(Ticket ticket) async {
    if (ticket.type != TicketType.epic && ticket.type != TicketType.story) {
      return (canAdvance: false, blockReason: null);
    }
    if (await _nextSddStage(ticket) == null) {
      return (canAdvance: false, blockReason: null);
    }

    switch (ticket.sddStage) {
      case null:
        return (canAdvance: true, blockReason: null);
      case SddStage.exploring:
      case SddStage.verifying:
        final ready = await _mostRecentChatHasTerminalReply(ticket.id);
        return (
          canAdvance: ready,
          blockReason: ready ? null : SddStageBlockReason.awaitingChatReply,
        );
      case SddStage.proposed:
        // Story branch: `designBrief`/`designSync` are supposed to run
        // *before* code, so a Story needing design review only requires
        // its Tasks to exist (not be done) to reach `designBrief` — see
        // proposal.md's "Grounding correction." The skip-design branch
        // (straight to `verifying`) is unaffected: it never had a
        // pre-code stage to protect, so "Tasks done" still gates it, same
        // as the epic branch (checking child Stories archived).
        final nextRank = ticket.type == TicketType.story
            ? TicketType.task
            : TicketType.story;
        final children = await _repository.getTicketsByParent(
          ticket.id,
          types: nextRank == TicketType.task
              ? TicketTypeHierarchy.executableTypes
              : [nextRank],
        );
        final needsDesign =
            ticket.type == TicketType.story &&
            _storyNeedsDesignReview(children);
        final ready =
            children.isNotEmpty &&
            (needsDesign ||
                children.every(
                  (c) => nextRank == TicketType.task
                      ? c.status == TicketStatus.done
                      : c.sddStage == SddStage.archived,
                ));
        return (
          canAdvance: ready,
          blockReason: ready ? null : SddStageBlockReason.awaitingChildren,
        );
      case SddStage.designBrief:
        final page = await _linkedDesignPage(ticket.id);
        final ready =
            page != null && (page.description?.trim().isNotEmpty ?? false);
        return (
          canAdvance: ready,
          blockReason: ready ? null : SddStageBlockReason.awaitingDesignPaste,
        );
      case SddStage.designSync:
        // Also requires every child Task done — restoring the check to
        // the transition it always should have gated, one stage later
        // than where it was misplaced (see proposal.md's "Grounding
        // correction").
        final approved = await _designSyncApproved(ticket.id);
        final tasks = await _repository.getTicketsByParent(
          ticket.id,
          types: TicketTypeHierarchy.executableTypes,
        );
        final ready =
            approved &&
            tasks.isNotEmpty &&
            tasks.every((t) => t.status == TicketStatus.done);
        return (
          canAdvance: ready,
          blockReason: ready
              ? null
              : SddStageBlockReason.awaitingDesignApproval,
        );
      case SddStage.archived:
        return (canAdvance: false, blockReason: null);
    }
  }

  /// The `page`-type ticket linked to [storyId] whose title matches the
  /// deterministic `"Design — <title>"` naming [_spawnStageChat] gives
  /// it — identified by naming convention rather than a dedicated schema
  /// field, since no other relationship in the codebase needs one.
  /// Returns `null` if constructed without a [TicketLinkRepository]
  /// (see the constructor's dartdoc), or if no such link exists yet.
  /// Added for `aion-arch/changes/sdd-design-gate`.
  Future<Ticket?> _linkedDesignPage(String storyId) async {
    final linkRepo = _linkRepository;
    if (linkRepo == null) return null;
    final links = await linkRepo.getLinksForTicket(storyId);
    for (final link in links) {
      final otherId = link.sourceTicketId == storyId
          ? link.targetTicketId
          : link.sourceTicketId;
      final other = await _repository.getTicketById(otherId);
      if (other != null &&
          other.type == TicketType.page &&
          other.title.startsWith('Design — ')) {
        return other;
      }
    }
    return null;
  }

  /// Whether [storyId]'s `"Design Sync — "`-prefixed chat's most recent
  /// comment is an [CommentAuthorType.ai] reply whose content contains
  /// the literal line `DESIGN GATE: APPROVED` — mirrors `/design-sync`'s
  /// own final-summary line format. Unlike
  /// [_mostRecentChatHasTerminalReply] (any AI reply unlocks
  /// advancement), this checks the reply's *content*, since a `DESIGN
  /// GATE: PENDING` verdict must not unblock advancement — see
  /// [retryDesignSync] for how a fresh verdict gets produced after a
  /// `PENDING` result. Added for `aion-arch/changes/sdd-design-gate`.
  Future<bool> _designSyncApproved(String storyId) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return false;
    final chats = await _repository.getTicketsByParent(
      storyId,
      types: const [TicketType.chat],
    );
    final designSyncChats =
        chats.where((c) => c.title.startsWith('Design Sync — ')).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (designSyncChats.isEmpty) return false;
    final comments = await commentRepo.getCommentsForTicket(
      designSyncChats.first.id,
    );
    if (comments.isEmpty) return false;
    final mostRecent = comments.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    return mostRecent.authorType == CommentAuthorType.ai &&
        mostRecent.content.contains('DESIGN GATE: APPROVED');
  }

  /// Whether a Task or Bug's coding-execution run may start, built
  /// directly on the now-correctly-gated [_storyNeedsDesignReview]/
  /// [_designSyncApproved] pair — not on [SddStage] position, sidestepping
  /// [_sddStageAdvanceCheck]'s fixed bug entirely rather than depending on
  /// it being exactly right. `canStart` is always `true` when [task] has
  /// no governing Story (see [_governingStory]) or that Story's Tasks/Bugs
  /// don't indicate UI work.
  Future<({bool canStart, CodingExecutionBlockReason? reason})>
  _codingExecutionGateCheck(Ticket task) async {
    final story = await _governingStory(task);
    if (story == null) return (canStart: true, reason: null);
    final siblingTasks = await _repository.getTicketsByParent(
      story.id,
      types: TicketTypeHierarchy.executableTypes,
    );
    if (!_storyNeedsDesignReview(siblingTasks)) {
      return (canStart: true, reason: null);
    }
    final approved = await _designSyncApproved(story.id);
    return (
      canStart: approved,
      reason: approved
          ? null
          : CodingExecutionBlockReason.storyDesignGatePending,
    );
  }

  /// Walks [task]'s `parentId` up to find the nearest `story` ancestor —
  /// `null` if [task] is parentless or its nearest structural ancestor is
  /// an `epic` (a Task parented directly by an Epic, ad hoc — no Story to
  /// gate on, so it's never blocked). A Task's parent is always a Story or
  /// an Epic or nothing at all (task-under-task is disallowed by
  /// `TicketTypeHierarchy.canParent`), so this never walks more than one
  /// level up in practice, but is written as a walk for defensiveness.
  Future<Ticket?> _governingStory(Ticket task) async {
    var current = task;
    while (current.parentId != null) {
      final parent = await _repository.getTicketById(current.parentId!);
      if (parent == null) return null;
      if (parent.type == TicketType.story) return parent;
      if (parent.type == TicketType.epic) return null;
      current = parent;
    }
    return null;
  }

  /// Checked by [changeTicketStatus]/[updateTicketStatus] before their
  /// repository write, for the one status transition that can be
  /// rejected: a Task or Bug (see `TicketTypeHierarchy.isExecutable`)
  /// moving to [TicketStatus.inProgress] while [_codingExecutionGateCheck]
  /// disallows it. Every other type/status combination always returns
  /// `true` (not a trigger — proceed as normal). On rejection, emits
  /// [TicketsErrorReason.codingExecutionBlocked] then a re-emitted
  /// unchanged [TicketDetailLoaded], mirroring
  /// [_emitInvalidParent]/[_emitSddStagePreconditionNotMet], and returns
  /// `false` so the caller skips the write entirely.
  Future<bool> _interceptTaskExecutionTrigger(
    Ticket task,
    TicketStatus status,
  ) async {
    if (!task.type.isExecutable || status != TicketStatus.inProgress) {
      return true;
    }
    final check = await _codingExecutionGateCheck(task);
    if (!check.canStart) {
      emit(
        const TicketsError(
          '',
          reason: TicketsErrorReason.codingExecutionBlocked,
        ),
      );
      emit(TicketDetailLoaded(task));
      return false;
    }
    return true;
  }

  /// Gate on a ticket's move to [TicketStatus.inProgress]: rejects the
  /// transition if [ticket] currently has an unresolved `blocks`/
  /// `blockedBy` dependency ([_isTicketBlocked]). Unlike
  /// [_interceptTaskExecutionTrigger], applies to every ticket type —
  /// the Board's `_BlockedBadge` this enforces is itself type-agnostic.
  /// `true` means the transition may proceed (not blocked, or [status]
  /// isn't `inProgress` — not a gated transition). On rejection, emits
  /// [TicketsErrorReason.blockedByOpenDependency] then a re-emitted
  /// unchanged [TicketDetailLoaded], mirroring
  /// [_interceptTaskExecutionTrigger]'s exact reject shape, and returns
  /// `false` so the caller skips the write entirely. Added for
  /// `aion-arch/changes/blocked-ticket-transition-gate`.
  Future<bool> _interceptBlockedDependencyTrigger(
    Ticket ticket,
    TicketStatus status,
  ) async {
    if (status != TicketStatus.inProgress) return true;
    if (!(await _isTicketBlocked(ticket))) return true;
    emit(
      const TicketsError(
        '',
        reason: TicketsErrorReason.blockedByOpenDependency,
      ),
    );
    emit(TicketDetailLoaded(ticket));
    return false;
  }

  /// Starts [task]'s coding-execution run immediately if no other run is
  /// in flight, or appends it to [_executionQueue] (FIFO) otherwise.
  /// Called by [changeTicketStatus]/[updateTicketStatus] after a Task's
  /// status write to [TicketStatus.inProgress] succeeds.
  Future<void> _triggerOrQueueCodingExecution(Ticket task) async {
    if (_inFlightExecutionTaskId != null) {
      _executionQueue.add(task.id);
      _refreshInFlightBoardState();
      return;
    }
    _inFlightExecutionTaskId = task.id;
    _refreshInFlightBoardState();
    unawaited(_runCodingExecution(task));
  }

  /// Re-emits the current list-shaped state (`TicketsLoaded` only — a
  /// no-op while a detail screen or a mutation-in-flight state is
  /// active, since there's no Board to refresh in that case) with
  /// [TicketsLoaded.inFlightExecutionIds]/
  /// [TicketsLoaded.executionQueuePositions]/
  /// [TicketsLoaded.inFlightAdvanceIds] recomputed from
  /// [_inFlightExecutionTaskId]/[_executionQueue]/
  /// [_inFlightStageAdvanceIds]. Called at every mutation site of those
  /// three: [_triggerOrQueueCodingExecution], [_dequeueNext],
  /// [_runCodingExecution]'s completion and catch-path clears, and every
  /// [_inFlightStageAdvanceIds] mutation in [advanceSddStage]/
  /// [_runStageChatTurn] — so `TicketBoardCard` never needs to poll.
  /// Added for `aion-arch/changes/board-execution-indicators-and-notifications`.
  void _refreshInFlightBoardState() {
    final current = state;
    if (current is! TicketsLoaded) return;
    emit(
      TicketsLoaded(
        current.tickets,
        hasMore: current.hasMore,
        inFlightExecutionIds: _inFlightExecutionTaskId == null
            ? const {}
            : {_inFlightExecutionTaskId!},
        executionQueuePositions: {
          for (var i = 0; i < _executionQueue.length; i++)
            _executionQueue[i]: i + 1,
        },
        inFlightAdvanceIds: Set.unmodifiable(_inFlightStageAdvanceIds),
        blockedTicketIds: current.blockedTicketIds,
      ),
    );
  }

  /// Computes the current set of blocked work-ticket ids: a ticket whose
  /// blocking counterpart (the other side of a `blocks`/`blockedBy` row)
  /// exists, is live, and is not [TicketStatus.done]. Queries
  /// [TicketLinkRepository.getLinksByTypes] once for every live
  /// `blocks`/`blockedBy` row app-wide, resolves each row's blockee/blocker
  /// pair via [relativeLinkType] — the ticket whose relative reading of
  /// the row is [TicketLinkType.blockedBy] is the blockee, the other side
  /// is the blocker — then looks up each blocker's current status from
  /// [allTickets] (already loaded for the Board, no extra per-ticket
  /// fetch). A blocker missing from [allTickets] (trashed, or simply not
  /// loaded on this page) is treated as *not* blocking, consistent with
  /// [TicketLinkDao](../../data/daos/ticket_link_dao.dart)
  /// `.getLinksByTypes`'s live-only join. Returns `{}` if
  /// constructed without a [TicketLinkRepository]. Called by
  /// [searchTickets]/[loadMoreTickets]'s [TicketsLoaded] emission and by
  /// [_refreshBlockedBoardState]. Added for
  /// `aion-arch/changes/board-task-ordering-indication`.
  Future<Set<String>> _computeBlockedTicketIds(List<Ticket> allTickets) async {
    final linkRepo = _linkRepository;
    if (linkRepo == null) return {};

    final rows = await linkRepo.getLinksByTypes([
      TicketLinkType.blocks,
      TicketLinkType.blockedBy,
    ]);

    final byId = {for (final t in allTickets) t.id: t};
    final blocked = <String>{};
    for (final row in rows) {
      final targetIsBlockee =
          relativeLinkType(row, row.targetTicketId) == TicketLinkType.blockedBy;
      final blockeeId = targetIsBlockee
          ? row.targetTicketId
          : row.sourceTicketId;
      final blockerId = targetIsBlockee
          ? row.sourceTicketId
          : row.targetTicketId;
      if (byId[blockerId]?.status != TicketStatus.done) {
        blocked.add(blockeeId);
      }
    }
    return blocked;
  }

  /// Whether [ticket] currently has an unresolved `blocks`/`blockedBy`
  /// dependency — i.e. a live link whose [relativeLinkType] from
  /// [ticket]'s own side is [TicketLinkType.blockedBy], and whose other
  /// side either doesn't exist or isn't [TicketStatus.done]. Mirrors
  /// [_computeBlockedTicketIds]'s row-resolution (via the same
  /// [relativeLinkType] helper) but scoped to a single ticket via
  /// [TicketLinkRepository.getLinksForTicket] rather than the board-wide
  /// bulk query, since this runs once per `inProgress` transition
  /// attempt rather than once per board load. Returns `false` if
  /// constructed without a [TicketLinkRepository] (mirrors
  /// [_computeBlockedTicketIds]'s same fallback). Added for
  /// `aion-arch/changes/blocked-ticket-transition-gate`.
  Future<bool> _isTicketBlocked(Ticket ticket) async {
    final linkRepo = _linkRepository;
    if (linkRepo == null) return false;

    final rows = await linkRepo.getLinksForTicket(ticket.id);
    for (final row in rows) {
      if (relativeLinkType(row, ticket.id) != TicketLinkType.blockedBy) {
        continue;
      }
      final blockerId = row.sourceTicketId == ticket.id
          ? row.targetTicketId
          : row.sourceTicketId;
      final blocker = await _repository.getTicketById(blockerId);
      if (blocker == null || blocker.status != TicketStatus.done) {
        return true;
      }
    }
    return false;
  }

  /// Re-emits the current list-shaped state (`TicketsLoaded` only — a
  /// no-op while a detail screen or a mutation-in-flight state is active)
  /// with [TicketsLoaded.blockedTicketIds] recomputed via
  /// [_computeBlockedTicketIds] against the state's own [TicketsLoaded
  /// .tickets] — unlike [_refreshInFlightBoardState]'s in-memory-only
  /// recomputation, this reads persisted link/status data. Called after
  /// [updateTicketStatus] (a blocker's status may have just changed) and
  /// after a `blocks`/`blockedBy` link is created via the widened
  /// `TicketLinkPicker` (`ticket_metadata_section.dart`). Added for
  /// `aion-arch/changes/board-task-ordering-indication`.
  Future<void> _refreshBlockedBoardState() async {
    final current = state;
    if (current is! TicketsLoaded) return;
    final blockedTicketIds = await _computeBlockedTicketIds(current.tickets);
    emit(
      TicketsLoaded(
        current.tickets,
        hasMore: current.hasMore,
        inFlightExecutionIds: current.inFlightExecutionIds,
        executionQueuePositions: current.executionQueuePositions,
        inFlightAdvanceIds: current.inFlightAdvanceIds,
        blockedTicketIds: blockedTicketIds,
      ),
    );
  }

  /// Public wrapper around [_refreshBlockedBoardState], for callers
  /// outside this cubit that just created (or removed) a `blocks`/
  /// `blockedBy` link and need the Board's blocked-badge state
  /// recomputed — the widened `TicketLinkPicker` call site in
  /// `ticket_metadata_section.dart` is the only caller today. Added for
  /// `aion-arch/changes/board-task-ordering-indication`.
  Future<void> refreshBlockedBoardState() => _refreshBlockedBoardState();

  /// Resolves which chat [task]'s next implement/verify turn(s) post to:
  /// its existing execution chat (see [_mostRecentExecutionChat]), reused
  /// as-is; a handoff (see [_handoffExecutionChat]) to a new one if that
  /// chat has crossed [_handoffThresholdRatio] of its effective cap
  /// ([_effectiveExecutionContextCap]); or a brand-new one if [task] has
  /// no execution chat at all yet. Returns `(chat, handoffSummary)` —
  /// `handoffSummary` is non-null only right after a handoff just
  /// happened, for the caller to feed into [_assembleExecutionContext].
  /// `(null, null)` only when constructed without an [AgentModelClient]/
  /// [CommentRepository] (mirrors every other chat-spawning path's guard)
  /// or a create write fails to persist. Added for
  /// `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-trigger`.
  Future<(Ticket?, String?)> _resolveExecutionChat(Ticket task) async {
    final existing = await _mostRecentExecutionChat(task.id);
    if (existing == null) {
      final created = await _createExecutionChat(
        task,
        _executionChatTitle(task.title),
      );
      return (created, null);
    }
    if (!await _executionChatOverCap(existing)) {
      return (existing, null);
    }
    return _handoffExecutionChat(task, existing);
  }

  /// Creates a new `chat` child ticket titled [title] under [task], and
  /// re-fetches it as persisted. `null` if the create write fails to
  /// persist. Shared by [_resolveExecutionChat] (first-ever trigger) and
  /// [_handoffExecutionChat] (a continuation chat). Added for
  /// `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-trigger`.
  Future<Ticket?> _createExecutionChat(Ticket task, String title) async {
    final now = DateTime.now();
    final chat = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.chat,
      title: title,
      status: TicketStatus.backlog,
      parentId: task.id,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createTicket(chat);
    return _repository.getTicketById(chat.id);
  }

  /// `"Coding Execution — <taskTitle>"`, or a numbered `"(continued
  /// N)"`-suffixed variant per [continuationIndex] (0 = the original,
  /// unsuffixed; 1 = the first handoff, suffixed `"(continued)"` with no
  /// number; 2+ = `"(continued 2)"`, `"(continued 3)"`, ...) — resolves
  /// open question #3 from `dont-spawn-new-chat-ticket-per-execution-
  /// trigger.md`: unlike a bare repeated `"(continued)"`, a third+
  /// continuation stays distinguishable from the second. Added for
  /// `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-trigger`.
  String _executionChatTitle(String taskTitle, [int continuationIndex = 0]) {
    final base = 'Coding Execution — $taskTitle';
    if (continuationIndex <= 0) return base;
    return continuationIndex == 1
        ? '$base (continued)'
        : '$base (continued $continuationIndex)';
  }

  /// How many `"Coding Execution — "`-prefixed children [taskId] already
  /// has — the next one's [_executionChatTitle] continuation index. Added
  /// for `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-
  /// trigger`.
  Future<int> _executionChatCount(String taskId) async {
    final chats = await _repository.getTicketsByParent(
      taskId,
      types: const [TicketType.chat],
    );
    return chats.where((c) => c.title.startsWith('Coding Execution — ')).length;
  }

  /// Whether [chat]'s accumulated token usage (every comment's
  /// `inputTokens + outputTokens`, `0` for a comment with neither — a
  /// human/system comment, or an ai comment predating this change) has
  /// crossed [_handoffThresholdRatio] of [_effectiveExecutionContextCap].
  /// Added for `aion-arch/changes/dont-spawn-new-chat-ticket-per-
  /// execution-trigger`.
  Future<bool> _executionChatOverCap(Ticket chat) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return false;
    final comments = await commentRepo.getCommentsForTicket(chat.id);
    final used = comments.fold<int>(
      0,
      (sum, c) => sum + (c.inputTokens ?? 0) + (c.outputTokens ?? 0),
    );
    final cap = await _effectiveExecutionContextCap();
    return used >= cap * _handoffThresholdRatio;
  }

  /// The execution-phase model's real
  /// `AgentModelDescriptor.contextWindowTokens`, lowered to
  /// [_executionContextCapRepository]'s persisted override
  /// when one is set and it's a smaller, positive value — an override can
  /// never raise the cap past the model's real limit
  /// ([ExecutionContextCapCubit] enforces the same ceiling when
  /// persisting one, this is defense in depth). Falls back to the
  /// model's real limit with no override available when constructed
  /// without an [ExecutionContextCapRepository] (see the constructor's
  /// dartdoc). Added for `aion-arch/changes/dont-spawn-new-chat-ticket-
  /// per-execution-trigger`.
  Future<int> _effectiveExecutionContextCap() async {
    final model = await _resolveModel(ModelPhase.execution);
    final override = await _executionContextCapRepository
        ?.getContextCapOverride();
    if (override != null &&
        override > 0 &&
        override < model.contextWindowTokens) {
      return override;
    }
    return model.contextWindowTokens;
  }

  /// Fraction of [_effectiveExecutionContextCap] an execution chat's
  /// accumulated usage must cross before [_resolveExecutionChat] hands
  /// off to a new chat (see [_executionChatOverCap]). Not user-
  /// configurable (proposal.md's Out of scope) — only the cap it's a
  /// fraction of is. Added for `aion-arch/changes/dont-spawn-new-chat-
  /// ticket-per-execution-trigger`.
  static const _handoffThresholdRatio = 0.9;

  /// Retires [oldChat] and starts a new linked one for [task]: one
  /// summary-only [ChatCubit.runChatTurn] on [oldChat] (no tools, no
  /// `workingDirectory` — the worktree that turn's run owned is already
  /// gone by the time a later trigger's [_resolveExecutionChat] call gets
  /// here) asks the model to write a handoff summary from [oldChat]'s own
  /// transcript, then a new chat is created ([_createExecutionChat],
  /// [_executionChatTitle]/[_executionChatCount] for its numbered title)
  /// and linked back to [oldChat] via [TicketLinkType.relatesTo] — a
  /// human can navigate between them via the existing generic "linked
  /// tickets" UI, no new widget needed. Falls back to `(oldChat, null)` —
  /// reuse the old, now-over-cap chat rather than block the run — if the
  /// summary turn itself hard-fails, or if constructed without a
  /// [ProviderRegistry]/[CommentRepository]: a soft context-budget
  /// overrun that risks a truncated next turn is preferable to a run that
  /// can't proceed at all, matching this project's fail-open precedent
  /// for [_computeExecutionFailure]'s "ended without a clear result"
  /// stalled case.
  ///
  /// The summary turn's own usage is recorded on [oldChat]'s total (it's
  /// just another comment there) but can never trigger a second,
  /// recursive handoff — [oldChat] is retired unconditionally once this
  /// runs, regardless of that comment's size. Resolves open question #2
  /// from `dont-spawn-new-chat-ticket-per-execution-trigger.md`. Added
  /// for `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-
  /// trigger`.
  Future<(Ticket?, String?)> _handoffExecutionChat(
    Ticket task,
    Ticket oldChat,
  ) async {
    final providerRegistry = _providerRegistry;
    final commentRepo = _commentRepository;
    if (providerRegistry == null || commentRepo == null) {
      return (oldChat, null);
    }

    final transcript = _assembleChatTranscript(
      await commentRepo.getCommentsForTicket(oldChat.id),
    );
    final (model, provider) = await _resolveModelAndProvider(
      ModelPhase.execution,
    );
    final summarized = await ChatCubit.runChatTurn(
      client: provider.client,
      provider: provider,
      commentRepo: commentRepo,
      chatTicketId: oldChat.id,
      prompt: _assembleHandoffContext(transcript),
      model: model,
    );
    if (!summarized) return (oldChat, null);

    final summary = await _lastCommentContent(oldChat.id);
    final continuationIndex = await _executionChatCount(task.id);
    final newChat = await _createExecutionChat(
      task,
      _executionChatTitle(task.title, continuationIndex),
    );
    if (newChat == null) return (oldChat, null);

    final linkRepo = _linkRepository;
    if (linkRepo != null) {
      await linkRepo.createLink(
        sourceTicketId: newChat.id,
        targetTicketId: oldChat.id,
        linkType: TicketLinkType.relatesTo,
      );
    }
    return (newChat, summary);
  }

  /// Renders [comments] (a chat's full history, oldest first — matches
  /// [CommentRepository.getCommentsForTicket]'s own ordering) as a plain
  /// transcript for the handoff-summary prompt: one `[authorType]` line
  /// per comment followed by its content, blank-line separated. Added for
  /// `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-trigger`.
  String _assembleChatTranscript(List<TicketComment> comments) {
    final buffer = StringBuffer();
    for (final comment in comments) {
      buffer
        ..writeln('[${comment.authorType.name}]')
        ..writeln(comment.content)
        ..writeln();
    }
    return buffer.toString().trim();
  }

  /// The handoff-summary turn's prompt: [transcript] plus an instruction
  /// to summarize what's done/left/decided for whoever picks this Task up
  /// next in a new chat, explicitly told not to use any tools — there is
  /// no worktree for this turn to act in (see [_handoffExecutionChat]'s
  /// dartdoc). Added for `aion-arch/changes/dont-spawn-new-chat-ticket-
  /// per-execution-trigger`.
  String _assembleHandoffContext(String transcript) {
    return 'This coding-execution chat is nearing its model context '
        'limit, and a new chat will continue this Task\'s work from here. '
        'Write a handoff summary for whoever picks it up next: what has '
        'been done, what is left, and any key decisions or gotchas '
        'discovered so far. Do not use any tools — reply with the summary '
        'only.\n\n'
        '--- Transcript so far ---\n\n$transcript';
  }

  /// Runs [task]'s coding-execution turn end to end: creates an isolated
  /// `git worktree` (via [GitRepositoryClient.createWorktree]) on a fresh
  /// `aion/task-<id>` branch, finds-or-creates-or-hands-off [task]'s
  /// execution chat (see [_resolveExecutionChat]), posts the assembled
  /// context (see [_assembleExecutionContext]) as a [CommentAuthorType.system]
  /// comment, then loops an implement-then-verify pair of **model**
  /// turns: an implement [ChatCubit.runChatTurn] (model resolved via
  /// [_resolveModel]/[ModelPhase.execution], `toolsEnabled: true`,
  /// `workingDirectory` pointed at the worktree — never [_projectRootPath]
  /// itself, so the developer's real checkout is never touched), then —
  /// if that succeeded — a second `runChatTurn` in the same chat/
  /// worktree fed [_assembleVerificationContext]'s prompt (the
  /// project's effective `skills/verify` content), asking the model to
  /// check its own work using whatever tooling fits this codebase and
  /// end with a `VERIFICATION: PASSED`/`FAILED` terminal line — parsed
  /// by [_verificationFailureReason] (fail-closed: only an explicit
  /// `PASSED` line counts). On a pass, pushes the branch
  /// ([GitRepositoryClient.push]) and opens the PR itself
  /// ([GitHubCliClient.openPullRequest], no model call), posting a
  /// system comment ending `EXECUTION: PR_OPENED <url>` (the same
  /// terminal-signal convention [_executionSucceededWithPr] already
  /// looks for). If either `runChatTurn` call reports a hard failure
  /// (already persisting its own `"Execution failed: ..."` comment), the
  /// loop stops immediately — there's nothing to verify (or nothing
  /// verified) if a turn never actually completed. On a verification
  /// failure, the effective [AutomationContext.codingExecutionRetry]
  /// confidence (see [_effectiveCodingExecutionRetryConfidence]) decides
  /// whether a corrective turn (same chat, fed
  /// [_assembleCorrectiveContext]'s prompt) runs automatically, up to
  /// [_maxVerifyRetries] attempts; once retries are exhausted (forced
  /// `gated`) or the confidence was never `auto`, posts a final
  /// `"Execution failed verification: ..."` comment and stops — no PR.
  /// A `catch` around the whole worktree-setup-through-PR sequence posts
  /// an `"Execution failed: ..."` comment (same shape/detection as
  /// [ChatCubit.runChatTurn]'s own hard-error comments) for any
  /// infra-level failure —
  /// [GitRepositoryClient.createWorktree]/[GitHubCliClient.openPullRequest]/
  /// etc. throwing — so the exception can't propagate out of this
  /// `unawaited`-run method and permanently wedge
  /// [_inFlightExecutionTaskId]. The worktree (never the branch) is
  /// always removed in a `finally`, success or failure — itself wrapped
  /// in its own try/catch, since a worktree that was never actually
  /// created has nothing to remove.
  ///
  /// If a PR was confirmed (see [_executionSucceededWithPr]) and
  /// [_automationSettingsRepository] is configured, flips [task] straight
  /// to [TicketStatus.inReview] when [AutomationContext.codingExecution]'s
  /// confidence is [AutomationConfidence.auto] (forced to
  /// [AutomationConfidence.gated] for the rest of the session once
  /// [_overageDetectedThisSession] is `true`) — `gated`/`manual` leave the
  /// status as-is, for [getTicketById]'s `executionAwaitingReview`
  /// computation (or a manual status change) to surface instead.
  /// Re-emits [TicketDetailLoaded] if the detail screen was showing
  /// [task] *when the run started* — captured up front rather than
  /// re-read from `state` afterward, since an overage toast (or a live
  /// [TicketDetailLoaded.executionLiveActivity] update, see
  /// [_emitLiveExecutionActivity]) emitted mid-run would otherwise
  /// clobber `state` and make a live re-check wrongly skip the refresh.
  /// Then dequeues the next run (see [_dequeueNext]), no-opping
  /// gracefully if constructed without a [ProviderRegistry]/
  /// [CommentRepository]/[GitRepositoryClient]/[GitHubCliClient]/
  /// [BaselineRepository]/`projectId`/`baselineVersion`/`projectRootPath`
  /// (see the constructor's dartdoc).
  Future<void> _runCodingExecution(Ticket task) async {
    final providerRegistry = _providerRegistry;
    final commentRepo = _commentRepository;
    final automationRepo = _automationSettingsRepository;
    final gitClient = _gitClient;
    final gitHubClient = _gitHubClient;
    final baselineRepo = _baselineRepository;
    final projectId = _projectId;
    final baselineVersion = _baselineVersion;
    final rootPath = _projectRootPath;
    if (providerRegistry == null ||
        commentRepo == null ||
        gitClient == null ||
        gitHubClient == null ||
        baselineRepo == null ||
        projectId == null ||
        baselineVersion == null ||
        rootPath == null) {
      _inFlightExecutionTaskId = null;
      _refreshInFlightBoardState();
      unawaited(_dequeueNext());
      return;
    }

    // Captured before the run starts, not re-read from `state` afterward:
    // `onConsumptionSignal`/live-activity updates below can emit mid-run,
    // which would otherwise clobber `state` and make a live re-check
    // wrongly conclude the detail screen isn't showing [task] anymore,
    // silently skipping the refresh.
    final wasShowingTaskDetail =
        state is TicketDetailLoaded &&
        (state as TicketDetailLoaded).ticket.id == task.id;

    final worktreePath = Directory.systemTemp.createTempSync('aion_exec_').path;
    final branchName = 'aion/task-${task.id}';

    final (chat, handoffSummary) = await _resolveExecutionChat(task);
    if (chat == null) {
      _inFlightExecutionTaskId = null;
      _refreshInFlightBoardState();
      unawaited(_dequeueNext());
      return;
    }

    try {
      await gitClient.createWorktree(rootPath, worktreePath, branchName);

      var prompt = await _assembleExecutionContext(
        task,
        handoffSummary: handoffSummary,
      );
      await commentRepo.addComment(
        TicketComment(
          id: '',
          ticketId: chat.id,
          content: prompt,
          authorType: CommentAuthorType.system,
          createdAt: DateTime.now(),
        ),
      );

      // Shared by both the implement and verify turns below — same live
      // "Running <tool>..." activity feed and overage handling either way.
      void onChunk(String _) =>
          _emitLiveExecutionActivity(task.id, wasShowingTaskDetail, null);
      void onToolUse(String toolName, String? summary) =>
          _emitLiveExecutionActivity(
            task.id,
            wasShowingTaskDetail,
            summary == null
                ? 'Running $toolName...'
                : 'Running $toolName: $summary...',
          );
      void onConsumptionSignal(ConsumptionSignal _) {
        if (!_overageDetectedThisSession) {
          _overageDetectedThisSession = true;
          emit(
            const TicketsError(
              '',
              reason: TicketsErrorReason.executionBudgetOverageDetected,
            ),
          );
        }
      }

      var attempt = 0;
      var verified = false;
      while (true) {
        final (implementModel, implementProvider) =
            await _resolveModelAndProvider(ModelPhase.execution);
        final implementSucceeded = await ChatCubit.runChatTurn(
          client: implementProvider.client,
          provider: implementProvider,
          commentRepo: commentRepo,
          chatTicketId: chat.id,
          prompt: prompt,
          model: implementModel,
          toolsEnabled: true,
          workingDirectory: worktreePath,
          onChunk: onChunk,
          onToolUse: onToolUse,
          onConsumptionSignal: onConsumptionSignal,
        );
        if (!implementSucceeded) {
          // A hard error (API failure, thrown exception) — `runChatTurn`
          // already persisted an "Execution failed: ..." comment itself.
          // Don't run a verify turn against a worktree whose
          // implementation turn never actually completed.
          break;
        }

        final verifyPrompt = await _assembleVerificationContext(task);
        final (verifyModel, verifyProvider) = await _resolveModelAndProvider(
          ModelPhase.execution,
        );
        final verifySucceeded = await ChatCubit.runChatTurn(
          client: verifyProvider.client,
          provider: verifyProvider,
          commentRepo: commentRepo,
          chatTicketId: chat.id,
          prompt: verifyPrompt,
          model: verifyModel,
          toolsEnabled: true,
          workingDirectory: worktreePath,
          onChunk: onChunk,
          onToolUse: onToolUse,
          onConsumptionSignal: onConsumptionSignal,
        );
        if (!verifySucceeded) {
          // A hard error during the verify turn itself — same shape as
          // above; `runChatTurn` already posted the failure comment.
          break;
        }

        final verifyReply = await _lastCommentContent(chat.id);
        final failureReason = _verificationFailureReason(verifyReply);
        if (failureReason == null) {
          verified = true;
          break;
        }

        attempt += 1;
        final retryConfidence = await _effectiveCodingExecutionRetryConfidence(
          automationRepo,
          attempt,
        );
        if (retryConfidence == AutomationConfidence.auto) {
          prompt = _assembleCorrectiveContext(failureReason);
          continue;
        }

        await commentRepo.addComment(
          TicketComment(
            id: '',
            ticketId: chat.id,
            content: 'Execution failed verification:\n\n$failureReason',
            authorType: CommentAuthorType.system,
            createdAt: DateTime.now(),
          ),
        );
        // `manual` never surfaces proactively — the failure banner's
        // always-available retry control is the only surface. `gated`
        // (including auto-exhausted, forced to gated above) gets the
        // one-shot toast too.
        if (retryConfidence == AutomationConfidence.gated) {
          emit(
            const TicketsError(
              '',
              reason: TicketsErrorReason.executionVerificationFailed,
            ),
          );
        }
        break;
      }

      if (verified) {
        await gitClient.push(worktreePath, branchName);
        final prUrl = await gitHubClient.openPullRequest(
          rootPath: worktreePath,
          branch: branchName,
          title: task.title,
          body: 'Implements "${task.title}" via Aion coding execution.',
        );
        await commentRepo.addComment(
          TicketComment(
            id: '',
            ticketId: chat.id,
            content: 'EXECUTION: PR_OPENED $prUrl',
            authorType: CommentAuthorType.system,
            createdAt: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      // A setup/infra failure — createWorktree, push, or openPullRequest
      // throwing (see GitRepositoryClient._runChecked's dartdoc). Posts
      // the same "Execution failed: ..." shape ChatCubit.runChatTurn's own
      // hard-error path already uses, so _computeExecutionFailure's
      // existing detection picks this up with no new state needed.
      // Without this catch, the exception would propagate out of
      // _runCodingExecution uncaught (it's run via `unawaited`),
      // skipping everything below — including clearing
      // _inFlightExecutionTaskId — and permanently wedging the
      // execution queue.
      await commentRepo.addComment(
        TicketComment(
          id: '',
          ticketId: chat.id,
          content: 'Execution failed: $e',
          authorType: CommentAuthorType.system,
          createdAt: DateTime.now(),
        ),
      );
    } finally {
      try {
        await gitClient.removeWorktree(rootPath, worktreePath);
      } catch (_) {
        // Best-effort cleanup only — createWorktree may itself have
        // failed (caught above), in which case there's nothing to
        // remove. Swallowed so it never masks whichever failure (if
        // any) the catch above already recorded.
      }
    }

    final prConfirmed = await _executionSucceededWithPr(task.id);
    if (prConfirmed && automationRepo != null) {
      final confidence = await _effectiveCodingExecutionConfidence(
        automationRepo,
      );
      if (confidence == AutomationConfidence.auto) {
        await _repository.updateTicketStatus(task.id, TicketStatus.inReview);
      }
      // `gated`/`manual`: leave status as-is; getTicketById's re-check
      // surfaces the "ready for review" banner or leaves it to a manual
      // status change.
    }

    // Cleared before the refresh below (not after) so getTicketById's own
    // `isExecuting` computation correctly sees this run as finished,
    // rather than reporting the just-completed run as still in flight.
    _inFlightExecutionTaskId = null;
    _refreshInFlightBoardState();

    if (wasShowingTaskDetail) {
      await getTicketById(task.id);
    }

    unawaited(_dequeueNext());
  }

  /// Re-enters the coding-execution flow for [task] from scratch in the
  /// worktree/branch sense only — a fresh `git worktree` and branch,
  /// exactly as a first attempt would (a prior failed attempt's worktree
  /// is already removed by [_runCodingExecution] itself, and its
  /// never-pushed branch is simply abandoned). The chat itself is *not*
  /// started fresh: [_runCodingExecution] resolves it via
  /// [_resolveExecutionChat], which reuses [task]'s existing execution
  /// chat (or hands off to a new, linked one — see
  /// [_handoffExecutionChat] — if it's crossed its context-window cap)
  /// exactly as any other trigger would. The failure banner's
  /// manual-retry action, and what the `gated`/exhausted-`auto` toast
  /// (see [TicketsErrorReason.executionVerificationFailed]) links to.
  /// Added for `aion-arch/changes/coding-execution-reliability-and-safety`;
  /// dartdoc updated for `aion-arch/changes/dont-spawn-new-chat-ticket-
  /// per-execution-trigger`.
  Future<void> retryCodingExecution(Ticket task) async {
    await _triggerOrQueueCodingExecution(task);
  }

  /// Re-emits [TicketDetailLoaded] with `executionLiveActivity` set to
  /// [activity] — a live "Running `<tool>`..." status string, or `null`
  /// to clear it — but only when [wasShowingTaskDetail] is `true` and the
  /// cubit's current `state` is still [TicketDetailLoaded] for [taskId]
  /// (the run's owning Task may no longer be the screen showing by the
  /// time a mid-run tool-use/text event fires). Every other field is
  /// copied unchanged from the current state. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`.
  void _emitLiveExecutionActivity(
    String taskId,
    bool wasShowingTaskDetail,
    String? activity,
  ) {
    if (!wasShowingTaskDetail) return;
    final current = state;
    if (current is! TicketDetailLoaded || current.ticket.id != taskId) {
      return;
    }
    emit(
      TicketDetailLoaded(
        current.ticket,
        childDocs: current.childDocs,
        linkedTickets: current.linkedTickets,
        backlinks: current.backlinks,
        canAdvanceSddStage: current.canAdvanceSddStage,
        sddStageBlockReason: current.sddStageBlockReason,
        needsDesignReview: current.needsDesignReview,
        linkedDesignPage: current.linkedDesignPage,
        isExecuting: current.isExecuting,
        executionQueuePosition: current.executionQueuePosition,
        executionAwaitingReview: current.executionAwaitingReview,
        executionFailureReason: current.executionFailureReason,
        executionCanRetry: current.executionCanRetry,
        executionLiveActivity: activity,
      ),
    );
  }

  /// [automationRepo]'s persisted [AutomationContext.codingExecutionRetry]
  /// confidence for [attempt] (1-based: how many verification failures
  /// have happened so far this run), forced to
  /// [AutomationConfidence.gated] once [attempt] exceeds
  /// [_maxVerifyRetries] regardless of what's persisted — mirrors
  /// [_effectiveCodingExecutionConfidence]'s own overage-forces-`gated`
  /// precedent. Falls back to [AutomationConfidence.gated] (the safe
  /// default for a recovery action that re-spawns a tool-enabled run)
  /// when constructed without an [AutomationSettingsRepository]. Added
  /// for `aion-arch/changes/coding-execution-reliability-and-safety`.
  Future<AutomationConfidence> _effectiveCodingExecutionRetryConfidence(
    AutomationSettingsRepository? automationRepo,
    int attempt,
  ) async {
    if (attempt > _maxVerifyRetries) return AutomationConfidence.gated;
    if (automationRepo == null) return AutomationConfidence.gated;
    return automationRepo.getConfidence(AutomationContext.codingExecutionRetry);
  }

  /// [automationRepo]'s persisted [AutomationContext.codingExecution]
  /// confidence, forced to [AutomationConfidence.gated] once
  /// [_overageDetectedThisSession] is `true` regardless of what's
  /// persisted — shared by [_runCodingExecution]'s completion-flip
  /// decision and [getTicketById]'s `executionAwaitingReview`
  /// computation so the two can't disagree about whether an
  /// overage-affected run counts as gated (post-`/verify` correction:
  /// [getTicketById] originally read the repository directly, so the
  /// "ready for review" banner never appeared after an overage forced
  /// `gated` — [_runCodingExecution] correctly skipped the auto-flip, but
  /// nothing surfaced the resulting awaiting-review state instead).
  Future<AutomationConfidence> _effectiveCodingExecutionConfidence(
    AutomationSettingsRepository automationRepo,
  ) async {
    return _overageDetectedThisSession
        ? AutomationConfidence.gated
        : await automationRepo.getConfidence(AutomationContext.codingExecution);
  }

  /// Pops the next queued Task id (if any) off [_executionQueue] and
  /// starts its run via [_runCodingExecution], skipping ids that no
  /// longer resolve to a ticket (defensive — not expected in practice).
  Future<void> _dequeueNext() async {
    if (_executionQueue.isEmpty) return;
    final nextId = _executionQueue.removeAt(0);
    final next = await _repository.getTicketById(nextId);
    if (next == null) {
      // The pop above already changed _executionQueue's positions, even
      // though nothing started running — refresh so the Board doesn't
      // show a stale queue position for the ids behind the skipped one.
      _refreshInFlightBoardState();
      unawaited(_dequeueNext());
      return;
    }
    _inFlightExecutionTaskId = next.id;
    _refreshInFlightBoardState();
    unawaited(_runCodingExecution(next));
  }

  /// Resolves the effective content for baseline asset [assetKey] in the
  /// active project — its local `ProjectOverride` content if one exists,
  /// otherwise the bundled default for the project's pinned
  /// [_baselineVersion]. Returns `null` if any of [_baselineRepository]/
  /// [_projectId]/[_baselineVersion] is unset, or if [assetKey] isn't
  /// present in the pinned manifest at all (e.g. a project pinned to
  /// `0.1.0`/`0.2.0`, which predate the `conventions/
  /// architecture-conventions` key). Callers treat a `null` return as
  /// "no guidance available," not an error. Added for
  /// `aion-arch/changes/project-type-aware-conventions-and-
  /// verification` — the narrowly-scoped mechanism
  /// [_assembleExecutionContext]/[_assembleVerificationContext] use to
  /// read `conventions/architecture-conventions`/`skills/verify`
  /// content into a coding-execution prompt; no other prompt in this
  /// class consults [_baselineRepository].
  Future<String?> _effectiveAssetContent(String assetKey) async {
    final baselineRepo = _baselineRepository;
    final projectId = _projectId;
    final baselineVersion = _baselineVersion;
    if (baselineRepo == null || projectId == null || baselineVersion == null) {
      return null;
    }

    final manifest = await baselineRepo.getManifest(baselineVersion);
    BaselineAsset? asset;
    for (final candidate in manifest.assets) {
      if (candidate.key == assetKey) {
        asset = candidate;
        break;
      }
    }
    if (asset == null) return null;

    final overrides = await baselineRepo.readOverrides(projectId);
    for (final override in overrides) {
      if (override.assetKey == assetKey) {
        return baselineRepo.readOverrideContent(override.overridePath);
      }
    }
    return baselineRepo.readBundledContent(asset);
  }

  /// Assembles the plain-text context a spawned coding-execution chat
  /// opens with: [task]'s title/description, the project's effective
  /// `conventions/architecture-conventions` content (see
  /// [_effectiveAssetContent]) if any, plus an instruction to implement
  /// the task using the available file, git, and bash tools, commit the
  /// result, and end the reply with exactly one line, `IMPLEMENTATION:
  /// DONE`. This no longer instructs the model to push or open a PR
  /// itself — that only happens after [_runCodingExecution]'s own
  /// agentic verify turn passes (see [_assembleVerificationContext]/
  /// [_assembleCorrectiveContext] for the retry-turn prompt used instead
  /// when that turn reports a failure). The explicit "commit your
  /// changes" instruction was added after a real manual pass caught the
  /// model finishing `IMPLEMENTATION: DONE` having only edited files on
  /// disk without ever running `git commit` — verification doesn't
  /// inherently care about git state, so it passed anyway, Aion pushed a
  /// branch with nothing new, and `gh pr create` correctly rejected it
  /// with "No commits between main and ...", losing the edit entirely
  /// once the worktree was torn down. When [handoffSummary] is non-null
  /// (a handoff — see [_handoffExecutionChat] — just seeded this chat),
  /// it's prepended so the new chat's opening context makes clear this
  /// Task is being picked up mid-flight rather than started fresh. Added
  /// for `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-
  /// trigger`.
  Future<String> _assembleExecutionContext(
    Ticket task, {
    String? handoffSummary,
  }) async {
    final buffer = StringBuffer();
    if (handoffSummary != null) {
      buffer
        ..writeln(
          'Picking up this Task from a prior coding-execution chat that '
          'reached its context limit. Handoff summary from that chat:',
        )
        ..writeln()
        ..writeln(handoffSummary)
        ..writeln()
        ..writeln('---')
        ..writeln();
    }
    buffer.writeln('# ${task.title}');
    final description = task.description;
    if (description != null && description.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(description);
    }

    final conventions = await _effectiveAssetContent(
      'conventions/architecture-conventions',
    );
    if (conventions != null && conventions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Project conventions')
        ..writeln()
        ..writeln(conventions);
    }

    buffer
      ..writeln()
      ..writeln(
        'If this worktree needs dependencies installed or a build step '
        'run before you can work effectively, do that first (see any '
        'suggested command in Project conventions above). Then '
        'implement this Task using the available file, git, and bash '
        'tools, and commit your changes (git add + git commit). Do not '
        'push or open a pull request — Aion verifies and does that '
        'itself once you\'re done. End your reply with exactly one '
        'line: "IMPLEMENTATION: DONE".',
      );
    return buffer.toString().trim();
  }

  /// Assembles the verify-turn prompt run immediately after a successful
  /// implement turn (see [_runCodingExecution]) — the project's
  /// effective `skills/verify` content (see [_effectiveAssetContent]),
  /// which is written as operative instructions (see `assets/baseline/
  /// 0.3.0/skills/verify.md`), plus a one-line reminder of what's being
  /// verified. Runs in the same chat/worktree as the implement turn, so
  /// the model still has the diff it just produced in context; this
  /// reminder is cheap insurance against that continuity, not a full
  /// re-statement of the task. Added for `aion-arch/changes/project-
  /// type-aware-conventions-and-verification` — replaces the
  /// `FlutterVerifier`-based mechanical verify gate with this agentic
  /// one.
  Future<String> _assembleVerificationContext(Ticket task) async {
    final verifySkill = await _effectiveAssetContent('skills/verify');
    final buffer = StringBuffer();
    if (verifySkill != null && verifySkill.isNotEmpty) {
      buffer
        ..writeln(verifySkill)
        ..writeln();
    }
    buffer.writeln(
      'Verify the change you just implemented and committed for '
      '"${task.title}", following the instructions above.',
    );
    return buffer.toString().trim();
  }

  /// Returns [chatTicketId]'s most recently created comment's raw
  /// content, or `null` if it has none. Used by [_runCodingExecution] to
  /// read back the verify turn's own reply — mirrors
  /// [_executionSucceededWithPr]'s existing "find the most recent
  /// comment" lookup, simplified since the caller already has the
  /// chat's id directly rather than needing to look it up from a Task
  /// id. Added for `aion-arch/changes/project-type-aware-conventions-
  /// and-verification`.
  Future<String?> _lastCommentContent(String chatTicketId) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return null;
    final comments = await commentRepo.getCommentsForTicket(chatTicketId);
    if (comments.isEmpty) return null;
    final mostRecent = comments.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    return mostRecent.content;
  }

  /// Parses a verify turn's reply ([reply], from [_lastCommentContent])
  /// for its terminal `VERIFICATION:` line. Returns `null` **only**
  /// when [reply] contains the literal `VERIFICATION: PASSED` line — an
  /// explicit `VERIFICATION: FAILED — <reason>` line returns that
  /// reason; anything else (a missing terminal line, or a `null` reply)
  /// fails closed, returning a generic reason. This "fail closed"
  /// behavior is what preserves `coding-execution-reliability-and-
  /// safety`'s actual safety property — a run must never open a PR on
  /// an ambiguous or missing verification result, even though pass/fail
  /// is no longer determined by an exit code. Added for `aion-arch/
  /// changes/project-type-aware-conventions-and-verification`.
  String? _verificationFailureReason(String? reply) {
    if (reply == null) {
      return 'The verification turn produced no reply.';
    }
    if (reply.contains('VERIFICATION: PASSED')) return null;
    final match = RegExp(
      r'VERIFICATION:\s*FAILED\s*(?:—|-)?\s*(.*)',
    ).firstMatch(reply);
    final reason = match?.group(1)?.trim();
    if (reason != null && reason.isNotEmpty) return reason;
    return reply.length > 500 ? '${reply.substring(0, 500)}...' : reply;
  }

  /// Assembles the corrective-turn prompt fed back to the model when
  /// [_verificationFailureReason] reports a failure and the effective
  /// `AutomationContext.codingExecutionRetry` confidence is
  /// [AutomationConfidence.auto] — the verify turn's own failure
  /// [reason], plus a repeat of [_assembleExecutionContext]'s commit +
  /// `IMPLEMENTATION: DONE` completion-signal instruction. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`;
  /// retyped from `FlutterVerifyResult` to a plain `String` for
  /// `aion-arch/changes/project-type-aware-conventions-and-
  /// verification`.
  String _assembleCorrectiveContext(String reason) {
    return 'Verification reported:\n\n'
        '$reason\n\n'
        'Fix these issues and commit your changes (git add + git '
        'commit), then end your reply with exactly one line: '
        '"IMPLEMENTATION: DONE".';
  }

  /// The Task/Bug [taskId]'s current coding-execution chat — its most
  /// recently created `"Coding Execution — "`-prefixed child. Covers a
  /// `"(continued)"` handoff descendant (see [_handoffExecutionChat])
  /// automatically: it shares the same prefix and is simply created
  /// later, so it naturally sorts first. `null` if [taskId] has no
  /// execution chat yet. Shared by [_executionSucceededWithPr],
  /// [_computeExecutionFailure], and [_resolveExecutionChat]. Added for
  /// `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-trigger`
  /// (extracted from what were previously two duplicated inline lookups).
  Future<Ticket?> _mostRecentExecutionChat(String taskId) async {
    final chats = await _repository.getTicketsByParent(
      taskId,
      types: const [TicketType.chat],
    );
    final executionChats =
        chats.where((c) => c.title.startsWith('Coding Execution — ')).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return executionChats.isEmpty ? null : executionChats.first;
  }

  /// Whether [taskId]'s most recently created `"Coding Execution — "`-
  /// prefixed `chat` child's most recent comment contains the literal
  /// `EXECUTION: PR_OPENED` line — mirrors [_designSyncApproved]'s own
  /// lookup shape exactly (that one takes the *Story's* id and finds its
  /// `"Design Sync — "`-prefixed chat; this takes the *Task's* id and
  /// finds its `"Coding Execution — "`-prefixed chat via
  /// [_mostRecentExecutionChat]), so both [_runCodingExecution] and
  /// [getTicketById] can call it identically without needing to know the
  /// spawned chat's own id. Accepts either [CommentAuthorType.ai] or
  /// [CommentAuthorType.system] as the comment's author — before
  /// `aion-arch/changes/coding-execution-reliability-and-safety`, only
  /// the model itself (`ai`) ever posted this line; now Aion posts it
  /// itself (`system`) once its own verify-then-push-then-PR sequence
  /// succeeds (see [_runCodingExecution]).
  Future<bool> _executionSucceededWithPr(String taskId) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return false;
    final executionChat = await _mostRecentExecutionChat(taskId);
    if (executionChat == null) return false;
    final comments = await commentRepo.getCommentsForTicket(executionChat.id);
    if (comments.isEmpty) return false;
    final mostRecent = comments.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    return (mostRecent.authorType == CommentAuthorType.ai ||
            mostRecent.authorType == CommentAuthorType.system) &&
        mostRecent.content.contains('EXECUTION: PR_OPENED');
  }

  /// Computes the `(executionFailureReason, executionCanRetry)` pair for
  /// [taskId] once its coding-execution run has finished without a
  /// confirmed PR (see [_executionSucceededWithPr]) — used by
  /// [getTicketById]. Finds the Task's most recent `"Coding Execution —
  /// "`-prefixed chat via [_mostRecentExecutionChat] (mirrors
  /// [_executionSucceededWithPr]'s own lookup) and inspects its most
  /// recent comment: an `"Execution failed verification: ..."` or
  /// `"Execution failed: ..."` system/ai comment (posted by
  /// [_runCodingExecution]/[ChatCubit.runChatTurn] respectively) surfaces
  /// that content verbatim; anything else — including no comments at all,
  /// which can happen after an app restart mid-run — surfaces a fixed
  /// "ended without a clear result" message. Either case always pairs
  /// with `canRetry: true`. Returns `(null, false)` only when no
  /// execution chat exists at all yet (a Task moved to `inProgress` a
  /// moment before its chat is spawned). Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`.
  Future<(String?, bool)> _computeExecutionFailure(String taskId) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return (null, false);
    final executionChat = await _mostRecentExecutionChat(taskId);
    if (executionChat == null) return (null, false);
    const stalledMessage =
        'Execution ended without a clear result — retry to try again.';
    final comments = await commentRepo.getCommentsForTicket(executionChat.id);
    if (comments.isEmpty) return (stalledMessage, true);
    final mostRecent = comments.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final isSystemOrAi =
        mostRecent.authorType == CommentAuthorType.system ||
        mostRecent.authorType == CommentAuthorType.ai;
    if (isSystemOrAi &&
        (mostRecent.content.startsWith('Execution failed verification:') ||
            mostRecent.content.startsWith('Execution failed:'))) {
      return (mostRecent.content, true);
    }
    return (stalledMessage, true);
  }

  /// Computes the `(sddStageFailureReason, sddStageCanRetry)` pair for
  /// [epicOrStoryId]'s most recent [advanceSddStage] attempt — used by
  /// [getTicketById]. Mirrors [_computeExecutionFailure]'s shape, but
  /// looks at the ticket's most recently created `chat` child directly
  /// (unlike [_mostRecentExecutionChat], no title-prefix filter is
  /// needed here — every `chat` child of an epic/story is a stage-
  /// advance chat spawned by [_createStageChat], never a coding-
  /// execution chat, which only ever parents under a Task/Bug) and
  /// inspects its most recent comment:
  /// - Starts with `"Stage advance failed: "` (posted by
  ///   [_runStageChatTurn]'s catch block) → that comment's content,
  ///   `canRetry: true`.
  /// - No `chat` child exists yet, or the most recent comment is
  ///   [CommentAuthorType.ai]-authored (the turn completed normally) →
  ///   `(null, false)`.
  /// - Anything else while [epicOrStoryId] is **not** in
  ///   [_inFlightStageAdvanceIds] (orphaned — most likely an app restart
  ///   happened mid-turn) → a fixed "ended without a clear result"
  ///   message, `canRetry: true`, mirroring [_computeExecutionFailure]'s
  ///   own orphaned/stalled fallback. While still in-flight, `(null,
  ///   false)` — the turn just hasn't produced a terminal comment yet.
  /// Added for `aion-arch/changes/board-execution-indicators-and-notifications`.
  Future<(String?, bool)> _computeStageAdvanceFailure(
    String epicOrStoryId,
  ) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return (null, false);
    final chats = await _repository.getTicketsByParent(
      epicOrStoryId,
      types: const [TicketType.chat],
    );
    if (chats.isEmpty) return (null, false);
    final mostRecentChat = chats.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    const stalledMessage = 'Stage advance ended without a clear result.';
    final comments = await commentRepo.getCommentsForTicket(mostRecentChat.id);
    if (comments.isEmpty) {
      return _inFlightStageAdvanceIds.contains(epicOrStoryId)
          ? (null, false)
          : (stalledMessage, true);
    }
    final mostRecent = comments.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    if (mostRecent.content.startsWith('Stage advance failed: ')) {
      return (mostRecent.content, true);
    }
    if (mostRecent.authorType == CommentAuthorType.ai) return (null, false);
    return _inFlightStageAdvanceIds.contains(epicOrStoryId)
        ? (null, false)
        : (stalledMessage, true);
  }

  /// Whether [parentId]'s most recently created `chat` child ticket
  /// already has at least one [CommentAuthorType.ai] comment — the proxy
  /// this change uses for "that stage's chat has completed," since a
  /// [ChatCubit] reply's in-progress `streamingText` is never persisted
  /// mid-stream (see `chat_cubit.dart`). Returns `false` if constructed
  /// without a [CommentRepository] (see the constructor's dartdoc), or if
  /// no `chat` child exists yet.
  Future<bool> _mostRecentChatHasTerminalReply(String parentId) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return false;

    final chats = await _repository.getTicketsByParent(
      parentId,
      types: const [TicketType.chat],
    );
    if (chats.isEmpty) return false;

    final mostRecent = chats.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final comments = await commentRepo.getCommentsForTicket(mostRecent.id);
    return comments.any((c) => c.authorType == CommentAuthorType.ai);
  }

  /// Resolves [phase] to its currently configured [AgentModelDescriptor],
  /// via [_modelRoutingRepository]. Falls back to the first registered
  /// provider's first model — the closest available equivalent to the
  /// hardcoded `AgentModel.sonnet` default every call site used before
  /// per-phase routing existed — when the cubit was constructed without a
  /// [ModelRoutingRepository] (see the constructor's dartdoc). Added for
  /// `aion-arch/changes/per-phase-tier-based-model-routing`.
  Future<AgentModelDescriptor> _resolveModel(ModelPhase phase) async {
    final repo = _modelRoutingRepository;
    if (repo != null) return repo.getModelForPhase(phase);
    final registry = _providerRegistry;
    if (registry != null) {
      return registry.availableProviders.first.availableModels.first;
    }
    return const AgentModelDescriptor(
      providerId: ProviderId.claudeAgentSdk,
      modelId: 'claude-sonnet-5',
      label: 'Sonnet 5',
      contextWindowTokens: 200000,
    );
  }

  /// Resolves [phase] to its currently configured [AgentModelDescriptor]
  /// (via [_resolveModel]) and that model's [AgentProvider] (via
  /// [_providerRegistry]). Shared helper so every model call site
  /// resolves the pair identically — see
  /// `aion-arch/changes/pluggable-provider-abstraction/design.md` §7.
  /// Only called from call sites already gated on [_providerRegistry]
  /// being non-null.
  Future<(AgentModelDescriptor, AgentProvider)> _resolveModelAndProvider(
    ModelPhase phase,
  ) async {
    final model = await _resolveModel(phase);
    final provider = _providerRegistry!.providerById(model.providerId);
    return (model, provider);
  }

  /// Creates a `chat`-type child ticket for [stage] under [parent] and
  /// posts an auto-assembled [CommentAuthorType.system] context comment
  /// (see [_assembleStageContext]) — the `await`ed half of what used to
  /// be a single blocking `_spawnStageChat` call before
  /// `aion-arch/changes/board-execution-indicators-and-notifications`
  /// split it so [advanceSddStage] no longer blocks on the chat's AI
  /// reply (see [_runStageChatTurn] for that half). Returns the
  /// persisted chat ticket's id, or `null` if constructed without a
  /// [ProviderRegistry]/[CommentRepository] (see the constructor's
  /// dartdoc) — real usage (`app_router.dart`) always supplies both. For
  /// [SddStage.designBrief] specifically, also creates a `page`-type
  /// design ticket (`"Design — <parent.title>"`) and links it to
  /// [parent] via [TicketLinkRepository.createLink] before the chat
  /// itself is created — see [_linkedDesignPage]. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  Future<String?> _createStageChat(Ticket parent, SddStage stage) async {
    final providerRegistry = _providerRegistry;
    final commentRepo = _commentRepository;
    if (providerRegistry == null || commentRepo == null) return null;

    final now = DateTime.now();

    if (stage == SddStage.designBrief) {
      // Guarded on _linkRepository, not just the link-creation call —
      // without it, _linkedDesignPage could never discover the page
      // (it walks links, not title text), leaving `designBrief` stuck
      // at `awaitingDesignPaste` forever. Skip creating the orphan
      // rather than leave one behind.
      final linkRepo = _linkRepository;
      if (linkRepo != null) {
        final page = Ticket(
          id: _uuid.v4(),
          ticketId: '',
          type: TicketType.page,
          title: 'Design — ${parent.title}',
          status: TicketStatus.backlog,
          createdAt: now,
          updatedAt: now,
        );
        await _repository.createTicket(page);
        await linkRepo.createLink(
          sourceTicketId: page.id,
          targetTicketId: parent.id,
          linkType: TicketLinkType.relatesTo,
        );
      }
    }

    final chatTicket = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.chat,
      title: '${_stagePresentName(stage)} — ${parent.title}',
      status: TicketStatus.backlog,
      parentId: parent.id,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createTicket(chatTicket);
    final persistedChat = await _repository.getTicketById(chatTicket.id);
    if (persistedChat == null) return null;

    final context = await _assembleStageContext(parent, stage);
    await commentRepo.addComment(
      TicketComment(
        id: '',
        ticketId: persistedChat.id,
        content: context,
        authorType: CommentAuthorType.system,
        createdAt: DateTime.now(),
      ),
    );

    return persistedChat.id;
  }

  /// Runs [chatId]'s stage-advance AI turn for [parent]/[stage] — the
  /// `unawaited` half of what used to be a single blocking
  /// `_spawnStageChat` call (see [_createStageChat] for the `await`ed
  /// chat-creation half). Calls the resolved [AgentProvider]'s client and
  /// persists the streamed reply via [ChatCubit.runChatTurn] — the same
  /// accumulate-then-persist logic [ChatCubit.sendMessage] uses, so the
  /// spawn path and the user-message path can't drift apart. The model
  /// is resolved via [_resolveModel] using [stage]'s
  /// [SddStageModelPhase.modelPhase] (see
  /// `aion-arch/changes/per-phase-tier-based-model-routing`). Re-runs
  /// [_assembleStageContext] to get [chatId]'s turn prompt (cheap —
  /// local ticket/comment reads only, no network) rather than threading
  /// [_createStageChat]'s already-computed context through an extra
  /// parameter. A hard error escaping [ChatCubit.runChatTurn] — this
  /// method runs `unawaited`, so nothing else would ever observe it — is
  /// caught, posts a `"Stage advance failed: <e>"` system comment
  /// (mirrors [_runCodingExecution]'s own `"Execution failed: ..."`
  /// catch-comment shape) and emits
  /// [TicketsErrorReason.sddStageAdvanceFailed] so the failure surfaces
  /// in the chat transcript and as a one-shot toast instead of silently
  /// vanishing into a discarded `unawaited` future. On completion
  /// (success or failure), removes both [parent]'s id and [chatId] from
  /// [_inFlightStageAdvanceIds] and calls [_refreshInFlightBoardState].
  /// When `stage == SddStage.proposed` and the turn succeeds, also reads
  /// [chatId]'s most recent comment back via
  /// [CommentRepository.getCommentsForTicket] (mirrors
  /// [_designSyncApproved]'s own read-back pattern — no change to
  /// [ChatCubit.runChatTurn]'s shared return contract) and passes it to
  /// [_materializeDecomposition]. Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`
  /// and `aion-arch/changes/board-task-ordering-indication`.
  Future<void> _runStageChatTurn(
    Ticket parent,
    SddStage stage,
    String chatId,
  ) async {
    final providerRegistry = _providerRegistry;
    final commentRepo = _commentRepository;
    if (providerRegistry == null || commentRepo == null) return;

    try {
      final context = await _assembleStageContext(parent, stage);
      final (model, provider) = await _resolveModelAndProvider(
        stage.modelPhase,
      );
      final succeeded = await ChatCubit.runChatTurn(
        client: provider.client,
        provider: provider,
        commentRepo: commentRepo,
        chatTicketId: chatId,
        prompt: context,
        model: model,
      );
      if (succeeded && stage == SddStage.proposed) {
        final comments = await commentRepo.getCommentsForTicket(chatId);
        if (comments.isNotEmpty) {
          final mostRecent = comments.reduce(
            (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
          );
          await _materializeDecomposition(parent, mostRecent.content);
        }
      }
    } catch (e) {
      await commentRepo.addComment(
        TicketComment(
          id: '',
          ticketId: chatId,
          content: 'Stage advance failed: $e',
          authorType: CommentAuthorType.system,
          createdAt: DateTime.now(),
        ),
      );
      emit(
        const TicketsError(
          '',
          reason: TicketsErrorReason.sddStageAdvanceFailed,
        ),
      );
    } finally {
      _inFlightStageAdvanceIds
        ..remove(parent.id)
        ..remove(chatId);
      _refreshInFlightBoardState();
    }
  }

  /// Assembles the plain-text context a spawned stage chat opens with:
  /// [parent]'s title/description, and — for [SddStage.verifying]/
  /// [SddStage.archived] — its direct children's titles and statuses, or
  /// — for [SddStage.designBrief]/[SddStage.designSync] — the existing
  /// design-token file contents (see [_readTokenFilesForContext]) and,
  /// for [SddStage.designSync] specifically, the linked design Page's
  /// pasted content (see [_linkedDesignPage]), or — for
  /// [SddStage.proposed] — instructions to end the reply with a fenced
  /// `## Decomposition` block (parsed by [_parseDecomposition] once the
  /// turn completes, see [_materializeDecomposition]). No embeddings, no
  /// repo-map-lite involvement (see proposal.md's Out of scope).
  Future<String> _assembleStageContext(Ticket parent, SddStage stage) async {
    final buffer = StringBuffer()..writeln('# ${parent.title}');
    final description = parent.description;
    if (description != null && description.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(description);
    }

    if (stage == SddStage.verifying || stage == SddStage.archived) {
      final nextRank = parent.type == TicketType.story
          ? TicketType.task
          : TicketType.story;
      final children = await _repository.getTicketsByParent(
        parent.id,
        types: nextRank == TicketType.task
            ? TicketTypeHierarchy.executableTypes
            : [nextRank],
      );
      if (children.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(nextRank == TicketType.task ? '## Tasks' : '## Stories');
        for (final child in children) {
          final statusLabel = nextRank == TicketType.task
              ? child.status.name
              : (child.sddStage?.name ?? 'not started');
          buffer.writeln('- ${child.title} ($statusLabel)');
        }
      }
    } else if (stage == SddStage.designBrief) {
      buffer
        ..writeln()
        ..writeln('## Existing design system')
        ..writeln(await _readTokenFilesForContext());
      buffer
        ..writeln()
        ..writeln(
          'Produce a ready-to-paste Claude Design prompt for this Story, '
          'covering: Context, Existing design system (the tokens above), '
          'Feature to design, Components to specify, Export requirements '
          '(Flutter Color/TextStyle/EdgeInsets values, both Arctic and '
          'Obsidian themes, no Material widgets), and a Mockup request.',
        );
    } else if (stage == SddStage.designSync) {
      final page = await _linkedDesignPage(parent.id);
      buffer
        ..writeln()
        ..writeln('## Pasted design export')
        ..writeln(page?.description ?? '(none pasted yet)')
        ..writeln()
        ..writeln('## Existing design system')
        ..writeln(await _readTokenFilesForContext())
        ..writeln()
        ..writeln(
          'Check the pasted design export above for: (1) any Material '
          'widget reference (Card, ElevatedButton, Scaffold, ThemeData, '
          'etc. — Aion is Non-Material, see project.md), (2) whether every '
          'referenced color matches one of the existing tokens above or is '
          'a clearly new, semantically named one. List any issues found. '
          'End your reply with exactly one line: "DESIGN GATE: APPROVED" '
          'if there are no issues, or "DESIGN GATE: PENDING" if there are.',
        );
    } else if (stage == SddStage.proposed) {
      final childRank = parent.type == TicketType.epic
          ? TicketType.story
          : TicketType.task;
      buffer
        ..writeln()
        ..writeln(
          'Decompose this ${parent.type.name} into child '
          '${childRank == TicketType.task ? "Tasks" : "Stories"}. End your '
          'reply with a fenced block titled "## Decomposition", one line per '
          'child in the exact form '
          '"- ${childRank == TicketType.task ? "Task" : "Story"}: <title>" '
          'optionally suffixed with " (blockedBy: <exact title of an earlier '
          'line in this block>)" when that child cannot start until another '
          'one finishes.',
        );
    }

    return buffer.toString().trim();
  }

  /// Parses [reply]'s trailing `"## Decomposition"` fenced block (see
  /// [_assembleStageContext]'s [SddStage.proposed] prompt) into an
  /// ordered list of `(title, blockedByTitle)` pairs — `blockedByTitle`
  /// is `null` when the line has no `(blockedBy: ...)` suffix. Matched
  /// only against the block's content: the text between `"##
  /// Decomposition"` and the next blank line or the end of [reply].
  /// Regex per line: `^- (Story|Task): (.+?)(?: \(blockedBy:
  /// (.+)\))?$`; [childType] picks which of `Story`/`Task` is accepted —
  /// a line whose literal doesn't match [childType] is skipped, not an
  /// error. Returns an empty list if no `"## Decomposition"` block is
  /// found, or no line matches at all — parse failure is silent, not an
  /// error (see proposal.md's fail-open note). Added for
  /// `aion-arch/changes/board-task-ordering-indication`.
  List<(String title, String? blockedByTitle)> _parseDecomposition(
    String reply,
    TicketType childType,
  ) {
    const heading = '## Decomposition';
    final headingIndex = reply.indexOf(heading);
    if (headingIndex == -1) return [];

    final afterHeading = reply.substring(headingIndex + heading.length);
    final blockEnd = afterHeading.indexOf('\n\n');
    final block = blockEnd == -1
        ? afterHeading
        : afterHeading.substring(0, blockEnd);

    final expectedPrefix = childType == TicketType.task ? 'Task' : 'Story';
    final linePattern = RegExp(
      r'^- (Story|Task): (.+?)(?: \(blockedBy: (.+)\))?$',
      multiLine: true,
    );

    return [
      for (final match in linePattern.allMatches(block))
        if (match.group(1) == expectedPrefix)
          (match.group(2)!.trim(), match.group(3)?.trim()),
    ];
  }

  /// Runs once per `proposed`-stage chat turn (called from
  /// [_runStageChatTurn] immediately after a successful turn, only when
  /// `stage == SddStage.proposed`): parses [reply] via
  /// [_parseDecomposition], creates one child ticket per parsed line
  /// under [parent] (via [TicketRepository.createTicket]), then — for
  /// every line whose `blockedByTitle` exact-matches (case-insensitive)
  /// another parsed line's title — creates a `blockedBy` link from the
  /// new child to its blocker sibling (via
  /// [TicketLinkRepository.createLink]). An unresolved `blockedByTitle`
  /// (no matching sibling title) is skipped for the link only — the
  /// child ticket itself is still created. No block, a block with no
  /// parseable lines, or no [TicketLinkRepository] configured is a
  /// silent no-op: today's exact behavior (a human creates children by
  /// hand) is preserved, not treated as a failure. Added for
  /// `aion-arch/changes/board-task-ordering-indication`.
  Future<void> _materializeDecomposition(Ticket parent, String reply) async {
    final childType = parent.type == TicketType.epic
        ? TicketType.story
        : TicketType.task;
    final parsed = _parseDecomposition(reply, childType);
    if (parsed.isEmpty) return;

    final now = DateTime.now();
    final idByTitle = <String, String>{};
    for (final (title, _) in parsed) {
      final child = Ticket(
        id: _uuid.v4(),
        ticketId: '',
        type: childType,
        title: title,
        status: TicketStatus.backlog,
        parentId: parent.id,
        createdAt: now,
        updatedAt: now,
      );
      await _repository.createTicket(child);
      idByTitle[title.toLowerCase()] = child.id;
    }

    final linkRepo = _linkRepository;
    if (linkRepo == null) return;
    for (final (title, blockedByTitle) in parsed) {
      if (blockedByTitle == null) continue;
      final childId = idByTitle[title.toLowerCase()];
      final blockerId = idByTitle[blockedByTitle.toLowerCase()];
      if (childId == null || blockerId == null) continue;
      await linkRepo.createLink(
        sourceTicketId: childId,
        targetTicketId: blockerId,
        linkType: TicketLinkType.blockedBy,
      );
    }
  }

  /// Reads `aion_colors.dart`/`aion_text.dart`/`aion_radius.dart`'s
  /// contents off disk for inclusion as plain-text context — the same
  /// static-injection approach `/design-brief`/`/design-sync`'s own
  /// `SKILL.md` `cat`s these files for, ported to Dart
  /// `File.readAsString`. No tool access involved; this is [TicketsCubit]
  /// reading files for context assembly, the same category of
  /// desktop-only capability [_gitProjector]/[_projectRootPath] already
  /// gates. Returns an empty string (not an error) if [_projectRootPath]
  /// is unset or a file is missing — mobile/web has neither a filesystem
  /// root nor UI Story design-gate stages triggering in practice
  /// (Task/Story execution is desktop-only already), so this degrades
  /// gracefully rather than throwing. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  Future<String> _readTokenFilesForContext() async {
    final root = _projectRootPath;
    if (root == null) return '';
    const relativePaths = [
      'lib/design_system/tokens/aion_colors.dart',
      'lib/design_system/tokens/aion_text.dart',
      'lib/design_system/tokens/aion_radius.dart',
    ];
    final buffer = StringBuffer();
    for (final relativePath in relativePaths) {
      final file = File(p.join(root, relativePath));
      if (await file.exists()) {
        buffer
          ..writeln('### $relativePath')
          ..writeln(await file.readAsString());
      }
    }
    return buffer.toString();
  }

  /// Display name for [stage], used in a spawned chat ticket's title —
  /// present-progressive for every stage except [SddStage.designBrief]/
  /// [SddStage.designSync], which read naturally as their plain node
  /// name instead (design.md §1.3).
  String _stagePresentName(SddStage stage) => switch (stage) {
    SddStage.exploring => 'Exploring',
    SddStage.proposed => 'Proposed',
    SddStage.designBrief => 'Design Brief',
    SddStage.designSync => 'Design Sync',
    SddStage.verifying => 'Verifying',
    SddStage.archived => 'Archived',
  };

  /// Fires an async embedding-regen call for [ticket] and writes the
  /// result back via [TicketRepository.updateEmbedding] once it
  /// resolves. Never awaited by callers — ticket save must never block
  /// on this. No-ops if no [_embeddingProvider] was provided (see the
  /// constructor's dartdoc).
  Future<void> _triggerEmbeddingRegen(Ticket ticket) async {
    final provider = _embeddingProvider;
    if (provider == null) return;
    final bytes = await provider.embed(
      '${ticket.title}\n\n${ticket.description ?? ''}',
    );
    await _repository.updateEmbedding(ticket.id, bytes);
  }

  /// Projects [ticket] to its Markdown file and commits it, labelled
  /// [eventLabel]. No-ops if no [_gitProjector]/[_projectRootPath] was
  /// provided (see the constructor's dartdoc) — desktop-only in
  /// practice, since `WorkspaceShell` only supplies these on desktop.
  ///
  /// The `'restored'` trigger event lives on `TrashCubit` instead — see
  /// its own `_triggerGitProjection` (added by
  /// `aion-arch/changes/trash-restore-git-projection`, which closed the
  /// gap this dartdoc used to flag here).
  Future<void> _triggerGitProjection(Ticket ticket, String eventLabel) async {
    final projector = _gitProjector;
    final rootPath = _projectRootPath;
    if (projector == null || rootPath == null) return;
    await projector.project(ticket, rootPath, eventLabel);
  }

  /// Recomputes and persists the rollup for every ticket on the path from
  /// each id in [startIds] up to its structural root (inclusive of each
  /// starting ancestor — see the call sites in [updateTicket]/
  /// [updateTicketParent]/[trashTicket]/[trashTickets] for exactly which
  /// ids each passes), then projects every ticket whose rollup actually
  /// changed to git in one batched commit labelled [eventLabel]. Thin
  /// delegate to [_rollupRecomputer] — the actual walk is shared with
  /// `TrashCubit` (see [TicketRollupRecomputer]) rather than duplicated
  /// here. No-ops if [startIds] is empty. Fire-and-forget from every call
  /// site — never awaited by the caller's own return path, same pattern
  /// as [_triggerEmbeddingRegen]/[_triggerGitProjection].
  Future<void> _recomputeRollupChain(
    Set<String> startIds,
    String eventLabel,
  ) {
    return _rollupRecomputer.recompute(startIds, eventLabel);
  }

  /// Runs [trashed]'s single-ticket `'trashed'` projection (no-op if
  /// [trashed] is `null`) followed by [parentId]'s ancestor chain's rollup
  /// recompute, in that order — see [trashTicket]'s dartdoc for why these
  /// must be sequenced rather than fired concurrently as two independent
  /// unawaited calls.
  Future<void> _trashGitSideEffects(Ticket? trashed, String? parentId) async {
    if (trashed != null) {
      await _triggerGitProjection(trashed, 'trashed');
    }
    await _recomputeRollupChain({?parentId}, 'rollup updated');
  }

  /// Runs each id in [ids]' single-ticket `'trashed'` projection (in
  /// order, re-fetching each from [_repository] since [trashTickets]
  /// itself never holds the post-trash rows) followed by one batched
  /// rollup recompute seeded from [parentIdOf]'s values — see
  /// [trashTickets]'s dartdoc for why these must be sequenced rather than
  /// fired concurrently.
  Future<void> _trashBatchGitSideEffects(
    List<String> ids,
    Map<String, String?> parentIdOf,
  ) async {
    for (final id in ids) {
      final trashed = await _repository.getTicketById(id);
      if (trashed != null) {
        await _triggerGitProjection(trashed, 'trashed');
      }
    }
    await _recomputeRollupChain({
      for (final id in ids)
        if (parentIdOf[id] != null) parentIdOf[id]!,
    }, 'rollup updated');
  }

  /// Returns the on-demand [TicketRollupCounts] for [ticket] — the number
  /// of live tickets (self + descendants) contributing a non-null
  /// `estimate`/`timeSpent` value. Query-only: performs no writes and
  /// emits no state, unlike [_recomputeRollupChain] which persists.
  /// Computed fresh via [computeRollups] rather than read from a
  /// persisted field, since [RollupResult.estimateCount]/
  /// [RollupResult.timeSpentCount] are never written to drift (see
  /// `ticket_rollup_calculator.dart`) — deliberately on-demand rather
  /// than persisted, since a full-subtree walk for the single ticket
  /// `TicketDetailScreen` is showing is cheap; the reason a *rollup total*
  /// is persisted at all is to avoid that walk per list/board row, which
  /// doesn't apply to a single detail-screen view. Returns `0`/`0` if
  /// [ticket] has no live children (absent from [computeRollups]'s
  /// result map).
  Future<TicketRollupCounts> getRollupCounts(Ticket ticket) async {
    final all = await _repository.getAllTickets();
    final nodes = [
      for (final t in all)
        (
          id: t.id,
          parentId: t.parentId,
          estimate: t.estimate,
          timeSpent: t.timeSpent,
        ),
    ];
    final result = computeRollups(nodes)[ticket.id];
    return TicketRollupCounts(
      estimateCount: result?.estimateCount ?? 0,
      timeSpentCount: result?.timeSpentCount ?? 0,
    );
  }

  /// Builds the full descendant-id set of [rootId] by walking `parentId`
  /// forward through [all]. Shared by [getValidParentCandidates] and
  /// [updateTicketParent] so both apply the identical cycle definition.
  Set<String> _descendantIds(String rootId, List<Ticket> all) {
    final childrenByParent = <String, List<Ticket>>{};
    for (final t in all) {
      final p = t.parentId;
      if (p != null) {
        childrenByParent.putIfAbsent(p, () => []).add(t);
      }
    }
    final result = <String>{};
    void walk(String id) {
      for (final child in childrenByParent[id] ?? const []) {
        if (result.add(child.id)) walk(child.id);
      }
    }

    walk(rootId);
    return result;
  }

  /// Fetches the ticket with internal id [id]. Emits [TicketsLoading] then
  /// [TicketDetailLoaded] on success, or [TicketsError] if not found or the
  /// repository call throws. For an `epic`/`story` ticket, also fetches
  /// its direct children and evaluates [advanceSddStage]'s precondition
  /// for the ticket's current stage, populating
  /// [TicketDetailLoaded.canAdvanceSddStage] and, when that's `false`,
  /// [TicketDetailLoaded.sddStageBlockReason]. For a `story` ticket
  /// specifically, also computes [TicketDetailLoaded.needsDesignReview]
  /// via [_storyNeedsDesignReview] against its current child Tasks
  /// (`null` if none exist yet), and — when that's `true` —
  /// [TicketDetailLoaded.linkedDesignPage] via [_linkedDesignPage].
  /// Added for `aion-arch/changes/sdd-design-gate`. For a `task` ticket,
  /// also computes [TicketDetailLoaded.isExecuting],
  /// [TicketDetailLoaded.executionQueuePosition], and
  /// [TicketDetailLoaded.executionAwaitingReview] from the in-memory
  /// coding-execution queue state. Added for
  /// `aion-arch/changes/task-to-coding-execution-trigger`. When the run
  /// finished without a confirmed PR, also computes
  /// [TicketDetailLoaded.executionFailureReason]/
  /// [TicketDetailLoaded.executionCanRetry] via
  /// [_computeExecutionFailure]. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`. Also
  /// computes [TicketDetailLoaded.isAdvancingStage] from
  /// [_inFlightStageAdvanceIds] for **any** ticket type — `true` for an
  /// `epic`/`story` with an [advanceSddStage] chat spawn in flight, or
  /// for a `chat` ticket that *is* that in-flight spawn's own chat
  /// ticket. For an `epic`/`story` with a current [Ticket.sddStage] that
  /// isn't mid-advance, also computes
  /// [TicketDetailLoaded.sddStageFailureReason]/
  /// [TicketDetailLoaded.sddStageCanRetry] via
  /// [_computeStageAdvanceFailure]. Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  Future<void> getTicketById(String id) async {
    emit(const TicketsLoading());
    try {
      final ticket = await _repository.getTicketById(id);
      if (ticket == null) {
        emit(const TicketsError('', reason: TicketsErrorReason.notFound));
        return;
      }
      final check = await _sddStageAdvanceCheck(ticket);

      bool? needsDesignReview;
      Ticket? linkedDesignPage;
      if (ticket.type == TicketType.story) {
        final tasks = await _repository.getTicketsByParent(
          ticket.id,
          types: TicketTypeHierarchy.executableTypes,
        );
        needsDesignReview = tasks.isEmpty
            ? null
            : _storyNeedsDesignReview(tasks);
        if (needsDesignReview == true) {
          linkedDesignPage = await _linkedDesignPage(ticket.id);
        }
      }

      var isExecuting = false;
      int? executionQueuePosition;
      var executionAwaitingReview = false;
      String? executionFailureReason;
      var executionCanRetry = false;
      if (ticket.type.isExecutable) {
        isExecuting = _inFlightExecutionTaskId == ticket.id;
        final queueIndex = _executionQueue.indexOf(ticket.id);
        // 1-based: the first entry in the FIFO queue is "next in line"
        // (position 1) once the in-flight run finishes — nothing *in the
        // queue* is ahead of it. The in-flight run itself never reaches
        // this branch (isExecuting is checked separately above).
        executionQueuePosition = queueIndex >= 0 ? queueIndex + 1 : null;
        if (!isExecuting &&
            executionQueuePosition == null &&
            ticket.status == TicketStatus.inProgress) {
          final prConfirmed = await _executionSucceededWithPr(ticket.id);
          final automationRepo = _automationSettingsRepository;
          final confidence = automationRepo == null
              ? null
              : await _effectiveCodingExecutionConfidence(automationRepo);
          executionAwaitingReview =
              prConfirmed && confidence == AutomationConfidence.gated;
          if (!prConfirmed) {
            final (reason, canRetry) = await _computeExecutionFailure(
              ticket.id,
            );
            executionFailureReason = reason;
            executionCanRetry = canRetry;
          }
        }
      }

      final isAdvancingStage = _inFlightStageAdvanceIds.contains(ticket.id);

      String? sddStageFailureReason;
      var sddStageCanRetry = false;
      if ((ticket.type == TicketType.epic || ticket.type == TicketType.story) &&
          !isAdvancingStage &&
          ticket.sddStage != null) {
        final (reason, canRetry) = await _computeStageAdvanceFailure(ticket.id);
        sddStageFailureReason = reason;
        sddStageCanRetry = canRetry;
      }

      emit(
        TicketDetailLoaded(
          ticket,
          canAdvanceSddStage: check.canAdvance,
          sddStageBlockReason: check.blockReason,
          needsDesignReview: needsDesignReview,
          linkedDesignPage: linkedDesignPage,
          isExecuting: isExecuting,
          executionQueuePosition: executionQueuePosition,
          executionAwaitingReview: executionAwaitingReview,
          executionFailureReason: executionFailureReason,
          executionCanRetry: executionCanRetry,
          isAdvancingStage: isAdvancingStage,
          sddStageFailureReason: sddStageFailureReason,
          sddStageCanRetry: sddStageCanRetry,
        ),
      );
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Returns the total number of tickets that would move to trash if
  /// every id in [ids] were trashed right now, via
  /// [TicketRepository.previewTrashCount] — the exact same cascade
  /// computation [trashTicket]/[trashTickets] themselves use (including
  /// descendants that are already trashed, e.g. a child trashed
  /// individually earlier whose still-live parent is being trashed now),
  /// so the confirm dialog's preview always matches the actual outcome.
  /// Query only, no state emitted. Used by both the single-ticket
  /// (`TicketOverflowMenu`) and bulk (`TicketSelectionBar`) delete flows.
  Future<int> previewTrashCount(List<String> ids) {
    return _repository.previewTrashCount(ids);
  }

  /// Moves ticket [id] to trash via [TicketRepository.trashTicket].
  /// Context-aware on the state active before the call: if it was
  /// [TicketDetailLoaded] (the caller is `TicketDetailScreen`), emits
  /// [TicketTrashed] on success; any other (list/board-shaped) previous
  /// state re-fetches (re-applying the filters [searchTickets] was last
  /// called with, requesting at least as many tickets as were already
  /// loaded) and emits [TicketsLoaded] instead, so
  /// `TicketsListScreen`/`TicketBoardView` never fall into a blank state.
  /// Trash never fails except on a genuine unexpected repository error,
  /// which emits [TicketsError].
  ///
  /// The `'trashed'` git-projection for [id] (see [_triggerGitProjection])
  /// and the rollup recompute for its pre-trash `parentId`'s ancestor
  /// chain (see [_recomputeRollupChain] — [id]'s `parentId` is read before
  /// the trash write so it's captured before `deletedAt` excludes [id]
  /// from [_recomputeRollupChain]'s `getAllTickets()` read) both touch the
  /// same git repository's add/commit sequence, so they're sequenced into
  /// one chain — the single-ticket projection commits first, then the
  /// ancestor batch — and fired as a single fire-and-forget unit. Running
  /// them as two independent unawaited calls (as this used to) races the
  /// underlying git client's add/commit steps: the ancestor batch's staged
  /// files can get silently swept into the single-ticket commit instead of
  /// producing their own correctly-labelled `"N ancestors rollup updated"`
  /// commit.
  Future<void> trashTicket(String id) async {
    _searchGeneration++;
    final previousState = state;
    final currentTickets = switch (previousState) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsBatchTrashed(:final tickets) => tickets,
      TicketsBatchStatusUpdated(:final tickets) => tickets,
      TicketsBatchPriorityUpdated(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };
    emit(const TicketTrashing());
    try {
      final preTrash = await _repository.getTicketById(id);
      await _repository.trashTicket(id);
      final trashed = await _repository.getTicketById(id);
      final parentId = preTrash?.parentId;
      unawaited(_trashGitSideEffects(trashed, parentId));
      if (previousState is TicketDetailLoaded) {
        emit(const TicketTrashed());
      } else {
        final page = await _repository.searchTickets(
          query: _lastQuery,
          statuses: _lastStatuses,
          types: _lastTypes,
          priorities: _lastPriorities,
          sort: _lastSort,
          limit: max(_pageSize, currentTickets.length),
        );
        emit(TicketsLoaded(page.tickets, hasMore: page.hasMore));
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Moves every ticket in [ids] to trash via
  /// [TicketRepository.trashTickets]. Always triggered from
  /// `TicketsListScreen`'s selection mode (list or board rendering) — no
  /// detail-screen caller to special-case, unlike [trashTicket]. Emits
  /// [TicketsBatchTrashing] then [TicketsBatchTrashed] (refreshed page +
  /// actual trashed count) on success, or [TicketsError] on an
  /// unexpected failure. The refresh re-applies the filters
  /// [searchTickets] was last called with and requests at least as many
  /// tickets as were already loaded.
  ///
  /// Every git-touching step — each explicitly-trashed id's own
  /// `'trashed'` projection (projects only the explicitly-requested ids,
  /// not their cascaded descendants, also trashed by
  /// [TicketRepository.trashTickets] but not individually enumerable from
  /// its return value — a documented scope simplification, not an
  /// oversight), then the single batched rollup recompute (see
  /// [_recomputeRollupChain]) seeded from the union of every
  /// explicitly-trashed id's pre-trash `parentId` (read before the trash
  /// write, mirroring [trashTicket]'s own timing) — is sequenced into one
  /// chain and fired as a single fire-and-forget unit, same reasoning as
  /// [trashTicket]: concurrent unawaited git operations race the
  /// underlying git client's add/commit steps and can silently coalesce
  /// separate logical commits into one mislabeled commit.
  Future<void> trashTickets(List<String> ids) async {
    _searchGeneration++;
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsBatchTrashed(:final tickets) => tickets,
      TicketsBatchStatusUpdated(:final tickets) => tickets,
      TicketsBatchPriorityUpdated(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };
    emit(const TicketsBatchTrashing());
    try {
      final parentIdOf = <String, String?>{
        for (final id in ids) id: (await _repository.getTicketById(id))?.parentId,
      };
      final trashedCount = await _repository.trashTickets(ids);
      unawaited(_trashBatchGitSideEffects(ids, parentIdOf));
      final page = await _repository.searchTickets(
        query: _lastQuery,
        statuses: _lastStatuses,
        types: _lastTypes,
        priorities: _lastPriorities,
        sort: _lastSort,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(
        TicketsBatchTrashed(page.tickets, trashedCount, hasMore: page.hasMore),
      );
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Sets [status] on every ticket in [ids], via
  /// [TicketRepository.updateStatusForIds] — but only for the subset that
  /// passes the same two per-ticket gates [updateTicketStatus] already
  /// enforces for a single ticket moving to [TicketStatus.inProgress]: the
  /// Blocked-dependency gate ([_isTicketBlocked]) and, for Task/Bug
  /// tickets ([TicketTypeHierarchy.isExecutable]), the coding-execution
  /// gate ([_codingExecutionGateCheck]). Both gates only apply when
  /// [status] is [TicketStatus.inProgress] — every other target status
  /// skips gating entirely and writes the full [ids] list, mirroring
  /// [updateTicketStatus]'s own short-circuit. Rejected ids are silently
  /// excluded from the write (not reported per-id) — the widget layer
  /// surfaces the aggregate via [TicketsBatchStatusUpdated.skippedCount].
  ///
  /// Emits [TicketsBatchStatusUpdating] immediately, then
  /// [TicketsBatchStatusUpdated] (refreshed page + how many were written +
  /// how many were skipped) on success, or [TicketsError] on an unexpected
  /// failure. For every successfully-written ticket: triggers git
  /// projection (`'status-changed'`, same event [updateTicketStatus]
  /// triggers), and — for a Task/Bug moving to [TicketStatus.inProgress] —
  /// starts or queues its coding-execution run via
  /// [_triggerOrQueueCodingExecution], identical to [updateTicketStatus]'s
  /// own post-write side effects. Also calls [_refreshBlockedBoardState]
  /// on completion, since a written ticket may be another ticket's
  /// blocker.
  Future<void> updateStatusForTickets(
    List<String> ids,
    TicketStatus status,
  ) async {
    _searchGeneration++;
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsBatchTrashed(:final tickets) => tickets,
      TicketsBatchStatusUpdated(:final tickets) => tickets,
      TicketsBatchPriorityUpdated(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };
    emit(const TicketsBatchStatusUpdating());
    try {
      final writableIds = <String>[];
      if (status == TicketStatus.inProgress) {
        for (final id in ids) {
          final ticket = await _repository.getTicketById(id);
          if (ticket == null) continue;
          if (await _isTicketBlocked(ticket)) continue;
          if (ticket.type.isExecutable) {
            final check = await _codingExecutionGateCheck(ticket);
            if (!check.canStart) continue;
          }
          writableIds.add(id);
        }
      } else {
        writableIds.addAll(ids);
      }

      if (writableIds.isNotEmpty) {
        await _repository.updateStatusForIds(writableIds, status);
        for (final id in writableIds) {
          final updated = await _repository.getTicketById(id);
          if (updated != null) {
            unawaited(_triggerGitProjection(updated, 'status-changed'));
            if (updated.type.isExecutable &&
                status == TicketStatus.inProgress) {
              unawaited(_triggerOrQueueCodingExecution(updated));
            }
          }
        }
      }

      final page = await _repository.searchTickets(
        query: _lastQuery,
        statuses: _lastStatuses,
        types: _lastTypes,
        priorities: _lastPriorities,
        sort: _lastSort,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(
        TicketsBatchStatusUpdated(
          page.tickets,
          writableIds.length,
          ids.length - writableIds.length,
          hasMore: page.hasMore,
        ),
      );
      unawaited(_refreshBlockedBoardState());
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Sets [priority] on every ticket in [ids] via
  /// [TicketRepository.updatePriorityForIds] — unconditional, no gating
  /// (priority has no structural constraint, unlike status). Emits
  /// [TicketsBatchPriorityUpdating] immediately, then
  /// [TicketsBatchPriorityUpdated] (refreshed page + updated count) on
  /// success, or [TicketsError] on an unexpected failure. Does not trigger
  /// git projection (a plain field edit is not one of `project.md`'s
  /// event-triggered projection events — see [updateTicket], which doesn't
  /// trigger it either) and does not trigger embedding regeneration (only
  /// a title/description change does, per [updateTicket]).
  Future<void> updatePriorityForTickets(
    List<String> ids,
    TicketPriority priority,
  ) async {
    _searchGeneration++;
    final currentTickets = switch (state) {
      TicketsLoaded(:final tickets) => tickets,
      TicketCreated(:final tickets) => tickets,
      TicketStatusUpdated(:final tickets) => tickets,
      TicketsBatchTrashed(:final tickets) => tickets,
      TicketsBatchStatusUpdated(:final tickets) => tickets,
      TicketsBatchPriorityUpdated(:final tickets) => tickets,
      TicketsLoadingMore(:final tickets) => tickets,
      TicketsLoadMoreFailed(:final tickets) => tickets,
      _ => <Ticket>[],
    };
    emit(const TicketsBatchPriorityUpdating());
    try {
      await _repository.updatePriorityForIds(ids, priority);
      final page = await _repository.searchTickets(
        query: _lastQuery,
        statuses: _lastStatuses,
        types: _lastTypes,
        priorities: _lastPriorities,
        sort: _lastSort,
        limit: max(_pageSize, currentTickets.length),
      );
      emit(
        TicketsBatchPriorityUpdated(
          page.tickets,
          ids.length,
          hasMore: page.hasMore,
        ),
      );
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Loads the Documentation-section relations for the `page`/`resource`/
  /// `bug` ticket with id [ticketId] — its direct sub-page/resource
  /// children (if it's a `page`) and its `TicketLink`s, grouped into
  /// [linkedTickets]
  /// (the other side is a board type: epic/story/task/bug/chat) and
  /// [backlinks] (the other side is itself `page`/`resource`) — then
  /// re-emits [TicketDetailLoaded] with those fields populated. `bug` was
  /// added here for `aion-arch/changes/bug-ticket-type`'s widened Linked
  /// Tickets/Backlinks gate — a Bug's `relatesTo` link to a `release`
  /// ticket would otherwise never be reflected in the loaded state, even
  /// though the link itself was created successfully. `epic`/`story`/
  /// `task` were added here for
  /// `aion-arch/changes/board-task-ordering-indication`'s widened Linked
  /// Tickets gate (`ticket_metadata_section.dart`) — those types now
  /// render the section too, and would otherwise never have it populated.
  /// No-ops (does not emit) if the ticket isn't found, isn't one of the
  /// gated types, or the cubit has since moved on to a different
  /// ticket's detail state (a stale response from an earlier
  /// navigation). Only actually populates [linkedTickets]/[backlinks]
  /// when constructed with a [TicketLinkRepository] — every other call
  /// site is unaffected by this optional dependency, same rationale as
  /// [_embeddingProvider]/[_gitProjector]/[_projectRootPath]. Each
  /// populated [LinkedTicketRef.relativeType] is resolved via
  /// [relativeLinkType] against [ticketId] itself, so it always reads
  /// correctly from this ticket's own point of view regardless of which
  /// side of the underlying row it is.
  Future<void> loadDocumentRelations(String ticketId) async {
    final ticket = await _repository.getTicketById(ticketId);
    if (ticket == null) return;
    if (ticket.type != TicketType.page &&
        ticket.type != TicketType.resource &&
        ticket.type != TicketType.bug &&
        ticket.type != TicketType.epic &&
        ticket.type != TicketType.story &&
        ticket.type != TicketType.task) {
      return;
    }

    final childDocs = ticket.type == TicketType.page
        ? await _repository.getTicketsByParent(
            ticket.id,
            types: const [TicketType.page, TicketType.resource],
          )
        : const <Ticket>[];

    final linkedTickets = <LinkedTicketRef>[];
    final backlinks = <LinkedTicketRef>[];
    final linkRepo = _linkRepository;
    if (linkRepo != null) {
      final links = await linkRepo.getLinksForTicket(ticket.id);
      for (final link in links) {
        final otherId = link.sourceTicketId == ticket.id
            ? link.targetTicketId
            : link.sourceTicketId;
        final other = await _repository.getTicketById(otherId);
        if (other == null) continue;
        final ref = (
          ticket: other,
          relativeType: relativeLinkType(link, ticket.id),
          linkId: link.id,
        );
        if (other.type == TicketType.page ||
            other.type == TicketType.resource) {
          backlinks.add(ref);
        } else {
          linkedTickets.add(ref);
        }
      }
    }

    final current = state;
    if (current is! TicketDetailLoaded || current.ticket.id != ticket.id) {
      return;
    }
    emit(
      TicketDetailLoaded(
        ticket,
        childDocs: childDocs,
        linkedTickets: linkedTickets,
        backlinks: backlinks,
      ),
    );
  }

  /// Creates a [linkType] relationship from [ticketId] to
  /// [targetTicketId], then refreshes [ticketId]'s document relations and
  /// (for a `blocks`/`blockedBy` link) the Board's blocked-badge state.
  /// No-ops if constructed without a [TicketLinkRepository]. Also the new
  /// home for link *creation* itself — previously
  /// `ticket_metadata_section.dart`'s `TicketLinkPicker.onSelected`
  /// called [TicketLinkRepository.createLink] directly from the widget
  /// layer and separately triggered the same refreshes this method now
  /// does in one place, alongside [deleteTicketLink]/
  /// [updateTicketLinkType] — all three mutations go through this cubit
  /// consistently.
  Future<void> createTicketLink(
    String ticketId,
    String targetTicketId,
    TicketLinkType linkType,
  ) async {
    final linkRepo = _linkRepository;
    if (linkRepo == null) return;
    await linkRepo.createLink(
      sourceTicketId: ticketId,
      targetTicketId: targetTicketId,
      linkType: linkType,
    );
    await loadDocumentRelations(ticketId);
    if (linkType == TicketLinkType.blocks ||
        linkType == TicketLinkType.blockedBy) {
      await _refreshBlockedBoardState();
    }
  }

  /// Deletes the [linkId] row, then refreshes [ticketId]'s document
  /// relations and (if the deleted link was a `blocks`/`blockedBy` pair)
  /// the Board's blocked-badge state. No-ops if constructed without a
  /// [TicketLinkRepository].
  Future<void> deleteTicketLink(String ticketId, String linkId) async {
    final linkRepo = _linkRepository;
    if (linkRepo == null) return;
    final wasBlocking = await _linkInvolvesBlocking(linkId);
    await linkRepo.deleteLink(linkId);
    await loadDocumentRelations(ticketId);
    if (wasBlocking) await _refreshBlockedBoardState();
  }

  /// Updates the [linkId] row's stored type to [newRelativeType] — the
  /// type as picked in `LinkedTicketsSection`'s `_LinkTypeEditor`, i.e.
  /// *as it reads from [ticketId]'s own side*, not the row's raw
  /// source-to-target reading. Translated to the canonical value via
  /// [toCanonical] here (rather than by the caller) because that
  /// translation needs the row's actual [TicketLinkData.sourceTicketId]/
  /// `.targetTicketId` — data [LinkedTicketRef] deliberately doesn't
  /// carry, since nothing else needs it once a row's [LinkedTicketRef
  /// .relativeType] has already been resolved for display. Fetches the
  /// row once (via [TicketLinkRepository.getLinkById]) for both this
  /// translation and the same blocking-state check [deleteTicketLink]
  /// does, then persists and refreshes the same state [deleteTicketLink]
  /// does. A single repository call rather than a delete-then-recreate
  /// pair, so a retype is one write and one refresh with no partial-
  /// failure window. No-ops if constructed without a
  /// [TicketLinkRepository], or if [linkId] no longer exists.
  Future<void> updateTicketLinkType(
    String ticketId,
    String linkId,
    TicketLinkType newRelativeType,
  ) async {
    final linkRepo = _linkRepository;
    if (linkRepo == null) return;
    final row = await linkRepo.getLinkById(linkId);
    if (row == null) return;
    final wasBlocking =
        row.linkType == TicketLinkType.blocks.name ||
        row.linkType == TicketLinkType.blockedBy.name;
    final newCanonicalType = toCanonical(newRelativeType, row, ticketId);
    await linkRepo.updateLinkType(linkId, newCanonicalType);
    await loadDocumentRelations(ticketId);
    if (wasBlocking ||
        newCanonicalType == TicketLinkType.blocks ||
        newCanonicalType == TicketLinkType.blockedBy) {
      await _refreshBlockedBoardState();
    }
  }

  /// Whether the link row with id [linkId] is currently a `blocks`/
  /// `blockedBy` relationship — used by [deleteTicketLink]/
  /// [updateTicketLinkType] to skip [_refreshBlockedBoardState]'s extra
  /// query unless the mutation could actually change the Board's
  /// blocked-badge state, mirroring [createTicketLink]'s own
  /// `linkType == blocks || blockedBy` guard. Returns `false` if
  /// constructed without a [TicketLinkRepository], or if [linkId] no
  /// longer exists.
  Future<bool> _linkInvolvesBlocking(String linkId) async {
    final linkRepo = _linkRepository;
    if (linkRepo == null) return false;
    final row = await linkRepo.getLinkById(linkId);
    if (row == null) return false;
    return row.linkType == TicketLinkType.blocks.name ||
        row.linkType == TicketLinkType.blockedBy.name;
  }

  /// Runs an opt-in codebase-summarization scan at [depth] and drafts one
  /// root `signal` ticket per finding, each linked
  /// ([TicketLinkType.relatesTo]) back to a "Codebase Analysis —
  /// `<project name>`" run-record `signal` ticket that records the scan
  /// itself (both depths get a run-record ticket, for consistent
  /// traceability; only [SummarizationDepth.full] also spawns a visible
  /// `chat` child under it, since only that depth's agentic turn has a
  /// transcript worth persisting — see [_runFullSummarization]).
  /// Every resulting `signal` ticket flows through the existing,
  /// unmodified `promoteSignal` — no automatic ticket creation beyond
  /// what this explicit, user-triggered call already represents.
  ///
  /// Progress is reported on [codebaseAnalysisStatus], not [state]:
  /// [CodebaseAnalysisRunning] immediately, then either
  /// [CodebaseAnalysisDone] (carrying the created-ticket count, `0` if
  /// the model reported no findings) or [CodebaseAnalysisFailed]. No-ops
  /// into an immediate [CodebaseAnalysisFailed] if constructed without
  /// `projectRootPath`. Added for
  /// `aion-arch/changes/new-project-onboarding`.
  Future<void> runCodebaseSummarization({
    required SummarizationDepth depth,
  }) async {
    final rootPath = _projectRootPath;
    if (rootPath == null) {
      _codebaseAnalysisController.add(
        const CodebaseAnalysisFailed('No project directory to scan.'),
      );
      return;
    }

    _codebaseAnalysisController.add(CodebaseAnalysisRunning(depth: depth));

    final now = DateTime.now();
    final runTicket = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.signal,
      title: 'Codebase Analysis — ${_projectName ?? 'this project'}',
      description: depth == SummarizationDepth.shallow
          ? 'Shallow structural scan — detected stack and directory '
                'listing only, no file contents read.'
          : 'Full agentic scan — read the project\'s actual files via an '
                'isolated, read-only worktree.',
      status: TicketStatus.backlog,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createTicket(runTicket);
    final persistedRun = await _repository.getTicketById(runTicket.id);
    if (persistedRun == null) {
      _codebaseAnalysisController.add(
        const CodebaseAnalysisFailed('Could not start the analysis run.'),
      );
      return;
    }

    try {
      final findings = depth == SummarizationDepth.shallow
          ? await _runShallowSummarization(rootPath)
          : await _runFullSummarization(rootPath, persistedRun);

      var createdCount = 0;
      final linkRepo = _linkRepository;
      for (final finding in findings) {
        final findingNow = DateTime.now();
        final description = depth == SummarizationDepth.shallow
            ? '[Shallow scan — structural only, may be incomplete]\n\n'
                  '${finding.description}'
            : finding.description;
        final findingTicket = Ticket(
          id: _uuid.v4(),
          ticketId: '',
          type: TicketType.signal,
          title: finding.title,
          description: description,
          status: TicketStatus.backlog,
          createdAt: findingNow,
          updatedAt: findingNow,
        );
        await _repository.createTicket(findingTicket);
        if (linkRepo != null) {
          await linkRepo.createLink(
            sourceTicketId: findingTicket.id,
            targetTicketId: persistedRun.id,
            linkType: TicketLinkType.relatesTo,
          );
        }
        createdCount += 1;
      }

      _codebaseAnalysisController.add(CodebaseAnalysisDone(createdCount));
    } catch (e) {
      _codebaseAnalysisController.add(CodebaseAnalysisFailed(e.toString()));
    }
  }

  /// [SummarizationDepth.shallow] path for [runCodebaseSummarization]: a
  /// single non-tool-enabled call through the resolved [AgentProvider]'s
  /// client (never a [ChatCubit.runChatTurn] — there's no chat ticket to
  /// anchor a no-tool text turn to) fed [_shallowSummaryPrompt]'s
  /// detected-stack + directory-listing context. Throws [StateError] if
  /// constructed without a [ProviderRegistry], or if the model run itself
  /// reports an [AgentErrorEvent].
  Future<List<({String title, String description})>> _runShallowSummarization(
    String rootPath,
  ) async {
    final providerRegistry = _providerRegistry;
    if (providerRegistry == null) {
      throw StateError('Shallow codebase analysis requires an agent client.');
    }

    final detected = ProjectStackDetector().detect(rootPath);
    final listing = await _shallowDirectoryListing(rootPath);
    final prompt = _shallowSummaryPrompt(detected, listing);
    final (model, provider) = await _resolveModelAndProvider(
      ModelPhase.frontier,
    );

    final buffer = StringBuffer();
    final events = await provider.client.run(
      AgentRequest(prompt: prompt, model: model.modelId),
    );
    await for (final event in events) {
      switch (event) {
        case AgentTextEvent(:final text):
          buffer.write(text);
          _codebaseAnalysisController.add(
            CodebaseAnalysisRunning(
              depth: SummarizationDepth.shallow,
              statusText: _lastLine(buffer.toString()),
            ),
          );
        case AgentDoneEvent():
          break;
        case AgentOverageDetectedEvent():
          break;
        case AgentToolUseEvent():
          break; // toolsEnabled is false — not expected, ignored defensively.
        case AgentErrorEvent(:final message):
          throw StateError(message);
      }
    }
    return _parseSummaryFindings(buffer.toString());
  }

  /// [SummarizationDepth.full] path for [runCodebaseSummarization]:
  /// mirrors [_runCodingExecution]'s worktree-isolation shape exactly —
  /// a fresh [GitRepositoryClient.createWorktree] (never [rootPath]
  /// itself), a visible `chat` child spawned under [runTicket] so the
  /// scan's live progress is inspectable, then one tool-enabled
  /// [ChatCubit.runChatTurn] fed [_fullSummaryPrompt] (explicitly
  /// read-only — never instructs the model to edit/commit/push). The
  /// worktree is always removed in a `finally`, exactly like
  /// [_runCodingExecution]'s own cleanup, even though nothing is ever
  /// pushed from it. Throws [StateError] if constructed without a
  /// [ProviderRegistry]/[CommentRepository]/[GitRepositoryClient], if the
  /// spawned chat can't be persisted, or if the model turn doesn't
  /// complete successfully.
  Future<List<({String title, String description})>> _runFullSummarization(
    String rootPath,
    Ticket runTicket,
  ) async {
    final providerRegistry = _providerRegistry;
    final commentRepo = _commentRepository;
    final gitClient = _gitClient;
    if (providerRegistry == null || commentRepo == null || gitClient == null) {
      throw StateError(
        'Full codebase analysis requires an agent client, comment '
        'repository, and git client.',
      );
    }

    final worktreePath = Directory.systemTemp
        .createTempSync('aion_analysis_')
        .path;
    final branchName = 'aion/analysis-${runTicket.id}';

    final now = DateTime.now();
    final chatTicket = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.chat,
      title: runTicket.title,
      status: TicketStatus.backlog,
      parentId: runTicket.id,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createTicket(chatTicket);
    final persistedChat = await _repository.getTicketById(chatTicket.id);
    if (persistedChat == null) {
      throw StateError('Could not create the analysis chat.');
    }

    try {
      await gitClient.createWorktree(rootPath, worktreePath, branchName);

      final prompt = _fullSummaryPrompt(runTicket.title);
      await commentRepo.addComment(
        TicketComment(
          id: '',
          ticketId: persistedChat.id,
          content: prompt,
          authorType: CommentAuthorType.system,
          createdAt: DateTime.now(),
        ),
      );

      final (model, provider) = await _resolveModelAndProvider(
        ModelPhase.execution,
      );
      final succeeded = await ChatCubit.runChatTurn(
        client: provider.client,
        provider: provider,
        commentRepo: commentRepo,
        chatTicketId: persistedChat.id,
        prompt: prompt,
        model: model,
        toolsEnabled: true,
        workingDirectory: worktreePath,
        onChunk: (textSoFar) => _codebaseAnalysisController.add(
          CodebaseAnalysisRunning(
            depth: SummarizationDepth.full,
            statusText: _lastLine(textSoFar),
          ),
        ),
        onToolUse: (toolName, summary) => _codebaseAnalysisController.add(
          CodebaseAnalysisRunning(
            depth: SummarizationDepth.full,
            statusText: summary == null
                ? 'Running $toolName...'
                : 'Running $toolName: $summary...',
          ),
        ),
      );
      if (!succeeded) {
        throw StateError('The analysis turn did not complete successfully.');
      }

      final reply = await _lastCommentContent(persistedChat.id);
      return _parseSummaryFindings(reply ?? '');
    } finally {
      try {
        await gitClient.removeWorktree(rootPath, worktreePath);
      } catch (_) {
        // Best-effort cleanup only, mirrors _runCodingExecution's own
        // finally block — createWorktree may itself have failed, in
        // which case there's nothing to remove.
      }
    }
  }

  /// Returns a newline-joined, depth-limited (default 2 levels) listing
  /// of [rootPath]'s entries (directories suffixed `/`), skipping Aion's
  /// own bookkeeping (`.aion/`, `tickets/`) and `.git/` — names only, no
  /// file content. Capped at [maxEntries] total entries so a very large
  /// repository can't blow out [_shallowSummaryPrompt]'s token cost.
  /// Unreadable subdirectories are silently skipped. Added for
  /// `aion-arch/changes/new-project-onboarding`.
  Future<String> _shallowDirectoryListing(
    String rootPath, {
    int maxDepth = 2,
    int maxEntries = 200,
  }) async {
    final entries = <String>[];

    void walk(Directory dir, int depth) {
      if (depth > maxDepth || entries.length >= maxEntries) return;
      List<FileSystemEntity> children;
      try {
        children = dir.listSync();
      } catch (_) {
        return;
      }
      for (final child in children) {
        if (entries.length >= maxEntries) return;
        final name = p.basename(child.path);
        if (name == '.git' || name == '.aion' || name == 'tickets') continue;
        final relative = p.relative(child.path, from: rootPath);
        final isDir = child is Directory;
        entries.add(isDir ? '$relative/' : relative);
        if (isDir) walk(child, depth + 1);
      }
    }

    walk(Directory(rootPath), 0);
    return entries.join('\n');
  }

  /// Assembles [_runShallowSummarization]'s prompt: [detected]'s stack
  /// (if any) plus [listing] (from [_shallowDirectoryListing]),
  /// instructing the model to reply with one or more `FINDING:`-prefixed
  /// entries terminated by a `SUMMARY: DONE` line — parsed by
  /// [_parseSummaryFindings]. Added for
  /// `aion-arch/changes/new-project-onboarding`.
  String _shallowSummaryPrompt(DetectedStack? detected, String listing) {
    final buffer = StringBuffer()
      ..writeln(
        'You are looking at the top-level structure of a software '
        'project — not its file contents. Based only on the information '
        'below, identify up to 5 notable things worth turning into '
        'starting project-management tickets (apparent major '
        'components, missing conventional files, anything structurally '
        'unusual).',
      )
      ..writeln();
    if (detected != null) {
      buffer
        ..writeln('Detected stack: ${detected.language}')
        ..writeln();
    }
    buffer
      ..writeln('Directory listing (depth-limited, names only):')
      ..writeln(listing.isEmpty ? '(empty or unreadable)' : listing)
      ..writeln()
      ..writeln('For each finding, reply in exactly this format:')
      ..writeln('FINDING: <short title>')
      ..writeln('<one to two sentence description>')
      ..writeln()
      ..writeln('End your reply with exactly one line: "SUMMARY: DONE".');
    return buffer.toString().trim();
  }

  /// Assembles [_runFullSummarization]'s prompt for the analysis run
  /// titled [runTitle] — asks the model to explore the project's actual
  /// files with the available read tools and reply in the same
  /// `FINDING:`/`SUMMARY: DONE` format [_shallowSummaryPrompt] uses, so
  /// [_parseSummaryFindings] handles both depths identically.
  /// Explicitly read-only: unlike [_assembleExecutionContext], this
  /// never instructs the model to edit, commit, or push — the worktree
  /// is discarded, never pushed, once this turn finishes (see
  /// [_runFullSummarization]). Added for
  /// `aion-arch/changes/new-project-onboarding`.
  String _fullSummaryPrompt(String runTitle) {
    return 'You are exploring an existing codebase ("$runTitle") to help '
        'draft a starting project-management backlog for it. Read '
        'whatever files you need using the available tools — do not '
        'edit, commit, or otherwise modify anything; this is a '
        'read-only exploration.\n\n'
        'Identify up to 8 notable things worth turning into starting '
        'tickets (major components, apparent gaps, technical debt, '
        'missing tests, anything structurally notable).\n\n'
        'For each finding, reply in exactly this format:\n'
        'FINDING: <short title>\n'
        '<one to three sentence description>\n\n'
        'End your reply with exactly one line: "SUMMARY: DONE".';
  }

  /// Parses a summarization reply (from either
  /// [_runShallowSummarization] or [_runFullSummarization]) into
  /// `(title, description)` finding pairs — every `FINDING: <title>`
  /// line starts a new finding; every line until the next `FINDING:` or
  /// the terminal `SUMMARY: DONE` line becomes that finding's
  /// description. A finding with an empty title is dropped. Added for
  /// `aion-arch/changes/new-project-onboarding`.
  List<({String title, String description})> _parseSummaryFindings(
    String reply,
  ) {
    final findings = <({String title, String description})>[];
    String? currentTitle;
    final currentBody = StringBuffer();

    void flush() {
      final title = currentTitle?.trim();
      if (title != null && title.isNotEmpty) {
        findings.add((
          title: title,
          description: currentBody.toString().trim(),
        ));
      }
      currentBody.clear();
    }

    for (final line in reply.split('\n')) {
      final trimmed = line.trim();
      final findingMatch = RegExp(r'^FINDING:\s*(.*)$').firstMatch(trimmed);
      if (findingMatch != null) {
        flush();
        currentTitle = findingMatch.group(1);
        continue;
      }
      if (trimmed == 'SUMMARY: DONE') {
        flush();
        currentTitle = null;
        return findings;
      }
      if (currentTitle != null) {
        currentBody.writeln(line);
      }
    }
    flush();
    return findings;
  }

  /// Returns the last non-empty line of [text], or `null` if [text] has
  /// none — a short live-status snippet for [CodebaseAnalysisRunning].
  /// Added for `aion-arch/changes/new-project-onboarding`.
  String? _lastLine(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return lines.isEmpty ? null : lines.last.trim();
  }
}
