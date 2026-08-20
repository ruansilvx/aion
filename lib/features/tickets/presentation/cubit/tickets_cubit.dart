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
import 'package:aion/core/contracts/agent_tool_definition.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/core/git/github_cli_client.dart';
import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/execution_context_cap_repository.dart';
import 'package:aion/features/providers/domain/repositories/execution_scheduling_repository.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/data/services/active_ticket_view_registry.dart';
import 'package:aion/features/tickets/data/services/page_wikilink_indexer.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/data/services/ticket_parent_change_result.dart';
import 'package:aion/features/tickets/data/services/ticket_parent_trash_service.dart';
import 'package:aion/features/tickets/domain/entities/backlink_ref.dart';
import 'package:aion/features/tickets/domain/entities/chat_turn_result.dart';
import 'package:aion/features/tickets/domain/entities/execution_queue_entry.dart';
import 'package:aion/features/tickets/domain/entities/gap_or_question_ref.dart';
import 'package:aion/features/tickets/domain/entities/linked_ticket_ref.dart';
import 'package:aion/features/tickets/domain/entities/skill_attachment.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/workflow_prompt_template.dart';
import 'package:aion/features/tickets/domain/entities/ticket_board_column_visibility.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_filters.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_view_mode.dart';
import 'package:aion/features/tickets/domain/enums/backlink_origin.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/summarization_depth.dart';
import 'package:aion/features/tickets/domain/enums/ticket_complexity.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_severity.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/enums/skill_attachment_kind.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';
import 'package:aion/features/tickets/domain/entities/default_workflow_statuses.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/domain/repositories/execution_queue_repository.dart';
import 'package:aion/features/tickets/domain/repositories/page_wikilink_repository.dart';
import 'package:aion/features/tickets/domain/repositories/sdd_stage_config_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_board_column_visibility_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_filter_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_sort_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_view_mode_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/domain/repositories/workflow_prompt_template_repository.dart';
import 'package:aion/features/tickets/domain/repositories/workflow_skill_attachment_repository.dart';
import 'package:aion/features/tickets/domain/repositories/workflow_status_repository.dart';
import 'package:aion/features/tickets/domain/utils/render_workflow_prompt_template.dart';
import 'package:aion/features/tickets/domain/utils/ticket_link_direction.dart';
import 'package:aion/features/tickets/domain/utils/ticket_rollup_calculator.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_branch_tool_definitions.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/codebase_analysis_status.dart';
import 'package:aion/features/tickets/presentation/cubit/in_flight_execution_run.dart';
import 'package:aion/features/tickets/presentation/cubit/pending_tool_proposal.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_context_enricher.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_estimation_suggester.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_token_predictor.dart';
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
  /// [pageWikilinkRepository] follows the same optional-dependency
  /// pattern once more — `null` (every existing construction site except
  /// `app_router.dart`) makes [updateTicket]'s wikilink reindex/rename-
  /// cascade step and [loadDocumentRelations]'s wikilink-origin backlinks
  /// merge both no-op; real usage (`app_router.dart`) always supplies
  /// one. [activeTicketViewRegistry] is the *existing* desktop-only
  /// registry `TicketMarkdownWatcherService`/`TicketRepairCubit` already
  /// use — reused here (not a second instance) to defer, rather than
  /// clobber, a rename-triggered rewrite of a page the user currently has
  /// open; `null` on mobile/web, where that deferral simply never
  /// triggers (no separate file-watcher write path to race against
  /// there). Both added for `aion-arch/changes/inline-wikilink-backlinks`.
  /// [executionSchedulingRepository]/[executionQueueRepository] follow the
  /// same optional-dependency pattern once more — `null`
  /// (every existing construction site except `app_router.dart`) makes
  /// [_effectiveConcurrencyCeiling] always resolve
  /// [ExecutionSchedulingMode.strictFifo] (today's unchanged behavior) and
  /// [restoreExecutionQueue]/[_persistExecutionQueueSnapshot] both no-op;
  /// real usage (`app_router.dart`) always supplies both. Added for
  /// `aion-arch/changes/parallel-work`.
  /// [workflowStatusRepository]/[sddStageConfigRepository] follow the same
  /// optional-dependency pattern once more, deliberately — unlike every
  /// other new dependency listed above, these two back *every* gate/
  /// trigger this cubit already performs on ticket status (see
  /// [_workflowStatuses]/[_resolveStatus]/[_roleOf]), so making them
  /// `required` would force every one of ~40 existing construction sites
  /// (most of them tests unrelated to workflow configuration) to start
  /// supplying both just to compile. `null` (every existing construction
  /// site except `app_router.dart`) makes [_workflowStatuses] stay pinned
  /// to [defaultWorkflowStatuses] and [_designStagesEnabled] always
  /// resolve `true` — exactly the pre-configuration hardcoded behavior
  /// every gate/trigger already had, so an unconfigured/test cubit is
  /// unaffected. Real usage (`app_router.dart`) always supplies both. Added
  /// for `aion-arch/changes/configurable-ticket-workflow`.
  /// [workflowSkillAttachmentRepository]/[workflowPromptTemplateRepository]
  /// follow the same optional-dependency convention once more — `null`
  /// (every existing construction site except `app_router.dart`) pins
  /// [_skillAttachments] to `const []` forever, so
  /// [_attachmentForStatus]/[_attachmentForStage] always resolve `null`
  /// and no attachment ever fires — exactly Phase 1's behavior, byte for
  /// byte. Real usage (`app_router.dart`) always supplies both. Added for
  /// `aion-arch/changes/workflow-skill-attachments`.
  // The public param names below (embeddingProvider/gitProjector/
  // projectRootPath/providerRegistry/commentRepository/
  // automationSettingsRepository/modelRoutingRepository/gitClient/
  // gitHubClient/baselineRepository/projectId/baselineVersion/
  // projectName/filterRepository/sortRepository/viewModeRepository/
  // boardColumnVisibilityRepository/pageWikilinkRepository/
  // activeTicketViewRegistry/executionSchedulingRepository/
  // executionQueueRepository/workflowSkillAttachmentRepository/
  // workflowPromptTemplateRepository) intentionally differ from their private
  // backing fields; a private identifier can't be used as an external
  // named-parameter label from another library, so `this._foo` shorthand
  // isn't usable here.
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
    TicketListViewModeRepository? viewModeRepository,
    TicketBoardColumnVisibilityRepository? boardColumnVisibilityRepository,
    PageWikilinkRepository? pageWikilinkRepository,
    ActiveTicketViewRegistry? activeTicketViewRegistry,
    ExecutionSchedulingRepository? executionSchedulingRepository,
    ExecutionQueueRepository? executionQueueRepository,
    WorkflowStatusRepository? workflowStatusRepository,
    SddStageConfigRepository? sddStageConfigRepository,
    WorkflowSkillAttachmentRepository? workflowSkillAttachmentRepository,
    WorkflowPromptTemplateRepository? workflowPromptTemplateRepository,
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
    _viewModeRepository = viewModeRepository;
    _boardColumnVisibilityRepository = boardColumnVisibilityRepository;
    _pageWikilinkRepository = pageWikilinkRepository;
    _executionSchedulingRepository = executionSchedulingRepository;
    _executionQueueRepository = executionQueueRepository;
    _workflowStatusRepository = workflowStatusRepository;
    _sddStageConfigRepository = sddStageConfigRepository;
    _workflowSkillAttachmentRepository = workflowSkillAttachmentRepository;
    _workflowPromptTemplateRepository = workflowPromptTemplateRepository;
    _workflowStatusChangesSubscription = workflowStatusRepository?.onChanged
        .listen((_) => _loadWorkflowStatuses());
    unawaited(_loadWorkflowStatuses());
    _skillAttachmentChangesSubscription = workflowSkillAttachmentRepository
        ?.onChanged
        .listen((_) => _loadSkillAttachments());
    unawaited(_loadSkillAttachments());
    _rollupRecomputer = TicketRollupRecomputer(
      _repository,
      gitProjector: gitProjector,
      projectRootPath: projectRootPath,
    );
    _parentTrashService = TicketParentTrashService(
      _repository,
      gitProjector: gitProjector,
      projectRootPath: projectRootPath,
    );
    _estimationSuggester = TicketEstimationSuggester(
      _repository,
      embeddingProvider: embeddingProvider,
      providerRegistry: providerRegistry,
      modelRoutingRepository: modelRoutingRepository,
    );
    _tokenPredictor = TicketTokenPredictor(
      _repository,
      embeddingProvider: embeddingProvider,
    );
    _contextEnricher = TicketContextEnricher(
      _repository,
      linkRepository: linkRepository,
      embeddingProvider: embeddingProvider,
    );
    _wikilinkIndexer = pageWikilinkRepository == null
        ? null
        : PageWikilinkIndexer(
            _repository,
            pageWikilinkRepository,
            activeTicketViewRegistry,
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

  /// Shared parentId-reparent and trash domain logic — see
  /// [TicketParentTrashService]. Wired to the same [_repository]/
  /// [_gitProjector]/[_projectRootPath] this cubit already holds, so
  /// [updateTicketParent]/[trashTicket] delegate to one instance instead
  /// of duplicating validation/cascade logic that
  /// `TicketMarkdownReconciler`/`TicketRepairService` also need.
  late final TicketParentTrashService _parentTrashService;

  /// AI-assisted complexity/estimate suggestion orchestrator — see
  /// [TicketEstimationSuggester]. Wired to the same [_repository]/
  /// [_embeddingProvider]/[_providerRegistry]/[_modelRoutingRepository]
  /// this cubit already holds.
  late final TicketEstimationSuggester _estimationSuggester;

  /// Deterministic pre-execution token-cost prediction orchestrator — see
  /// [TicketTokenPredictor]. Wired to the same [_repository]/
  /// [_embeddingProvider] this cubit already holds, constructed alongside
  /// [_estimationSuggester]. Added for
  /// `aion-arch/changes/token-cost-prediction`.
  late final TicketTokenPredictor _tokenPredictor;

  /// Task/Bug id → total coding-execution token spend recorded so far —
  /// the in-memory running-total cache backing
  /// [TicketsLoaded.executionTokenTotals]/
  /// [TicketDetailLoaded.executionTokenTotal]. Fully reconstructable at
  /// any time from [TicketRepository.getExecutionTokenTotals] (this is a
  /// cache, not the source of truth — the persisted comment rows are),
  /// which is exactly what [loadTickets]/[loadMoreTickets]/
  /// [getTicketById] do to batch-seed any not-yet-cached id. Once seeded,
  /// an entry is only ever incremented in place by
  /// [_runCodingExecution]'s own turn-completion points — never
  /// recomputed from scratch on every read, the same "seed once, update
  /// incrementally" shape [_inFlightExecutionIds] and its siblings
  /// already use. Deliberately untouched by
  /// [_refreshInFlightBoardState]'s own recompute walk — that method
  /// mirrors this cache's *current* contents into every fresh
  /// [TicketsLoaded] emission, but never mutates it, so a scheduling-only
  /// event (a run starting/stopping) can't accidentally reset a token
  /// total that has nothing to do with scheduling. Added for
  /// `aion-arch/changes/token-cost-prediction`.
  final Map<String, int> _executionTokenTotals = {};

  /// Shared related-tickets context-assembly walk — see
  /// [TicketContextEnricher]. Wired to the same [_repository]/
  /// [_linkRepository]/[_embeddingProvider] this cubit already holds.
  late final TicketContextEnricher _contextEnricher;
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

  /// Backs [currentViewMode]/[setViewMode]/[loadPersistedViewMode] — see
  /// those methods. `null` (the default, and every existing test/call
  /// site) makes [setViewMode] skip persistence (the in-memory override
  /// still works) and [loadPersistedViewMode] a no-op; real usage
  /// (`app_router.dart`) always supplies one. Added for
  /// `aion-arch/changes/list-board-view-and-column-visibility`.
  late final TicketListViewModeRepository? _viewModeRepository;

  /// Backs [hiddenBoardColumns]/[toggleBoardColumnVisibility]/
  /// [loadPersistedBoardColumnVisibility] — see those methods. Same
  /// optional-dependency convention as [_viewModeRepository]. Added for
  /// `aion-arch/changes/list-board-view-and-column-visibility`.
  late final TicketBoardColumnVisibilityRepository?
  _boardColumnVisibilityRepository;

  late final PageWikilinkRepository? _pageWikilinkRepository;

  /// Persists the user's coding-execution scheduling mode/concurrency
  /// ceiling — see [_effectiveConcurrencyCeiling]. `null` (every existing
  /// construction site except `app_router.dart`) makes scheduling always
  /// resolve [ExecutionSchedulingMode.strictFifo]. Added for
  /// `aion-arch/changes/parallel-work`.
  late final ExecutionSchedulingRepository? _executionSchedulingRepository;

  /// Persists the in-flight/queued coding-execution snapshot across an
  /// app restart — see [restoreExecutionQueue]/
  /// [_persistExecutionQueueSnapshot]. `null` (every existing construction
  /// site except `app_router.dart`) makes both no-op. Added for
  /// `aion-arch/changes/parallel-work`.
  late final ExecutionQueueRepository? _executionQueueRepository;

  /// Shared inline-wikilink reindex/rename-cascade logic — see
  /// [PageWikilinkIndexer]. `null` whenever this cubit was constructed
  /// without a [PageWikilinkRepository], mirroring every other optional-
  /// dependency service field above.
  late final PageWikilinkIndexer? _wikilinkIndexer;

  /// Persists the project's configured [WorkflowStatus] set. `null`
  /// (every existing construction site except `app_router.dart`) pins
  /// [_workflowStatuses] to [defaultWorkflowStatuses] forever — see the
  /// constructor's own dartdoc. Added for
  /// `aion-arch/changes/configurable-ticket-workflow`.
  late final WorkflowStatusRepository? _workflowStatusRepository;

  /// Persists the project's `SddStage` configuration. `null` makes
  /// [_designStagesEnabled] always resolve `true` and the stage
  /// display-name resolution point always fall back to each stage's own
  /// hardcoded name. Added for
  /// `aion-arch/changes/configurable-ticket-workflow`.
  late final SddStageConfigRepository? _sddStageConfigRepository;

  /// Persists the project's configured [SkillAttachment] set. `null`
  /// (every existing construction site except `app_router.dart`) pins
  /// [_skillAttachments] to `const []` forever — see the constructor's
  /// own dartdoc. Added for `aion-arch/changes/workflow-skill-attachments`.
  late final WorkflowSkillAttachmentRepository? _workflowSkillAttachmentRepository;

  /// Persists the project's [WorkflowPromptTemplate] set, consulted by
  /// [_promptFor] to render an [SkillAttachmentKind.aionNativeTemplate]
  /// attachment's prompt. `null` makes [_promptFor] fall back to a
  /// defensive placeholder for that kind (see its own dartdoc). Added for
  /// `aion-arch/changes/workflow-skill-attachments`.
  late final WorkflowPromptTemplateRepository? _workflowPromptTemplateRepository;

  /// The project's currently-configured [WorkflowStatus] set — every
  /// scope, shared base and every per-type extension together. Loaded
  /// once at construction ([_loadWorkflowStatuses], fired from the
  /// constructor body without being awaited — a cubit is usable
  /// immediately with [defaultWorkflowStatuses] as its baseline, then
  /// silently upgrades to the real configured set once the async load
  /// resolves) and refreshed every time [_workflowStatusRepository]
  /// fires [WorkflowStatusRepository.onChanged] (i.e. whenever
  /// `WorkflowConfigCubit` persists an edit) — the two Cubits stay
  /// consistent through the shared repository, never a direct reference
  /// to each other. Every place that used to gate on a literal
  /// `TicketStatus` value now resolves through [_resolveStatus]/[_roleOf]
  /// against this list instead. See
  /// `aion-arch/changes/configurable-ticket-workflow/design.md` §3.
  List<WorkflowStatus> _workflowStatuses = defaultWorkflowStatuses;

  /// Subscription driving [_workflowStatuses]'s live refresh — see that
  /// field's dartdoc. `null` whenever this cubit was constructed without
  /// a [WorkflowStatusRepository]. Cancelled in [close].
  StreamSubscription<void>? _workflowStatusChangesSubscription;

  /// Reloads [_workflowStatuses] from [_workflowStatusRepository]. A
  /// no-op (leaving [_workflowStatuses] at its current value) when this
  /// cubit was constructed without one, or when the repository currently
  /// has no rows (defensive — `seedDefaultsIfEmpty` should always have
  /// run before this cubit is used, but an empty result must never
  /// silently strand every gate/trigger with no `WorkflowStatusRole`
  /// holder at all).
  Future<void> _loadWorkflowStatuses() async {
    final repository = _workflowStatusRepository;
    if (repository == null) return;
    final statuses = await repository.getAll();
    if (isClosed) return;
    if (statuses.isEmpty) return;
    _workflowStatuses = statuses;
  }

  /// Resolves [status] (a raw [Ticket.status] string) to its configured
  /// [WorkflowStatus], or `null` if it's not present in
  /// [_workflowStatuses]'s currently-cached scope — e.g. a status the
  /// project has since deleted. Existence beyond the cache is defensive
  /// only; a ticket whose status was deleted out from under it still
  /// round-trips safely as "no role."
  WorkflowStatus? _resolveStatus(String status) =>
      _workflowStatuses.where((s) => s.name == status).firstOrNull;

  /// The [WorkflowStatusRole] [status] currently fills, or `null` if it
  /// fills none (or doesn't resolve at all — see [_resolveStatus]). The
  /// generalized replacement for every literal `TicketStatus.inProgress`/
  /// `.inReview`/`.done` comparison this cubit used to perform.
  WorkflowStatusRole? _roleOf(String status) => _resolveStatus(status)?.role;

  /// The project's currently-configured [SkillAttachment] set. Loaded
  /// once at construction ([_loadSkillAttachments], fired from the
  /// constructor body without being awaited, mirroring
  /// [_workflowStatuses]'s own load-then-upgrade shape) and refreshed
  /// every time [_workflowSkillAttachmentRepository] fires
  /// [WorkflowSkillAttachmentRepository.onChanged] (i.e. whenever
  /// `WorkflowConfigCubit` persists an attachment edit). Defaults to
  /// `const []` — the correct empty baseline (unlike
  /// [_workflowStatuses]'s `defaultWorkflowStatuses` fallback, there is
  /// no pre-configuration attachment behavior to reproduce). See
  /// `aion-arch/changes/workflow-skill-attachments/design.md` §3.1.
  List<SkillAttachment> _skillAttachments = const [];

  /// Subscription driving [_skillAttachments]'s live refresh — see that
  /// field's dartdoc. `null` whenever this cubit was constructed without
  /// a [WorkflowSkillAttachmentRepository]. Cancelled in [close].
  StreamSubscription<void>? _skillAttachmentChangesSubscription;

  /// Reloads [_skillAttachments] from [_workflowSkillAttachmentRepository].
  /// A no-op (leaving [_skillAttachments] at its current value) when this
  /// cubit was constructed without one.
  Future<void> _loadSkillAttachments() async {
    final repository = _workflowSkillAttachmentRepository;
    if (repository == null) return;
    final attachments = await repository.getAll();
    if (isClosed) return;
    _skillAttachments = attachments;
  }

  /// The [SkillAttachment] configured to fire on entry to the
  /// `WorkflowStatus` with id [workflowStatusId], or `null` if none is
  /// configured — the target has at most one, enforced by
  /// `WorkflowConfigCubit.createAttachment`/`.updateAttachment`.
  SkillAttachment? _attachmentForStatus(String workflowStatusId) =>
      _skillAttachments
          .where((a) => a.workflowStatusId == workflowStatusId)
          .firstOrNull;

  /// The [SkillAttachment] configured to fire on entry to [stage], or
  /// `null` if none is configured. Same at-most-one guarantee as
  /// [_attachmentForStatus].
  SkillAttachment? _attachmentForStage(SddStage stage) =>
      _skillAttachments.where((a) => a.sddStage == stage).firstOrNull;

  /// The status every new ticket is created at — the shared-base set's
  /// lowest-[WorkflowStatus.sortOrder] status's name (today's hardcoded
  /// `TicketStatus.backlog` literal, generalized). Falls back to
  /// `'backlog'` only if [_workflowStatuses] somehow holds no shared-base
  /// status at all — defensive, since [defaultWorkflowStatuses] and every
  /// real configured set always has one; this literal is effectively
  /// unreachable in practice, same as [_reviewReadyStatus]/[_doneStatus]'s
  /// own fallbacks below.
  String get _defaultCreationStatus {
    final base = _workflowStatuses.where((s) => s.ticketType == null).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return base.isEmpty ? 'backlog' : base.first.name;
  }

  /// The name of the shared-base status currently holding
  /// [WorkflowStatusRole.reviewReady] — what a successful coding-execution
  /// run auto-writes to (today's hardcoded `TicketStatus.inReview`
  /// literal, generalized). Falls back to `'inReview'` only if
  /// [_workflowStatuses] somehow holds no status with this role —
  /// defensive, since [defaultWorkflowStatuses] and every real configured
  /// set (`WorkflowConfigCubit` enforces the role invariant — see
  /// `WorkflowConfigCubit.updateStatus`/`.deleteStatus`'s rejection of any
  /// edit that would leave a role with no holder) always has one, so this
  /// literal is effectively unreachable in practice.
  String get _reviewReadyStatus =>
      _workflowStatuses
          .where((s) => s.role == WorkflowStatusRole.reviewReady)
          .firstOrNull
          ?.name ??
      'inReview';

  /// The name of the shared-base status currently holding
  /// [WorkflowStatusRole.done] (today's hardcoded `TicketStatus.done`
  /// literal, generalized). Same unreachable-in-practice defensive
  /// fallback as [_reviewReadyStatus].
  String get _doneStatus =>
      _workflowStatuses
          .where((s) => s.role == WorkflowStatusRole.done)
          .firstOrNull
          ?.name ??
      'done';

  /// Every configured status name, ordered by [WorkflowStatus.sortOrder]
  /// ascending (first occurrence wins on a name collision across scopes)
  /// — passed to [TicketRepository.searchTickets] as `statusSortOrder` so
  /// `TicketSortField.status` orders by each ticket's resolved
  /// `WorkflowStatus.sortOrder` rather than a fixed enum declaration
  /// order. See `aion-arch/changes/configurable-ticket-workflow/design.md`
  /// §5.2.
  List<String> get _statusSortOrder {
    final sorted = [..._workflowStatuses]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final seen = <String>{};
    return [
      for (final s in sorted)
        if (seen.add(s.name)) s.name,
    ];
  }

  /// Whether Epics/Stories must clear the `designBrief`/`designSync`
  /// stage cycle before execution — [_sddStageConfigRepository]'s
  /// persisted setting, or `true` (matching
  /// `SharedPrefsSddStageConfigRepository`'s own default) when this cubit
  /// was constructed without one.
  Future<bool> _designStagesEnabled() async {
    final repository = _sddStageConfigRepository;
    if (repository == null) return true;
    return repository.getDesignStagesEnabled();
  }

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

  /// Fires [detailTick] every 60 seconds while a [TicketDetailScreen] is
  /// mounted — see [startDetailTicker]/[stopDetailTicker]. `null`
  /// whenever no detail screen currently has it running. Cancelled in
  /// [close].
  Timer? _detailTickTimer;

  /// Broadcasts an empty pulse once a minute while [_detailTickTimer] is
  /// running, purely so [TicketDetailScreen]'s "Updated {relative}"
  /// label can rebuild off elapsed wall-clock time without a
  /// [TicketsState] emission — see design.md §2 for why a state
  /// re-emit isn't used. Not tied to [state] the same way
  /// `codebaseAnalysisStatus` isn't.
  final _detailTickController = StreamController<void>.broadcast();

  /// See [_detailTickController]'s dartdoc.
  Stream<void> get detailTick => _detailTickController.stream;

  /// Starts (or restarts) the 60-second [detailTick] pulse. Called by
  /// [TicketDetailScreen.initState] — idempotent, so re-navigating
  /// between two tickets (a fresh screen instance each time) safely
  /// cancels any previous timer before starting its own.
  void startDetailTicker() {
    _detailTickTimer?.cancel();
    _detailTickTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!isClosed) _detailTickController.add(null);
    });
  }

  /// Stops the [detailTick] pulse started by [startDetailTicker]. Called
  /// by [TicketDetailScreen.dispose] so the timer doesn't keep firing
  /// into an empty stream once no detail screen is mounted to consume
  /// it — [TicketsCubit] is a single app-wide instance (see
  /// `aion-arch/ideas/live-refresh-open-ticket-detail-screen.md`), so
  /// nothing else would stop it otherwise.
  void stopDetailTicker() {
    _detailTickTimer?.cancel();
    _detailTickTimer = null;
  }

  /// The active project's display name, if this cubit was constructed
  /// with one (`app_router.dart` always supplies it). Read by
  /// `CodebaseAnalysisBanner` to name the codebase in its offer copy —
  /// `null` falls back to generic wording. Added for
  /// `aion-arch/changes/new-project-onboarding`.
  String? get projectName => _projectName;

  @override
  Future<void> close() {
    _codebaseAnalysisController.close();
    _detailTickTimer?.cancel();
    unawaited(_detailTickController.close());
    unawaited(_workflowStatusChangesSubscription?.cancel());
    unawaited(_skillAttachmentChangesSubscription?.cancel());
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

  /// Task/Bug ids with a coding-execution run currently in flight —
  /// replaces the single-slot `_inFlightExecutionTaskId` this cubit used
  /// before `aion-arch/changes/parallel-work` to support
  /// [ExecutionSchedulingMode.parallel]/[ExecutionSchedulingMode.hybrid]'s
  /// concurrent runs. Persisted (see [_persistExecutionQueueSnapshot])
  /// but rebuilt from scratch on every app launch via
  /// [restoreExecutionQueue] — this in-memory field itself does not
  /// survive a restart.
  final Set<String> _inFlightExecutionIds = {};

  /// Each entry in [_inFlightExecutionIds]'s currently-active model turn,
  /// keyed by Task/Bug id — see [InFlightExecutionRun]. Updated every time
  /// [_runCodingExecution] starts a fresh implement/verify turn, read by
  /// [cancelCodingExecution] to resolve which run to cancel.
  final Map<String, InFlightExecutionRun> _inFlightRuns = {};

  /// Each currently-in-flight-or-queued Task/Bug's [Ticket.status]
  /// immediately before it moved to a status holding
  /// [WorkflowStatusRole.executionTrigger] — captured by
  /// [_interceptTaskExecutionTrigger]'s allowed path (and
  /// [updateStatusForTickets]'s own gate loop) right before the write,
  /// consumed by [cancelCodingExecution] to know which status to revert
  /// to on cancel.
  final Map<String, String> _preExecutionStatus = {};

  /// Task ids waiting to start, FIFO — index 0 is next in line, though
  /// under [ExecutionSchedulingMode.hybrid] a later-queued id may start
  /// ahead of it if index 0's parent already has an in-flight sibling
  /// (see [_nextEligibleForHybrid]).
  final List<String> _executionQueue = [];

  /// Interrupted coding-execution runs [restoreExecutionQueue] found on
  /// this launch under [AutomationConfidence.gated], surfaced via
  /// [TicketsLoaded.pendingResumePrompt] for `ResumeRunsPrompt` to render
  /// — `null` once nothing is pending (the default), or after
  /// [resumePendingExecutions]/[dismissPendingResumePrompt] clears it.
  List<Ticket>? _pendingResumeTickets;

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
  Set<String> _lastStatuses = const {};
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

  /// The status names currently selected in the ticket list's Filters
  /// popover — mirrors [_lastStatuses], exposed read-only for the
  /// screen/popover to render checked state and the chip row against.
  Set<String> get selectedStatuses => _lastStatuses;

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
    Set<String>? statuses,
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
  Future<void> toggleStatusFilter(String status) async {
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

  /// The ticket list's current view mode — `board` until an explicit
  /// choice is made or restored via [loadPersistedViewMode]. Plain state,
  /// not part of [TicketsState]: switching view mode never changes which
  /// tickets are loaded, only which widget renders the already-loaded
  /// list, so it doesn't belong in the list-loading lifecycle states
  /// [TicketsState] models — same reasoning [selectedStatuses]/
  /// [currentSort] already follow. See
  /// `aion-arch/changes/list-board-view-and-column-visibility`.
  TicketListViewMode _viewMode = TicketListViewMode.board;

  /// The currently active view mode. Read by `TicketsListScreen`
  /// everywhere it needs to know whether List or Board mode is active.
  TicketListViewMode get currentViewMode => _viewMode;

  /// Sets [mode] as the current view mode, then persists it via
  /// [_viewModeRepository]/[_projectId] (no-op if either is `null`, same
  /// optional-dependency pattern as [setSort]). Does **not** call
  /// [searchTickets] — a view-mode change never affects which tickets
  /// match the current query, only which widget renders the
  /// already-loaded list — so this method never emits a [TicketsState].
  /// Callers must force their own rebuild after awaiting this (see
  /// `TicketsListScreen._handleViewModeChanged`), the same
  /// forced-rebuild precedent [setSort]'s callers already establish for
  /// state that lives outside [TicketsState].
  Future<void> setViewMode(TicketListViewMode mode) async {
    _viewMode = mode;
    final repo = _viewModeRepository;
    final projectId = _projectId;
    if (repo != null && projectId != null) {
      await repo.setViewMode(projectId, mode);
    }
  }

  /// Reads this project's persisted [TicketListViewMode] (via
  /// [_viewModeRepository]/[_projectId]) into [_viewMode], without
  /// emitting a state — same load-before-first-render precedent as
  /// [loadPersistedSort], called alongside it from
  /// `TicketsListScreen._initializeAndSearch`. No-ops if
  /// [_viewModeRepository] or [_projectId] is `null`, or if nothing was
  /// persisted yet (leaves [_viewMode] at its [TicketListViewMode.board]
  /// default).
  Future<void> loadPersistedViewMode() async {
    final repo = _viewModeRepository;
    final projectId = _projectId;
    if (repo == null || projectId == null) return;
    final mode = await repo.getViewMode(projectId);
    if (mode != null) _viewMode = mode;
  }

  /// The status names whose board column is currently hidden — empty
  /// means every column is visible. Plain state, not part of
  /// [TicketsState], for the same reason [_viewMode] isn't: hiding a
  /// column never changes which tickets are loaded, only which
  /// `BoardColumn`s `TicketBoardView` renders. See
  /// `aion-arch/changes/list-board-view-and-column-visibility`.
  Set<String> _hiddenColumns = const {};

  /// The board's currently hidden status columns. Read by
  /// `TicketBoardView` (which columns to skip) and `TicketColumnsPopover`
  /// (each row's checked state).
  Set<String> get hiddenBoardColumns => _hiddenColumns;

  /// Toggles [status]'s membership in [hiddenBoardColumns] — hides it if
  /// currently visible, shows it if currently hidden — then persists the
  /// updated [TicketBoardColumnVisibility] via
  /// [_boardColumnVisibilityRepository]/[_projectId] (no-op if either is
  /// `null`). Does **not** call [searchTickets], same reasoning as
  /// [setViewMode] — never emits a [TicketsState]; callers must force
  /// their own rebuild after awaiting this (see
  /// `TicketsListScreen._handleColumnVisibilityToggled`).
  Future<void> toggleBoardColumnVisibility(String status) async {
    _hiddenColumns = _toggleFilter(_hiddenColumns, status);
    final repo = _boardColumnVisibilityRepository;
    final projectId = _projectId;
    if (repo != null && projectId != null) {
      await repo.setHiddenColumns(
        projectId,
        TicketBoardColumnVisibility(hiddenStatuses: _hiddenColumns),
      );
    }
  }

  /// Reads this project's persisted [TicketBoardColumnVisibility] (via
  /// [_boardColumnVisibilityRepository]/[_projectId]) into
  /// [_hiddenColumns], without emitting a state — same
  /// load-before-first-render precedent as [loadPersistedViewMode],
  /// called alongside it from `TicketsListScreen._initializeAndSearch`.
  /// No-ops if [_boardColumnVisibilityRepository] or [_projectId] is
  /// `null`.
  Future<void> loadPersistedBoardColumnVisibility() async {
    final repo = _boardColumnVisibilityRepository;
    final projectId = _projectId;
    if (repo == null || projectId == null) return;
    final visibility = await repo.getHiddenColumns(projectId);
    _hiddenColumns = visibility.hiddenStatuses;
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
    Set<String> statuses = const {},
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
        statusSortOrder: _statusSortOrder,
      );
      if (generation != _searchGeneration) return;
      final blockedTicketIds = await _computeBlockedTicketIds(page.tickets);
      if (generation != _searchGeneration) return;
      await _seedExecutionTokenTotals(page.tickets.map((t) => t.id));
      if (generation != _searchGeneration) return;
      emit(
        TicketsLoaded(
          page.tickets,
          hasMore: page.hasMore,
          blockedTicketIds: blockedTicketIds,
          // Seeded from the cubit's own in-memory scheduling/stage-advance
          // state — _refreshInFlightBoardState only ever *updates* an
          // already-emitted TicketsLoaded (it no-ops otherwise), so this
          // fresh emission is the sole place that ever seeds these fields
          // for a just-opened/just-filtered Board. Without this, a Task
          // already running/queued at the moment the Board loads (e.g.
          // right after restoreExecutionQueue's auto/gated resume, or
          // simply navigating back to the Board mid-run) shows no
          // Running/Queued badge and no cancel affordance until some
          // unrelated mutation happens to call _refreshInFlightBoardState.
          // Fixed for `aion-arch/changes/parallel-work` post-/verify.
          inFlightExecutionIds: Set.unmodifiable(_inFlightExecutionIds),
          executionQueuePositions: {
            for (var i = 0; i < _executionQueue.length; i++)
              _executionQueue[i]: i + 1,
          },
          inFlightAdvanceIds: Set.unmodifiable(_inFlightStageAdvanceIds),
          pendingResumePrompt: _pendingResumeTickets ?? const [],
          // Same rationale as the fields above — this fresh emission is
          // the sole place that seeds a just-opened/just-filtered Board's
          // running totals; without it, a ticket with recorded execution
          // spend would show no token label until an unrelated mutation
          // happened to call _refreshInFlightBoardState.
          executionTokenTotals: Map.unmodifiable(_executionTokenTotals),
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
        statusSortOrder: _statusSortOrder,
      );
      if (generation != _searchGeneration) return;
      final combined = [...currentTickets, ...page.tickets];
      final blockedTicketIds = await _computeBlockedTicketIds(combined);
      if (generation != _searchGeneration) return;
      await _seedExecutionTokenTotals(page.tickets.map((t) => t.id));
      if (generation != _searchGeneration) return;
      emit(
        TicketsLoaded(
          combined,
          hasMore: page.hasMore,
          blockedTicketIds: blockedTicketIds,
          // Same fix as searchTickets — see its comment. Without this, a
          // load-more triggered while runs are already in flight/queued
          // would otherwise wipe their Board badges/cancel affordances.
          inFlightExecutionIds: Set.unmodifiable(_inFlightExecutionIds),
          executionQueuePositions: {
            for (var i = 0; i < _executionQueue.length; i++)
              _executionQueue[i]: i + 1,
          },
          inFlightAdvanceIds: Set.unmodifiable(_inFlightStageAdvanceIds),
          pendingResumePrompt: _pendingResumeTickets ?? const [],
          executionTokenTotals: Map.unmodifiable(_executionTokenTotals),
        ),
      );
    } catch (e) {
      if (generation != _searchGeneration) return;
      emit(TicketsLoadMoreFailed(currentTickets, hasMore: snapshot.hasMore));
    }
  }

  /// Creates a new ticket of [type] with [title], then reloads the list.
  ///
  /// [status] always starts at `_defaultCreationStatus`. [complexity]
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
  ///
  /// Also fires a fire-and-forget [_estimationSuggester] call, alongside a
  /// fire-and-forget [_tokenPredictor] call, alongside
  /// [_triggerEmbeddingRegen] — always, on every create, same condition as
  /// embedding regen — so a freshly created ticket's unset `complexity`/
  /// `estimate` get an AI first guess, and (for a `task`/`bug`) a
  /// token-cost prediction, without blocking this save. The
  /// [_estimationSuggester] call chains
  /// [_refreshDetailIfOpenAndAffected] onto its completion, so a
  /// suggestion that lands while the same ticket's detail screen is
  /// already open (e.g. the user navigated there right after creating it)
  /// live-refreshes instead of waiting for a manual reload. Added for
  /// `aion-arch/changes/live-refresh-open-ticket-detail-screen`.
  ///
  /// Independently of that chain, also fires
  /// [_refreshDetailIfOpenAndAffected] immediately after the write (not
  /// waiting on the suggester), so a parent Story's or Epic's
  /// already-open detail screen live-refreshes the moment [parentId]
  /// gains a new child — its `canAdvanceSddStage` precondition (e.g.
  /// "at least one child exists") can flip right away, independent of
  /// whether an AI suggestion ever lands for the new ticket. Added for
  /// `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`.
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
    // Captured before this call's own TicketCreating/TicketCreated
    // emissions below overwrite `state` — see
    // _refreshDetailIfOpenAndAffected's dartdoc for why a live `state`
    // read after those emissions would never see a detail screen (e.g.
    // the new ticket's parent) that was open when this call started.
    // Only the new immediate refresh call below needs this — the
    // existing _estimationSuggester-chained call further down correctly
    // keeps reading live `state`, since it resolves well after this
    // method's own emissions.
    final stateBeforeThisWrite = state;
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
        status: _defaultCreationStatus,
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
        unawaited(
          _estimationSuggester
              .suggest(persisted)
              .then((_) => _refreshDetailIfOpenAndAffected({persisted.id})),
        );
        unawaited(_tokenPredictor.suggest(persisted));
        unawaited(_triggerGitProjection(persisted, 'created'));
        unawaited(
          _refreshDetailIfOpenAndAffected(
            {persisted.id},
            fromState: stateBeforeThisWrite,
          ),
        );
      }
      final page = await _repository.searchTickets(
        query: _lastQuery,
        statuses: _lastStatuses,
        types: _lastTypes,
        priorities: _lastPriorities,
        sort: _lastSort,
        limit: max(_pageSize, currentTickets.length),
        statusSortOrder: _statusSortOrder,
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
  /// an `executionTrigger`-role status first runs
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
  /// ticket's blocker, and fires a fire-and-forget
  /// [_refreshDetailIfOpenAndAffected] call so a Story's already-open
  /// detail screen live-refreshes [TicketDetailLoaded.canAdvanceSddStage]
  /// when [id] is one of its direct Task/Bug children. Added for
  /// `aion-arch/changes/live-refresh-open-ticket-detail-screen`. On a
  /// successful write, also resolves [status] to its configured
  /// `WorkflowStatus.id` and looks up [_attachmentForStatus]; if one is
  /// found, fires it via [_resolveAndFireAttachment] — symmetric to, and
  /// independent of, the `executionTrigger`-role check above. Added for
  /// `aion-arch/changes/workflow-skill-attachments`.
  Future<void> updateTicketStatus(String id, String status) async {
    // Only fetch the ticket up front when the status holds the
    // executionTrigger role — every other transition returns true
    // immediately, so skip the extra round trip other status changes
    // (e.g. a plain board drag) don't need.
    if (_roleOf(status) == WorkflowStatusRole.executionTrigger) {
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

    // Captured before this call's own TicketStatusUpdating/TicketStatusUpdated
    // emissions below overwrite `state` — see _refreshDetailIfOpenAndAffected's
    // dartdoc for why a live `state` read after those emissions would never
    // see a detail screen that was open when this call started.
    final stateBeforeThisWrite = state;

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
      SkillAttachment? attachment;
      if (updated != null) {
        unawaited(_triggerGitProjection(updated, 'status-changed'));
        if (updated.type.isExecutable &&
            _roleOf(status) == WorkflowStatusRole.executionTrigger) {
          unawaited(_triggerOrQueueCodingExecution(updated));
        }
        final statusId = _resolveStatus(status)?.id;
        attachment = statusId != null ? _attachmentForStatus(statusId) : null;
      }
      final page = await _repository.searchTickets(
        query: _lastQuery,
        statuses: _lastStatuses,
        types: _lastTypes,
        priorities: _lastPriorities,
        sort: _lastSort,
        limit: max(_pageSize, currentTickets.length),
        statusSortOrder: _statusSortOrder,
      );
      emit(TicketStatusUpdated(page.tickets, hasMore: page.hasMore));
      unawaited(_refreshBlockedBoardState());
      // The attachment-firing call is chained *after*
      // _refreshDetailIfOpenAndAffected resolves, not run alongside it —
      // both are unawaited, but a `gated` attachment's own
      // TicketDetailLoaded(pendingSkillAttachment: ...) emission must be
      // the truly final one for this write, not clobbered by
      // _refreshDetailIfOpenAndAffected's own (pending-attachment-less)
      // re-emission landing afterward. Added for
      // `aion-arch/changes/workflow-skill-attachments`.
      unawaited(
        _refreshDetailIfOpenAndAffected(
          {id},
          fromState: stateBeforeThisWrite,
        ).then((_) {
          if (updated != null && attachment != null) {
            return _resolveAndFireAttachment(updated, attachment);
          }
        }),
      );
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
  ///
  /// Also fires a fire-and-forget [_estimationSuggester] call, alongside a
  /// fire-and-forget [_tokenPredictor] call, alongside
  /// [_triggerEmbeddingRegen], under the same title/description-changed
  /// condition, so a content edit gets a fresh AI complexity/estimate
  /// suggestion for whichever field isn't `manual`-locked, and (for a
  /// `task`/`bug` not yet executing) a fresh token-cost prediction. The
  /// [_estimationSuggester] call chains [_refreshDetailIfOpenAndAffected]
  /// onto its completion, so a passive suggestion that lands while
  /// [refreshed]'s own detail screen is still open live-refreshes instead
  /// of waiting for a manual reload. Added for
  /// `aion-arch/changes/live-refresh-open-ticket-detail-screen`.
  ///
  /// [complexityEdited]/[estimateEdited] tell [TicketRepository.updateTicket]
  /// whether *this specific call* is the Complexity picker's `onSelected`
  /// or the Estimate field's `onCommit` (`true`) versus some other field's
  /// edit that merely carries `ticket.complexity`/`ticket.estimate`
  /// through unchanged (`false`, the default) — see that method's dartdoc
  /// for why the distinction matters. Forwarded to the repository only
  /// when at least one is `true`, so the overwhelmingly common "editing
  /// some other field" call keeps the exact same
  /// `_repository.updateTicket(ticket)` shape it always has.
  Future<Ticket> updateTicket(
    Ticket ticket, {
    bool complexityEdited = false,
    bool estimateEdited = false,
  }) async {
    try {
      final previous = await _repository.getTicketById(ticket.id);
      if (complexityEdited || estimateEdited) {
        await _repository.updateTicket(
          ticket,
          complexityEdited: complexityEdited,
          estimateEdited: estimateEdited,
        );
      } else {
        await _repository.updateTicket(ticket);
      }
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
          unawaited(
            _estimationSuggester
                .suggest(refreshed)
                .then((_) => _refreshDetailIfOpenAndAffected({refreshed.id})),
          );
          unawaited(_tokenPredictor.suggest(refreshed));
        }
        if (previous != null &&
            (previous.estimate != refreshed.estimate ||
                previous.timeSpent != refreshed.timeSpent)) {
          unawaited(_recomputeRollupChain({refreshed.id}, 'rollup updated'));
        }
        final indexer = _wikilinkIndexer;
        if (indexer != null &&
            previous != null &&
            refreshed.type == TicketType.page &&
            (previous.title != refreshed.title ||
                previous.description != refreshed.description)) {
          unawaited(_reindexAndCascadeWikilinks(indexer, previous, refreshed));
        }
      }
      return refreshed ?? ticket;
    } catch (e) {
      emit(TicketsError(e.toString()));
      rethrow;
    }
  }

  /// Explicitly re-suggests [ticket]'s complexity via
  /// [TicketEstimationSuggester.regenerate], bypassing the lock even if
  /// `ticket.complexitySource == TicketEstimationSource.manual`. Awaited —
  /// unlike the passive background trigger in [createTicket]/[updateTicket],
  /// this is a direct response to the detail screen's Regenerate button, so
  /// it re-fetches and emits [TicketDetailLoaded] with the refreshed value
  /// once the suggestion lands, rather than leaving the UI to catch up on
  /// next reopen. No-ops (does nothing, emits nothing) if
  /// `ticket.complexity == null` — nothing to regenerate against an unset
  /// field; the picker's own "+ COMPLEXITY" flow is how a first value gets
  /// set. Emits [TicketsError] only if the repository re-fetch itself
  /// throws — a failed/empty model suggestion (see
  /// [TicketEstimationSuggester]'s swallow-on-failure behavior) silently
  /// leaves the ticket's current value in place and still re-emits
  /// [TicketDetailLoaded] unchanged, rather than erroring the whole screen
  /// over a background-nicety failure.
  Future<void> regenerateComplexitySuggestion(Ticket ticket) async {
    if (ticket.complexity == null) return;
    try {
      await _estimationSuggester.regenerate(ticket, forceComplexity: true);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) emit(TicketDetailLoaded(refreshed));
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Same as [regenerateComplexitySuggestion], for `estimate`.
  Future<void> regenerateEstimateSuggestion(Ticket ticket) async {
    if (ticket.estimate == null) return;
    try {
      await _estimationSuggester.regenerate(ticket, forceEstimate: true);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) emit(TicketDetailLoaded(refreshed));
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Changes [ticket]'s status from the ticket-detail screen. Persists via
  /// the same [TicketRepository.updateTicketStatus] the board's drag/
  /// `MoveToStatusMenu` path calls, then re-fetches and emits
  /// [TicketDetailLoaded] with the refreshed ticket — unlike
  /// [updateTicketStatus], which emits list-shaped optimistic states built
  /// for the board and would fall through `TicketDetailScreen`'s state
  /// switch. Emits [TicketsError] on failure. Moving [ticket] to
  /// an `executionTrigger`-role status first runs
  /// [_interceptBlockedDependencyTrigger] — every ticket type is
  /// rejected if it has an unresolved `blocks`/`blockedBy` dependency —
  /// then, if [ticket] is a Task or Bug (see
  /// `TicketTypeHierarchy.isExecutable`), [_interceptTaskExecutionTrigger].
  /// A rejection from either skips the write entirely; an allowed
  /// transition proceeds as normal, then [_triggerOrQueueCodingExecution]
  /// starts (or queues) the coding-execution run once the write succeeds.
  Future<void> changeTicketStatus(Ticket ticket, String status) async {
    if (!(await _interceptBlockedDependencyTrigger(ticket, status))) return;
    if (!(await _interceptTaskExecutionTrigger(ticket, status))) return;
    try {
      await _repository.updateTicketStatus(ticket.id, status);
      final refreshed = await _repository.getTicketById(ticket.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
        unawaited(_triggerGitProjection(refreshed, 'status-changed'));
        if (refreshed.type.isExecutable &&
            _roleOf(status) == WorkflowStatusRole.executionTrigger) {
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
  /// Validation (self-parenting, cycles, always-root types, an
  /// Inbox-spawned chat, and structural type-compatibility) and the
  /// actual write/rollup-recompute now live in
  /// [TicketParentTrashService.changeParent] — shared with
  /// `TicketMarkdownReconciler`/`TicketRepairService`, see
  /// [_parentTrashService] — so this method only translates the result
  /// into UI state: [ParentChangeRejected] emits [TicketsError] with
  /// [TicketsErrorReason.invalidParent] followed immediately by a
  /// re-emitted [TicketDetailLoaded] (via [_emitInvalidParent], same
  /// pattern as [deleteTicket]'s `hasChildren` handling), so the detail
  /// screen shows a toast rather than collapsing to the generic error
  /// view; [ParentChangeSuccess] emits the refreshed [TicketDetailLoaded]
  /// directly.
  ///
  /// On success, also fires a fire-and-forget
  /// [_refreshDetailIfOpenAndAffected] call for [ticket]'s id — covers
  /// the *new*-parent direction: if a Story's or Epic's already-open
  /// detail screen is the ticket's new parent, that screen
  /// live-refreshes. The *old*-parent direction (a Story's or Epic's
  /// already-open detail screen loses a child) needs a second, separate
  /// check: [_refreshDetailIfOpenAndAffected] infers a written ticket's
  /// parent by re-fetching its *current* `parentId`, which after this
  /// write is always the *new* parent — the old parent is structurally
  /// undiscoverable that way, since nothing about the post-write ticket
  /// still points at it. [ticket]'s `parentId` *before* this call is the
  /// only place that information exists, so it's captured
  /// (`oldParentId`) and checked directly against
  /// [_liveRefreshDependents] and the state open when this call started.
  /// Added for
  /// `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`.
  Future<void> updateTicketParent(Ticket ticket, String? newParentId) async {
    // Captured before this call's own emissions below overwrite `state`
    // — see _refreshDetailIfOpenAndAffected's dartdoc for why a live
    // `state` read after those emissions would never see a detail
    // screen that was open when this call started.
    final stateBeforeThisWrite = state;
    final oldParentId = ticket.parentId;
    try {
      final result = await _parentTrashService.changeParent(
        ticket,
        newParentId,
      );
      switch (result) {
        case ParentChangeRejected():
          await _emitInvalidParent(ticket.id);
        case ParentChangeSuccess(:final ticket):
          emit(TicketDetailLoaded(ticket));
          unawaited(
            _refreshDetailIfOpenAndAffected({
              ticket.id,
            }, fromState: stateBeforeThisWrite),
          );
          if (oldParentId != null &&
              oldParentId != ticket.parentId &&
              stateBeforeThisWrite is TicketDetailLoaded &&
              stateBeforeThisWrite.ticket.id == oldParentId) {
            final childTypes =
                _liveRefreshDependents[stateBeforeThisWrite.ticket.type];
            if (childTypes != null && childTypes.contains(ticket.type)) {
              unawaited(getTicketById(oldParentId));
            }
          }
      }
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
  ///   reached a terminal state (a `done`-role status for a Task,
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
  /// [_runStageChatTurn] finishes. When [nextStage] has a configured
  /// [_attachmentForStage], the spawned chat's opening comment is
  /// [_promptFor]'s output instead of [_assembleStageContext]'s (see
  /// [_createStageChat]), and whether/when [_runStageChatTurn] actually
  /// runs on it is gated by the attachment's own confidence via
  /// [_resolveAndFireAttachment] rather than firing unconditionally —
  /// `auto` behaves identically to the no-attachment path;
  /// `gated`/`manual` create the chat but leave [isAdvancingStage] `false`
  /// again immediately, surfacing a pending-confirmation banner or a
  /// manual "Run" control instead. Added for
  /// `aion-arch/changes/workflow-skill-attachments`.
  ///
  /// Also fires a fire-and-forget [_refreshDetailIfOpenAndAffected] call
  /// right after the write is confirmed, so a parent Epic's already-open
  /// detail screen live-refreshes when [ticket] is one of its direct
  /// Story children and this call just advanced that Story's `sddStage`.
  /// Added for
  /// `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`.
  Future<String?> advanceSddStage(Ticket ticket) async {
    // Captured before this call's own emissions below (including the
    // guard-clause emits from _emitSddStagePreconditionNotMet) overwrite
    // `state` — see _refreshDetailIfOpenAndAffected's dartdoc for why a
    // live `state` read after those emissions would never see a detail
    // screen that was open when this call started.
    final stateBeforeThisWrite = state;
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
      // Fired once, right after the persisted sddStage write is
      // confirmed, rather than duplicated in every branch below — a
      // parent Epic's precondition only cares that a child Story's
      // sddStage has changed, not which branch this call subsequently
      // takes. Added for
      // `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`.
      unawaited(
        _refreshDetailIfOpenAndAffected(
          {ticket.id},
          fromState: stateBeforeThisWrite,
        ),
      );
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

      final attachment = _attachmentForStage(nextStage);
      if (attachment == null) {
        // No attachment configured for nextStage — identical to before
        // this change: unconditional, no confidence check.
        _inFlightStageAdvanceIds.add(chatId);
        unawaited(_runStageChatTurn(refreshed, nextStage, chatId));
      } else if (attachment.confidence == AutomationConfidence.auto) {
        _inFlightStageAdvanceIds.add(chatId);
        unawaited(
          _resolveAndFireAttachment(
            refreshed,
            attachment,
            fire: () => _runStageChatTurn(refreshed, nextStage, chatId),
          ),
        );
      } else {
        // gated/manual: the chat was already created above with
        // _promptFor's prompt as its opening comment, but the turn
        // itself doesn't run yet — clear the momentary "advancing"
        // spinner (isAdvancingStage) rather than leave it stuck true.
        _inFlightStageAdvanceIds.remove(ticket.id);
        _refreshInFlightBoardState();
        final currentDetail = state;
        if (currentDetail is TicketDetailLoaded &&
            currentDetail.ticket.id == refreshed.id) {
          // copyWith, not a bare TicketDetailLoaded(refreshed) — see
          // TicketDetailLoaded.copyWith's dartdoc.
          emit(currentDetail.copyWith(isAdvancingStage: false));
        } else {
          emit(TicketDetailLoaded(refreshed));
        }
        await _resolveAndFireAttachment(
          refreshed,
          attachment,
          fire: () => _runStageChatTurn(refreshed, nextStage, chatId),
        );
      }
      return chatId;
    } catch (e) {
      _inFlightStageAdvanceIds.remove(ticket.id);
      emit(TicketsError(e.toString()));
      return null;
    }
  }

  /// Restores `TicketDetailLoaded` for the ticket with id [ticketId] after
  /// a guard-clause [TicketsError] — so a rejected `promoteIdea`/
  /// `reclassifyIdea` call doesn't leave the Cubit stuck on a bare error
  /// state indefinitely (the whole ticket-detail panel is one
  /// `BlocBuilder` switching on [TicketsState], so a lingering
  /// [TicketsError] blanks out the entire screen, not just the action
  /// that failed). No-ops if [ticketId] no longer resolves to a ticket —
  /// nothing to restore to. Added for
  /// `aion-arch/changes/idea-gap-question-ticket-types`'s `/verify` fix-up.
  Future<void> _emitTicketDetailIfFound(String ticketId) async {
    final ticket = await _repository.getTicketById(ticketId);
    if (ticket != null) {
      emit(TicketDetailLoaded(ticket));
    }
  }

  /// Same recovery as [_emitTicketDetailIfFound], for a guard clause on a
  /// Documentation-mode ticket (`createGapOrQuestion`'s [targetTicketId])
  /// whose detail screen also depends on [loadDocumentRelations] for its
  /// Linked Tickets/Backlinks/Gaps & Open Questions sections — restores
  /// those too, not just the bare ticket. Added for
  /// `aion-arch/changes/idea-gap-question-ticket-types`'s `/verify` fix-up.
  Future<void> _restoreDocumentTicketDetail(String ticketId) async {
    final ticket = await _repository.getTicketById(ticketId);
    if (ticket == null) return;
    emit(TicketDetailLoaded(ticket));
    await loadDocumentRelations(ticketId);
  }

  /// Promotes [idea] into an epic or a bug (per [targetType]): if
  /// [existingTicketId] is given, links [idea] to that ticket via
  /// [TicketLinkRepository.createLink] (as [TicketLinkType.relatesTo]);
  /// otherwise creates a new [targetType] ticket copying
  /// `idea.title`/`description`, then links the two the same way. Does
  /// not delete or change [idea]'s own type or status — promotion is a
  /// link, not a conversion, consistent with `release`'s existing
  /// cross-cutting-link precedent. Emits [TicketsError] (raw message, no
  /// classified reason — these guards are defensive, since the UI only
  /// ever calls this for an `idea` ticket with [targetType] set to
  /// [TicketType.epic] or [TicketType.bug]) if `idea.type` isn't
  /// [TicketType.idea], or if [targetType] is neither
  /// [TicketType.epic] nor [TicketType.bug] — either guard then calls
  /// [_emitTicketDetailIfFound] to recover the screen. No-ops (does not
  /// touch the repository) if constructed without a
  /// [TicketLinkRepository] (see the constructor's dartdoc). Renamed from
  /// `promoteSignal` for `aion-arch/changes/idea-gap-question-ticket-types`
  /// — behavior is otherwise unchanged.
  Future<void> promoteIdea(
    Ticket idea, {
    required TicketType targetType,
    String? existingTicketId,
  }) async {
    if (idea.type != TicketType.idea) {
      emit(TicketsError('Only idea tickets can be promoted.'));
      await _emitTicketDetailIfFound(idea.id);
      return;
    }
    if (targetType != TicketType.epic && targetType != TicketType.bug) {
      emit(TicketsError('Ideas can only be promoted to an epic or a bug.'));
      await _emitTicketDetailIfFound(idea.id);
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
          title: idea.title,
          description: idea.description,
          status: _defaultCreationStatus,
          createdAt: now,
          updatedAt: now,
        );
        await _repository.createTicket(target);
        targetId = target.id;
      }
      await linkRepo.createLink(
        sourceTicketId: idea.id,
        targetTicketId: targetId,
        linkType: TicketLinkType.relatesTo,
      );
      final refreshed = await _repository.getTicketById(idea.id);
      if (refreshed != null) {
        emit(TicketDetailLoaded(refreshed));
      }
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Creates a [type] (`knownGap`/`openQuestion` only) ticket titled
  /// [title] with optional [description], linked
  /// ([TicketLinkType.relatesTo]) to [targetTicketId] in the same
  /// operation. Returns `true` on success, `false` if rejected or if the
  /// creation/link write throws — [RaiseGapOrQuestionPicker] awaits this
  /// to decide whether to close its overlay or show its inline error
  /// state instead of assuming success. Emits [TicketsError] and refuses
  /// to create anything if [type] isn't `knownGap`/`openQuestion`, or if
  /// [targetTicketId] doesn't resolve to an existing ticket — the hard
  /// rule that a known-gap/open-question can never exist without its
  /// target lives here, not as a UI-layer convention. Every failure path
  /// calls [_restoreDocumentTicketDetail] so [targetTicketId]'s detail
  /// screen (and its Gaps & Open Questions section) recovers instead of
  /// staying stuck on a bare [TicketsError]. Returns `false` without
  /// emitting if constructed without a [TicketLinkRepository]. Added for
  /// `aion-arch/changes/idea-gap-question-ticket-types`; see that
  /// change's design.md §3.2.
  Future<bool> createGapOrQuestion(
    TicketType type, {
    required String title,
    String? description,
    required String targetTicketId,
  }) async {
    if (type != TicketType.knownGap && type != TicketType.openQuestion) {
      emit(
        TicketsError(
          'Only known gaps or open questions can be raised this way.',
        ),
      );
      await _restoreDocumentTicketDetail(targetTicketId);
      return false;
    }
    final linkRepo = _linkRepository;
    if (linkRepo == null) return false;
    final target = await _repository.getTicketById(targetTicketId);
    if (target == null) {
      emit(TicketsError('The target ticket no longer exists.'));
      await _restoreDocumentTicketDetail(targetTicketId);
      return false;
    }
    try {
      final now = DateTime.now();
      final raised = Ticket(
        id: _uuid.v4(),
        ticketId: '',
        type: type,
        title: title,
        description: description,
        status: _defaultCreationStatus,
        createdAt: now,
        updatedAt: now,
      );
      await _repository.createTicket(raised);
      await linkRepo.createLink(
        sourceTicketId: raised.id,
        targetTicketId: targetTicketId,
        linkType: TicketLinkType.relatesTo,
      );
      await loadDocumentRelations(targetTicketId);
      return true;
    } catch (e) {
      emit(TicketsError(e.toString()));
      await _restoreDocumentTicketDetail(targetTicketId);
      return false;
    }
  }

  /// Converts an existing `idea` ticket into a `knownGap`/`openQuestion`
  /// (per [targetType]), linking it to [targetTicketId] in the same
  /// operation — the manual-reclassification path for a misclassified
  /// idea, or for a pre-`idea-gap-question-ticket-types` `signal` ticket
  /// migrated to `idea` by the schema-11 default (see
  /// `AppDatabase`'s migration). Same target-existence/type validation as
  /// [createGapOrQuestion]; additionally refuses if [idea]'s type isn't
  /// [TicketType.idea]. Every failure path calls
  /// [_emitTicketDetailIfFound] to recover [idea]'s own detail screen
  /// instead of leaving the Cubit stuck on a bare [TicketsError]. Mutates
  /// the ticket's stored `type` via [TicketRepository.updateTicket] —
  /// never deletes/recreates it, so its id, ticketId, createdAt, and any
  /// comments/chat children survive the reclassification. Added for
  /// `aion-arch/changes/idea-gap-question-ticket-types`; see that
  /// change's design.md §3.3.
  Future<void> reclassifyIdea(
    Ticket idea, {
    required TicketType targetType,
    required String targetTicketId,
  }) async {
    if (idea.type != TicketType.idea) {
      emit(TicketsError('Only idea tickets can be reclassified.'));
      await _emitTicketDetailIfFound(idea.id);
      return;
    }
    if (targetType != TicketType.knownGap &&
        targetType != TicketType.openQuestion) {
      emit(
        TicketsError(
          'Ideas can only be reclassified to a known gap or an open '
          'question.',
        ),
      );
      await _emitTicketDetailIfFound(idea.id);
      return;
    }
    final linkRepo = _linkRepository;
    if (linkRepo == null) return;
    final target = await _repository.getTicketById(targetTicketId);
    if (target == null) {
      emit(TicketsError('The target ticket no longer exists.'));
      await _emitTicketDetailIfFound(idea.id);
      return;
    }
    try {
      await _repository.updateTicket(idea.copyWith(type: targetType));
      await linkRepo.createLink(
        sourceTicketId: idea.id,
        targetTicketId: targetTicketId,
        linkType: TicketLinkType.relatesTo,
      );
      final refreshed = await _repository.getTicketById(idea.id);
      if (refreshed != null) emit(TicketDetailLoaded(refreshed));
    } catch (e) {
      emit(TicketsError(e.toString()));
      await _emitTicketDetailIfFound(idea.id);
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
      tools: await _toolsFor(designSyncChat.id),
      onToolCall: _onToolCallFor(designSyncChat),
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
        return await _storyNeedsDesignReview(tasks)
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
  ///
  /// Short-circuits to `false` before that heuristic runs at all when
  /// [_designStagesEnabled] resolves `false` — a project that's turned
  /// off design-review stages project-wide never routes a Story through
  /// `designBrief`/`designSync`, regardless of what its Tasks look like.
  /// When design stages are enabled (the default), this per-Story
  /// heuristic is completely unchanged. Added for
  /// `aion-arch/changes/configurable-ticket-workflow`.
  Future<bool> _storyNeedsDesignReview(List<Ticket> tasks) async {
    if (!(await _designStagesEnabled())) return false;
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
            await _storyNeedsDesignReview(children);
        final ready =
            children.isNotEmpty &&
            (needsDesign ||
                children.every(
                  (c) => nextRank == TicketType.task
                      ? _roleOf(c.status) == WorkflowStatusRole.done
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
            tasks.every((t) => _roleOf(t.status) == WorkflowStatusRole.done);
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
    if (!(await _storyNeedsDesignReview(siblingTasks))) {
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
  /// moving to an `executionTrigger`-role status while [_codingExecutionGateCheck]
  /// disallows it. Every other type/status combination always returns
  /// `true` (not a trigger — proceed as normal). On rejection, emits
  /// [TicketsErrorReason.codingExecutionBlocked] then a re-emitted
  /// unchanged [TicketDetailLoaded], mirroring
  /// [_emitInvalidParent]/[_emitSddStagePreconditionNotMet], and returns
  /// `false` so the caller skips the write entirely.
  Future<bool> _interceptTaskExecutionTrigger(
    Ticket task,
    String status,
  ) async {
    if (!task.type.isExecutable ||
        _roleOf(status) != WorkflowStatusRole.executionTrigger) {
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
    // Captured immediately before the caller's own inProgress status
    // write, so cancelCodingExecution knows which status to revert to.
    // Added for `aion-arch/changes/parallel-work`.
    _preExecutionStatus[task.id] = task.status;
    return true;
  }

  /// Gate on a ticket's move to an `executionTrigger`-role status: rejects the
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
    String status,
  ) async {
    if (_roleOf(status) != WorkflowStatusRole.executionTrigger) return true;
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

  /// Enqueues [task]'s coding-execution run, then immediately tries to
  /// start it (and any other now-eligible queued run) via
  /// [_tryStartNextQueuedExecutions] — under
  /// [ExecutionSchedulingMode.strictFifo] (today's unchanged default),
  /// this only ever actually starts [task] when nothing else is running,
  /// exactly as the old single-slot behavior did. Called by
  /// [changeTicketStatus]/[updateTicketStatus] after a Task's status
  /// write to an `executionTrigger`-role status succeeds.
  Future<void> _triggerOrQueueCodingExecution(Ticket task) async {
    _executionQueue.add(task.id);
    _refreshInFlightBoardState();
    _refreshTaskDetailIfShowing();
    unawaited(_persistExecutionQueueSnapshot());
    unawaited(_tryStartNextQueuedExecutions());
  }

  /// Re-emits the current list-shaped state (`TicketsLoaded` only — a
  /// no-op while a detail screen or a mutation-in-flight state is
  /// active, since there's no Board to refresh in that case) with
  /// [TicketsLoaded.inFlightExecutionIds]/
  /// [TicketsLoaded.executionQueuePositions]/
  /// [TicketsLoaded.inFlightAdvanceIds]/[TicketsLoaded.pendingResumePrompt]
  /// recomputed from [_inFlightExecutionIds]/[_executionQueue]/
  /// [_inFlightStageAdvanceIds]/[_pendingResumeTickets]. Called at every
  /// mutation site of those: [_triggerOrQueueCodingExecution],
  /// [_tryStartNextQueuedExecutions], [cancelCodingExecution],
  /// [_runCodingExecution]'s completion and catch-path clears, every
  /// [_inFlightStageAdvanceIds] mutation in [advanceSddStage]/
  /// [_runStageChatTurn], and [resumePendingExecutions]/
  /// [dismissPendingResumePrompt] — so `TicketBoardCard` never needs to
  /// poll. Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  /// Also re-mirrors [TicketsLoaded.executionTokenTotals] from
  /// [_executionTokenTotals]'s current contents — a mirror, not a
  /// mutation; this method never writes to that cache itself. Added for
  /// `aion-arch/changes/token-cost-prediction`.
  void _refreshInFlightBoardState() {
    final current = state;
    if (current is! TicketsLoaded) return;
    emit(
      TicketsLoaded(
        current.tickets,
        hasMore: current.hasMore,
        inFlightExecutionIds: Set.unmodifiable(_inFlightExecutionIds),
        executionQueuePositions: {
          for (var i = 0; i < _executionQueue.length; i++)
            _executionQueue[i]: i + 1,
        },
        inFlightAdvanceIds: Set.unmodifiable(_inFlightStageAdvanceIds),
        blockedTicketIds: current.blockedTicketIds,
        pendingResumePrompt: _pendingResumeTickets ?? const [],
        executionTokenTotals: Map.unmodifiable(_executionTokenTotals),
      ),
    );
  }

  /// Re-emits [TicketDetailLoaded] with `isExecuting`/
  /// `executionQueuePosition` recomputed from [_inFlightExecutionIds]/
  /// [_executionQueue] — but only when the cubit's current `state` is
  /// still [TicketDetailLoaded], and only if either value actually
  /// changed (avoids an unnecessary rebuild on every unrelated
  /// scheduling mutation). Every other field is copied unchanged from
  /// the current state. Needed because [_refreshInFlightBoardState]
  /// only refreshes a list-shaped `TicketsLoaded` state and is a no-op
  /// while a detail screen is showing — without this, a Task's own
  /// already-open detail screen (its cancel button, its "Queued #N"
  /// hint) never reflects a scheduling change that happens while it's
  /// open — e.g. triggering it from that very screen, or a sibling's
  /// scheduling decision shifting its queue position — until the user
  /// navigates away and back. Called from the same coding-execution
  /// scheduling mutation sites as [_refreshInFlightBoardState]
  /// (SDD-stage-advance's own [_inFlightStageAdvanceIds] mutations don't
  /// call this — [TicketDetailLoaded] has no equivalent field for those).
  /// Fixed for `aion-arch/changes/parallel-work` post-/verify.
  void _refreshTaskDetailIfShowing() {
    final current = state;
    if (current is! TicketDetailLoaded) return;
    final taskId = current.ticket.id;
    final isExecuting = _inFlightExecutionIds.contains(taskId);
    final queueIndex = _executionQueue.indexOf(taskId);
    final executionQueuePosition = queueIndex >= 0 ? queueIndex + 1 : null;
    if (isExecuting == current.isExecuting &&
        executionQueuePosition == current.executionQueuePosition) {
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
        isExecuting: isExecuting,
        executionQueuePosition: executionQueuePosition,
        executionAwaitingReview: current.executionAwaitingReview,
        executionFailureReason: current.executionFailureReason,
        executionCanRetry: current.executionCanRetry,
        executionLiveActivity: current.executionLiveActivity,
      ),
    );
  }

  /// Computes the current set of blocked work-ticket ids: a ticket whose
  /// blocking counterpart (the other side of a `blocks`/`blockedBy` row)
  /// exists, is live, and is not a `done`-role status. Queries
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
      final blockerStatus = byId[blockerId]?.status;
      if (blockerStatus == null || _roleOf(blockerStatus) != WorkflowStatusRole.done) {
        blocked.add(blockeeId);
      }
    }
    return blocked;
  }

  /// Batch-seeds [_executionTokenTotals] for every id in [ids] not
  /// already cached — one [TicketRepository.getExecutionTokenTotals]
  /// call for the whole not-yet-cached subset, never one query per id.
  /// Merges results with a compare-and-keep-max against any existing
  /// in-memory value, so a batch read that resolves after a concurrent
  /// [_runCodingExecution] increment can never clobber it with a staler
  /// total. Called by [searchTickets]/[loadMoreTickets]/[getTicketById]
  /// for whichever ids they just loaded. Added for
  /// `aion-arch/changes/token-cost-prediction`.
  Future<void> _seedExecutionTokenTotals(Iterable<String> ids) async {
    final uncached = [
      for (final id in ids)
        if (!_executionTokenTotals.containsKey(id)) id,
    ];
    if (uncached.isEmpty) return;
    final totals = await _repository.getExecutionTokenTotals(uncached);
    for (final entry in totals.entries) {
      final existing = _executionTokenTotals[entry.key];
      if (existing == null || entry.value > existing) {
        _executionTokenTotals[entry.key] = entry.value;
      }
    }
  }

  /// Whether [ticket] currently has an unresolved `blocks`/`blockedBy`
  /// dependency — i.e. a live link whose [relativeLinkType] from
  /// [ticket]'s own side is [TicketLinkType.blockedBy], and whose other
  /// side either doesn't exist or isn't a `done`-role status. Mirrors
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
      if (blocker == null || _roleOf(blocker.status) != WorkflowStatusRole.done) {
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
        pendingResumePrompt: current.pendingResumePrompt,
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
      status: _defaultCreationStatus,
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
    // ChatTurnCancelled is unreachable here — this call passes no `runId`,
    // so there is no way to cancel it — but is still treated the same as
    // a failure defensively, preserving today's exact bool-equivalent
    // behavior.
    if (summarized is! ChatTurnSuccess) return (oldChat, null);

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
  /// [_inFlightExecutionIds]. The worktree (never the branch) is
  /// always removed in a `finally`, success or failure — itself wrapped
  /// in its own try/catch, since a worktree that was never actually
  /// created has nothing to remove.
  ///
  /// If a PR was confirmed (see [_executionSucceededWithPr]) and
  /// [_automationSettingsRepository] is configured, flips [task] straight
  /// to a `reviewReady`-role status when [AutomationContext.codingExecution]'s
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
  /// Then tries to start the next queued run(s) (see
  /// [_tryStartNextQueuedExecutions]), no-opping gracefully if constructed
  /// without a [ProviderRegistry]/[CommentRepository]/[GitRepositoryClient]/
  /// [GitHubCliClient]/[BaselineRepository]/`projectId`/`baselineVersion`/
  /// `projectRootPath` (see the constructor's dartdoc).
  ///
  /// Every implement/verify turn below gets a fresh `runId`, tracked in
  /// [_inFlightRuns] for the run's duration — [cancelCodingExecution]
  /// resolves it from there. On a `ChatTurnCancelled` result from either
  /// turn (see [ChatCubit.runChatTurn]), persists the accumulated text (if
  /// any) as one [CommentAuthorType.ai] comment, posts an `"Execution
  /// cancelled."` [CommentAuthorType.system] comment, reverts [task]'s
  /// status to whatever [_preExecutionStatus] captured before the trigger,
  /// and stops the loop entirely — no verify turn, no PR. The worktree is
  /// still always removed in the `finally` block below (the branch/commits
  /// already pushed to it are not) — cancellation doesn't change that.
  /// Added for `aion-arch/changes/parallel-work`; see that change's
  /// design.md §5.4/§5.5.
  ///
  /// Also updates [_executionTokenTotals] (via [_addExecutionTokens])
  /// right after each implement/verify turn's `ai` comment is persisted —
  /// see `TicketsLoaded.executionTokenTotals`'s dartdoc for how that
  /// running total then surfaces. Added for
  /// `aion-arch/changes/token-cost-prediction`.
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
      _inFlightExecutionIds.remove(task.id);
      _inFlightRuns.remove(task.id);
      _refreshInFlightBoardState();
      _refreshTaskDetailIfShowing();
      unawaited(_persistExecutionQueueSnapshot());
      unawaited(_tryStartNextQueuedExecutions());
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
      _inFlightExecutionIds.remove(task.id);
      _inFlightRuns.remove(task.id);
      _refreshInFlightBoardState();
      _refreshTaskDetailIfShowing();
      unawaited(_persistExecutionQueueSnapshot());
      unawaited(_tryStartNextQueuedExecutions());
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

      // Stable across every retry below — [chat]'s own parent never
      // changes mid-run, so the offered tool/handler doesn't either.
      final (executionTools, executionOnToolCall) = await _toolCallParamsFor(
        chat.id,
      );

      var attempt = 0;
      var verified = false;
      while (true) {
        final (implementModel, implementProvider) =
            await _resolveModelAndProvider(ModelPhase.execution);
        final implementRunId = _uuid.v4();
        _inFlightRuns[task.id] = InFlightExecutionRun(
          implementRunId,
          implementProvider,
        );
        final implementResult = await ChatCubit.runChatTurn(
          client: implementProvider.client,
          provider: implementProvider,
          commentRepo: commentRepo,
          chatTicketId: chat.id,
          prompt: prompt,
          model: implementModel,
          runId: implementRunId,
          toolsEnabled: true,
          workingDirectory: worktreePath,
          onChunk: onChunk,
          onToolUse: onToolUse,
          onConsumptionSignal: onConsumptionSignal,
          tools: executionTools,
          onToolCall: executionOnToolCall,
        );
        if (implementResult is ChatTurnCancelled) {
          await _handleExecutionCancelled(task, chat, implementResult);
          break;
        }
        if (implementResult is! ChatTurnSuccess) {
          // A hard error (API failure, thrown exception) — `runChatTurn`
          // already persisted an "Execution failed: ..." comment itself.
          // Don't run a verify turn against a worktree whose
          // implementation turn never actually completed.
          break;
        }
        await _addExecutionTokens(task.id, chat.id);

        final verifyPrompt = await _assembleVerificationContext(task);
        final (verifyModel, verifyProvider) = await _resolveModelAndProvider(
          ModelPhase.execution,
        );
        final verifyRunId = _uuid.v4();
        _inFlightRuns[task.id] = InFlightExecutionRun(
          verifyRunId,
          verifyProvider,
        );
        final verifyResult = await ChatCubit.runChatTurn(
          client: verifyProvider.client,
          provider: verifyProvider,
          commentRepo: commentRepo,
          chatTicketId: chat.id,
          prompt: verifyPrompt,
          model: verifyModel,
          runId: verifyRunId,
          toolsEnabled: true,
          workingDirectory: worktreePath,
          onChunk: onChunk,
          onToolUse: onToolUse,
          onConsumptionSignal: onConsumptionSignal,
          tools: executionTools,
          onToolCall: executionOnToolCall,
        );
        if (verifyResult is ChatTurnCancelled) {
          await _handleExecutionCancelled(task, chat, verifyResult);
          break;
        }
        if (verifyResult is! ChatTurnSuccess) {
          // A hard error during the verify turn itself — same shape as
          // above; `runChatTurn` already posted the failure comment.
          break;
        }
        await _addExecutionTokens(task.id, chat.id);

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
      // _inFlightExecutionIds — and permanently wedging the
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
        await _repository.updateTicketStatus(task.id, _reviewReadyStatus);
      }
      // `gated`/`manual`: leave status as-is; getTicketById's re-check
      // surfaces the "ready for review" banner or leaves it to a manual
      // status change.
    }

    // Cleared before the refresh below (not after) so getTicketById's own
    // `isExecuting` computation correctly sees this run as finished,
    // rather than reporting the just-completed run as still in flight.
    _inFlightExecutionIds.remove(task.id);
    _inFlightRuns.remove(task.id);
    _refreshInFlightBoardState();
    _refreshTaskDetailIfShowing();
    unawaited(_persistExecutionQueueSnapshot());

    if (wasShowingTaskDetail) {
      await getTicketById(task.id);
    }

    unawaited(_tryStartNextQueuedExecutions());
  }

  /// Handles a `ChatTurnCancelled` result from either of
  /// [_runCodingExecution]'s implement/verify turns: persists
  /// [result]'s accumulated text as one [CommentAuthorType.ai] comment on
  /// [chat] if non-empty (`runChatTurn` persists nothing itself for a
  /// cancelled turn — see [ChatCubit.runChatTurn]'s dartdoc), posts an
  /// `"Execution cancelled."` [CommentAuthorType.system] comment so the
  /// ticket doesn't look untouched, then reverts [task]'s status to
  /// whatever [_preExecutionStatus] captured immediately before the
  /// trigger that started this run (a no-op if nothing was captured —
  /// defensive only, every real trigger path captures one). Added for
  /// `aion-arch/changes/parallel-work`; see that change's design.md §5.4.
  Future<void> _handleExecutionCancelled(
    Ticket task,
    Ticket chat,
    ChatTurnCancelled result,
  ) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return;
    if (result.accumulatedText.isNotEmpty) {
      await commentRepo.addComment(
        TicketComment(
          id: '',
          ticketId: chat.id,
          content: result.accumulatedText,
          authorType: CommentAuthorType.ai,
          createdAt: DateTime.now(),
        ),
      );
    }
    await commentRepo.addComment(
      TicketComment(
        id: '',
        ticketId: chat.id,
        content: 'Execution cancelled.',
        authorType: CommentAuthorType.system,
        createdAt: DateTime.now(),
      ),
    );
    final previousStatus = _preExecutionStatus.remove(task.id);
    if (previousStatus != null) {
      await _repository.updateTicketStatus(task.id, previousStatus);
    }
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

  /// Cancels [task]'s coding-execution run — covers both the still-queued
  /// case (simply drops [task.id] from [_executionQueue] and reverts its
  /// status) and the in-flight case (signals
  /// [AgentModelClient.cancel] on the run's current turn via
  /// [_inFlightRuns]; the actual comment-persist/status-revert/cleanup
  /// sequence happens once that turn's stream actually terminates with
  /// `ChatTurnCancelled`, inside [_runCodingExecution] itself — see
  /// [_handleExecutionCancelled]). No-op if [task.id] is neither queued
  /// nor in flight. Called by the Board badge/detail-screen cancel
  /// affordances and `ExecutionCancelControl`. Added for
  /// `aion-arch/changes/parallel-work`; see that change's design.md §5.4.
  Future<void> cancelCodingExecution(Ticket task) async {
    if (_executionQueue.remove(task.id)) {
      final previousStatus = _preExecutionStatus.remove(task.id);
      if (previousStatus != null) {
        await _repository.updateTicketStatus(task.id, previousStatus);
      }
      // Posted on a best-effort basis — _resolveExecutionChat may itself
      // create the chat ticket if this is the queued entry's very first
      // trigger, so a comment repository is still required; a
      // constructor without one (or a chat-resolution failure) simply
      // skips the note rather than blocking the cancel itself. Matches
      // design.md §5.4. Fixed for `aion-arch/changes/parallel-work`
      // post-/verify — this comment was missing entirely.
      final commentRepo = _commentRepository;
      if (commentRepo != null) {
        final (chat, _) = await _resolveExecutionChat(task);
        if (chat != null) {
          await commentRepo.addComment(
            TicketComment(
              id: '',
              ticketId: chat.id,
              content: 'Execution cancelled before it started.',
              authorType: CommentAuthorType.system,
              createdAt: DateTime.now(),
            ),
          );
        }
      }
      _refreshInFlightBoardState();
      _refreshTaskDetailIfShowing();
      unawaited(_persistExecutionQueueSnapshot());
      return;
    }

    if (!_inFlightExecutionIds.contains(task.id)) return;
    final run = _inFlightRuns[task.id];
    run?.provider.client.cancel(run.runId);
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

  /// The user's persisted coding-execution scheduling mode, defaulting to
  /// [ExecutionSchedulingMode.strictFifo] when constructed without an
  /// [ExecutionSchedulingRepository] — today's unchanged behavior. Added
  /// for `aion-arch/changes/parallel-work`.
  Future<ExecutionSchedulingMode> _effectiveSchedulingMode() async {
    final repo = _executionSchedulingRepository;
    if (repo == null) return ExecutionSchedulingMode.strictFifo;
    return repo.getMode();
  }

  /// The number of coding-execution runs allowed in flight at once for
  /// [mode]: always `1` under [ExecutionSchedulingMode.strictFifo]
  /// (ignoring whatever concurrency ceiling is persisted); otherwise the
  /// persisted [ExecutionSchedulingRepository.getConcurrencyCeiling]
  /// (defaulting to `2` without a repository), additionally capped to `1`
  /// for the rest of the session once [_overageDetectedThisSession] is
  /// `true` — the same reactive-only budget-handling precedent
  /// [_effectiveCodingExecutionConfidence]'s overage-forces-`gated` check
  /// already established, applied here to concurrency instead of
  /// automation confidence. Added for `aion-arch/changes/parallel-work`.
  Future<int> _effectiveConcurrencyCeiling(ExecutionSchedulingMode mode) async {
    if (mode == ExecutionSchedulingMode.strictFifo) return 1;
    if (_overageDetectedThisSession) return 1;
    final repo = _executionSchedulingRepository;
    if (repo == null) return 2;
    return repo.getConcurrencyCeiling();
  }

  /// Under [ExecutionSchedulingMode.hybrid], returns the first still-
  /// queued Task/Bug id (FIFO order) whose parent isn't already
  /// represented among [_inFlightExecutionIds]'s own tickets — same-parent
  /// siblings never run concurrently, but an unrelated queued ticket may
  /// start ahead of one that's blocked this way. Returns the id of a
  /// queued ticket that no longer resolves (stale — defensive, not
  /// expected in practice) immediately, so the caller can skip and retry
  /// rather than stalling the whole queue behind it. Returns `null` only
  /// when every remaining queued id's parent already has an in-flight
  /// sibling — nothing eligible to start right now. Added for
  /// `aion-arch/changes/parallel-work`; see that change's design.md §5.2.
  Future<String?> _nextEligibleForHybrid() async {
    final inFlightParentIds = <String?>{};
    for (final id in _inFlightExecutionIds) {
      final ticket = await _repository.getTicketById(id);
      inFlightParentIds.add(ticket?.parentId);
    }
    for (final queuedId in _executionQueue) {
      final ticket = await _repository.getTicketById(queuedId);
      if (ticket == null) return queuedId;
      if (ticket.parentId == null ||
          !inFlightParentIds.contains(ticket.parentId)) {
        return queuedId;
      }
    }
    return null;
  }

  /// Starts as many queued Task/Bug runs as [_effectiveConcurrencyCeiling]
  /// currently allows, replacing the old single-slot `_dequeueNext`.
  /// Under [ExecutionSchedulingMode.strictFifo] this only ever starts one
  /// (the loop's own `_inFlightExecutionIds.length < ceiling` condition
  /// stops after the first, exactly like the old single-slot behavior);
  /// under [ExecutionSchedulingMode.parallel] it pops [_executionQueue]'s
  /// own FIFO head each time; under [ExecutionSchedulingMode.hybrid] it
  /// resolves each pick via [_nextEligibleForHybrid] instead, so a
  /// same-parent sibling never starts ahead of its already-in-flight
  /// counterpart, while an unrelated queued ticket still starts
  /// immediately. Skips (and refreshes past) any queued id that no longer
  /// resolves to a ticket. Called from every trigger/completion/cancel
  /// site that might have freed up scheduling capacity. Added for
  /// `aion-arch/changes/parallel-work`; see that change's design.md §5.2.
  Future<void> _tryStartNextQueuedExecutions() async {
    final mode = await _effectiveSchedulingMode();
    final ceiling = await _effectiveConcurrencyCeiling(mode);
    while (_inFlightExecutionIds.length < ceiling &&
        _executionQueue.isNotEmpty) {
      final nextId = mode == ExecutionSchedulingMode.hybrid
          ? await _nextEligibleForHybrid()
          : _executionQueue.first;
      if (nextId == null) break; // Hybrid: nothing eligible right now.

      _executionQueue.remove(nextId);
      final next = await _repository.getTicketById(nextId);
      if (next == null) {
        // Already removed above, even though nothing started running —
        // refresh so the Board doesn't show a stale queue position for
        // the ids behind the skipped one.
        _refreshInFlightBoardState();
        _refreshTaskDetailIfShowing();
        continue;
      }
      _inFlightExecutionIds.add(next.id);
      _refreshInFlightBoardState();
      _refreshTaskDetailIfShowing();
      unawaited(_persistExecutionQueueSnapshot());
      unawaited(_runCodingExecution(next));
    }
  }

  /// Persists the current [_inFlightExecutionIds]/[_executionQueue]
  /// snapshot via [_executionQueueRepository] — a no-op without one.
  /// Called (`unawaited`) from every mutation site of those two:
  /// [_triggerOrQueueCodingExecution], [_tryStartNextQueuedExecutions],
  /// [cancelCodingExecution], and [_runCodingExecution]'s completion and
  /// early-return guard paths. Added for `aion-arch/changes/parallel-work`;
  /// see that change's design.md §5.3.
  Future<void> _persistExecutionQueueSnapshot() async {
    final repo = _executionQueueRepository;
    if (repo == null) return;
    await repo.replaceSnapshot([
      for (final id in _inFlightExecutionIds)
        ExecutionQueueEntry(taskId: id, inFlight: true),
      // 1-based, matching ExecutionQueueEntry.queuePosition's/design.md
      // §5.3's documented contract — the first still-queued entry is
      // position 1, not 0.
      for (var i = 0; i < _executionQueue.length; i++)
        ExecutionQueueEntry(
          taskId: _executionQueue[i],
          inFlight: false,
          queuePosition: i + 1,
        ),
    ]);
  }

  /// Restores the coding-execution queue from [_executionQueueRepository]
  /// after an app restart — a no-op without one. Re-validates every
  /// persisted entry against the current repository state first: an
  /// entry whose ticket no longer exists, or is no longer
  /// an `executionTrigger`-role status (e.g. the user manually moved it while the
  /// app was closed), is silently dropped rather than resumed. If nothing
  /// survives re-validation, just clears the stale persisted snapshot.
  /// Otherwise branches on [AutomationContext.codingExecutionResume]'s
  /// effective confidence (via [_automationSettingsRepository], falling
  /// back to [AutomationConfidence.gated] without one):
  ///
  /// - [AutomationConfidence.auto]: re-enqueues every surviving entry and
  ///   calls [_tryStartNextQueuedExecutions] immediately.
  /// - [AutomationConfidence.gated]: surfaces the surviving tickets via
  ///   [_pendingResumeTickets]/[TicketsLoaded.pendingResumePrompt] for
  ///   `ResumeRunsPrompt` to render — [resumePendingExecutions]/
  ///   [dismissPendingResumePrompt] decide from there.
  /// - [AutomationConfidence.manual]: clears the persisted snapshot and
  ///   leaves the tickets for the existing orphaned/stalled
  ///   [_computeExecutionFailure] retry banner to pick up.
  ///
  /// Called once, immediately after construction, by whichever call site
  /// constructs this cubit's project-scoped instance (`app_router.dart`).
  /// Added for `aion-arch/changes/parallel-work`; see that change's
  /// design.md §5.3.
  Future<void> restoreExecutionQueue() async {
    final queueRepo = _executionQueueRepository;
    if (queueRepo == null) return;
    final snapshot = await queueRepo.getSnapshot();
    if (snapshot.isEmpty) return;

    final survivingTickets = <Ticket>[];
    for (final entry in snapshot) {
      final ticket = await _repository.getTicketById(entry.taskId);
      if (ticket != null &&
          _roleOf(ticket.status) == WorkflowStatusRole.executionTrigger) {
        survivingTickets.add(ticket);
      }
    }
    if (survivingTickets.isEmpty) {
      unawaited(_persistExecutionQueueSnapshot());
      return;
    }

    final automationRepo = _automationSettingsRepository;
    final confidence = automationRepo == null
        ? AutomationConfidence.gated
        : await automationRepo.getConfidence(
            AutomationContext.codingExecutionResume,
          );

    switch (confidence) {
      case AutomationConfidence.auto:
        _executionQueue.addAll(survivingTickets.map((t) => t.id));
        _refreshInFlightBoardState();
        unawaited(_tryStartNextQueuedExecutions());
      case AutomationConfidence.gated:
        _pendingResumeTickets = survivingTickets;
        _refreshInFlightBoardState();
      case AutomationConfidence.manual:
        unawaited(_persistExecutionQueueSnapshot());
    }
  }

  /// Resumes every ticket [restoreExecutionQueue]'s `gated` branch
  /// surfaced via [_pendingResumeTickets]/[TicketsLoaded.pendingResumePrompt]
  /// — re-enqueues each, clears the prompt, and calls
  /// [_tryStartNextQueuedExecutions], mirroring [restoreExecutionQueue]'s
  /// own `auto` branch. No-op if nothing is pending. Called by
  /// `ResumeRunsPrompt`'s Resume action. Added for
  /// `aion-arch/changes/parallel-work`.
  Future<void> resumePendingExecutions() async {
    final pending = _pendingResumeTickets;
    if (pending == null) return;
    _executionQueue.addAll(pending.map((t) => t.id));
    _pendingResumeTickets = null;
    _refreshInFlightBoardState();
    unawaited(_tryStartNextQueuedExecutions());
  }

  /// Dismisses [restoreExecutionQueue]'s `gated`-branch resume prompt
  /// without resuming anything — clears [_pendingResumeTickets] and the
  /// persisted snapshot, falling back to [AutomationConfidence.manual]'s
  /// own behavior (the existing orphaned/stalled
  /// [_computeExecutionFailure] retry banner is still available per
  /// ticket). Called by `ResumeRunsPrompt`'s Dismiss action. Added for
  /// `aion-arch/changes/parallel-work`.
  Future<void> dismissPendingResumePrompt() async {
    if (_pendingResumeTickets == null) return;
    _pendingResumeTickets = null;
    _refreshInFlightBoardState();
    unawaited(_persistExecutionQueueSnapshot());
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
  /// opens with: [task]'s title/description, a `## Related tickets`
  /// section from [_contextEnricher] (see
  /// [TicketContextEnricher.relatedTicketsSection] — omitted entirely
  /// when it returns `''`), the project's effective `conventions/
  /// architecture-conventions` content (see [_effectiveAssetContent]) if
  /// any, plus an instruction to implement the task using the available
  /// file, git, and bash tools, commit the result, and end the reply with
  /// exactly one line, `IMPLEMENTATION: DONE`. This no longer instructs
  /// the model to push or open a PR
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

    final related = await _contextEnricher.relatedTicketsSection(task);
    if (related.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(related);
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

  /// Adds [chatTicketId]'s most recently persisted comment's
  /// `inputTokens + outputTokens` (each treated as `0` when `null`) onto
  /// [_executionTokenTotals]`[taskId]`. Called by [_runCodingExecution]
  /// right after each implement/verify `ChatCubit.runChatTurn` call
  /// returns [ChatTurnSuccess] — at that point the turn's `ai` comment
  /// has already been persisted (by `runChatTurn` itself), so the most
  /// recent comment for [chatTicketId] is exactly the one this turn just
  /// wrote. Mirrors [_lastCommentContent]'s own "find the most recent
  /// comment" lookup. No-ops if constructed without a [CommentRepository]
  /// (mirrors [_lastCommentContent]'s same fallback). Added for
  /// `aion-arch/changes/token-cost-prediction`.
  Future<void> _addExecutionTokens(String taskId, String chatTicketId) async {
    final commentRepo = _commentRepository;
    if (commentRepo == null) return;
    final comments = await commentRepo.getCommentsForTicket(chatTicketId);
    if (comments.isEmpty) return;
    final mostRecent = comments.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final tokens = (mostRecent.inputTokens ?? 0) + (mostRecent.outputTokens ?? 0);
    _executionTokenTotals[taskId] = (_executionTokenTotals[taskId] ?? 0) + tokens;
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
  /// `aion-arch/changes/sdd-design-gate`. When [stage] has a configured
  /// [_attachmentForStage], the posted comment is [_promptFor]'s output
  /// instead of [_assembleStageContext]'s — the attachment overrides the
  /// stage's hardcoded prompt, but chat creation itself (including the
  /// [SddStage.designBrief] design-page special case above) is otherwise
  /// unaffected. Added for `aion-arch/changes/workflow-skill-attachments`.
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
          status: _defaultCreationStatus,
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
      title: '${await _stagePresentName(stage)} — ${parent.title}',
      status: _defaultCreationStatus,
      parentId: parent.id,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createTicket(chatTicket);
    final persistedChat = await _repository.getTicketById(chatTicket.id);
    if (persistedChat == null) return null;

    final attachment = _attachmentForStage(stage);
    final context = attachment != null
        ? await _promptFor(attachment, parent)
        : await _assembleStageContext(parent, stage);
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
  /// and `aion-arch/changes/board-task-ordering-indication`. When [stage]
  /// has a configured [_attachmentForStage], re-derives [_promptFor]'s
  /// output instead of [_assembleStageContext]'s, resolves the model via
  /// [attachment.kind]'s [ModelPhase] (mirroring [_fireSkillAttachment]'s
  /// own selection: [ModelPhase.capable] for `aionNativeTemplate`,
  /// [ModelPhase.execution] for `delegatedSkill`) instead of [stage
  /// .modelPhase], sets `toolsEnabled`/`workingDirectory` per
  /// [attachment.kind] instead of always text-only, and offers no
  /// app-defined `tools` (skips [_toolCallParamsFor] — see
  /// proposal.md's Non-goals). When `attachmentToolsEnabled`, runs
  /// inside a fresh isolated `git worktree` (via
  /// [GitRepositoryClient.createWorktree]/`.removeWorktree`) exactly
  /// like [_runCodingExecution] — never [_projectRootPath] itself, so a
  /// `delegatedSkill` attachment can't touch the developer's real
  /// checkout. Throws (caught below, posting the usual failure comment)
  /// if constructed without a [GitRepositoryClient]/`projectRootPath` in
  /// that case. Added for `aion-arch/changes/workflow-skill-attachments`.
  Future<void> _runStageChatTurn(
    Ticket parent,
    SddStage stage,
    String chatId,
  ) async {
    final providerRegistry = _providerRegistry;
    final commentRepo = _commentRepository;
    if (providerRegistry == null || commentRepo == null) return;

    String? worktreePath;
    try {
      final attachment = _attachmentForStage(stage);
      final context = attachment != null
          ? await _promptFor(attachment, parent)
          : await _assembleStageContext(parent, stage);
      final attachmentToolsEnabled =
          attachment?.kind == SkillAttachmentKind.delegatedSkill;
      final (model, provider) = await _resolveModelAndProvider(
        attachment == null
            ? stage.modelPhase
            : (attachmentToolsEnabled ? ModelPhase.execution : ModelPhase.capable),
      );
      var tools = const <AgentToolDefinition>[];
      Future<Map<String, dynamic>> Function(
        String toolCallId,
        String toolName,
        Map<String, dynamic> arguments,
      )?
      onToolCall;
      if (attachment == null) {
        (tools, onToolCall) = await _toolCallParamsFor(chatId);
      }
      if (attachmentToolsEnabled) {
        final gitClient = _gitClient;
        final rootPath = _projectRootPath;
        if (gitClient == null || rootPath == null) {
          throw StateError(
            'Delegated-skill attachments require a git client and '
            'project checkout to run in an isolated worktree.',
          );
        }
        worktreePath = Directory.systemTemp
            .createTempSync('aion_skill_')
            .path;
        await gitClient.createWorktree(
          rootPath,
          worktreePath,
          'aion/skill-${attachment!.id}-${_uuid.v4()}',
        );
      }
      final result = await ChatCubit.runChatTurn(
        client: provider.client,
        provider: provider,
        commentRepo: commentRepo,
        chatTicketId: chatId,
        prompt: context,
        model: model,
        toolsEnabled: attachment == null ? false : attachmentToolsEnabled,
        workingDirectory: worktreePath,
        tools: tools,
        onToolCall: onToolCall,
      );
      // No `runId` is passed above, so ChatTurnCancelled can never
      // actually occur here in practice (no stop-button UI is wired to
      // SDD-stage chats this slice) — handled defensively anyway,
      // preserving today's exact true/false-equivalent behavior for
      // ChatTurnSuccess/ChatTurnFailure.
      final succeeded = switch (result) {
        ChatTurnSuccess() => true,
        ChatTurnFailure() || ChatTurnCancelled() => false,
      };
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
      if (worktreePath != null) {
        final gitClient = _gitClient;
        final rootPath = _projectRootPath;
        if (gitClient != null && rootPath != null) {
          try {
            await gitClient.removeWorktree(rootPath, worktreePath);
          } catch (_) {
            // Best-effort cleanup only, mirrors _runCodingExecution's
            // own finally block — createWorktree may itself have
            // failed, in which case there's nothing to remove.
          }
        }
      }
      _inFlightStageAdvanceIds
        ..remove(parent.id)
        ..remove(chatId);
      _refreshInFlightBoardState();
    }
  }

  // ---------------------------------------------------------------------
  // Skill attachments — generalizes _createStageChat/_runStageChatTurn's
  // shape (above) to any SkillAttachment, whether it's attached to a
  // WorkflowStatus or an SddStage. See
  // aion-arch/changes/workflow-skill-attachments/design.md §3.
  // ---------------------------------------------------------------------

  /// Builds [attachment]'s run prompt against [parent]:
  /// [SkillAttachmentKind.aionNativeTemplate] renders the referenced
  /// [WorkflowPromptTemplate] via [renderWorkflowPromptTemplate] (falling
  /// back to a defensive `"(template not found)"` placeholder if
  /// [_workflowPromptTemplateRepository] is `null` or [attachment
  /// .templateId] no longer resolves — a since-deleted template, or a
  /// cubit constructed without one); [SkillAttachmentKind.delegatedSkill]
  /// returns the literal `/<skillName>` slash-command text, chosen over a
  /// natural-language description match because an automation feature
  /// needs a deterministic trigger. See
  /// `aion-arch/changes/workflow-skill-attachments/design.md` §3.2.
  Future<String> _promptFor(SkillAttachment attachment, Ticket parent) async {
    switch (attachment.kind) {
      case SkillAttachmentKind.aionNativeTemplate:
        final templateRepo = _workflowPromptTemplateRepository;
        final templateId = attachment.templateId;
        if (templateRepo == null || templateId == null) {
          return '(template not found)';
        }
        final templates = await templateRepo.getAll();
        final template = templates
            .where((t) => t.id == templateId)
            .firstOrNull;
        if (template == null) return '(template not found)';
        return renderWorkflowPromptTemplate(template, parent);
      case SkillAttachmentKind.delegatedSkill:
        return '/${attachment.skillName}';
    }
  }

  /// A short, human-readable label for [attachment.kind], used to title
  /// the chat ticket [_fireSkillAttachment] spawns.
  String _skillAttachmentKindLabel(SkillAttachment attachment) =>
      switch (attachment.kind) {
        SkillAttachmentKind.aionNativeTemplate => 'Template',
        SkillAttachmentKind.delegatedSkill => 'Skill',
      };

  /// Spawns a `chat`-type child ticket under [parent] titled
  /// `'<kind label> — <parent.title>'`, posts [_promptFor]'s result as a
  /// [CommentAuthorType.system] comment, and runs it via
  /// [ChatCubit.runChatTurn] — generalizing [_createStageChat] +
  /// [_runStageChatTurn]'s exact two-phase shape to any [SkillAttachment]
  /// rather than only an [SddStage]. `toolsEnabled`/`workingDirectory` are
  /// set per [attachment.kind]:
  ///
  /// | `kind` | `toolsEnabled` | `workingDirectory` |
  /// |---|---|---|
  /// | `aionNativeTemplate` | `false` | `null` |
  /// | `delegatedSkill` | `true` | a fresh isolated `git worktree` |
  ///
  /// For `delegatedSkill`, the worktree is created via
  /// [GitRepositoryClient.createWorktree] on a fresh
  /// `aion/skill-<attachment.id>-<uuid>` branch and always removed in a
  /// `finally` — mirrors [_runCodingExecution]'s own worktree-isolation
  /// shape exactly, never running tool-enabled against [_projectRootPath]
  /// itself, so the developer's real checkout is never touched by an
  /// unattended (`auto`-confidence) attachment run.
  ///
  /// The model is resolved via [_resolveModelAndProvider] using
  /// [ModelPhase.capable] for `aionNativeTemplate` (comparatively
  /// mechanical, text-only work — the same tier `designBrief`/`designSync`
  /// use) and [ModelPhase.execution] for `delegatedSkill` (the only other
  /// tool-enabled phase, [ModelPhaseToolAccess.requiredToolAccessTier]
  /// being [ToolAccessTier.full] for both). No app-defined `tools` are
  /// offered (see proposal.md's Non-goals). No-ops if constructed without
  /// a [ProviderRegistry]/[CommentRepository] (see the constructor's
  /// dartdoc). A hard error — including a `delegatedSkill` run
  /// constructed without a [GitRepositoryClient]/`projectRootPath`, which
  /// throws rather than silently falling back to [_projectRootPath] — is
  /// caught and posted as a "Skill attachment failed: `<e>`"
  /// [CommentAuthorType.system] comment, mirroring [_runStageChatTurn]'s
  /// own catch-comment shape.
  Future<void> _fireSkillAttachment(
    Ticket parent,
    SkillAttachment attachment,
  ) async {
    final providerRegistry = _providerRegistry;
    final commentRepo = _commentRepository;
    if (providerRegistry == null || commentRepo == null) return;

    final now = DateTime.now();
    final chatTicket = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.chat,
      title: '${_skillAttachmentKindLabel(attachment)} — ${parent.title}',
      status: _defaultCreationStatus,
      parentId: parent.id,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createTicket(chatTicket);
    final persistedChat = await _repository.getTicketById(chatTicket.id);
    if (persistedChat == null) return;

    final prompt = await _promptFor(attachment, parent);
    await commentRepo.addComment(
      TicketComment(
        id: '',
        ticketId: persistedChat.id,
        content: prompt,
        authorType: CommentAuthorType.system,
        createdAt: DateTime.now(),
      ),
    );

    final toolsEnabled =
        attachment.kind == SkillAttachmentKind.delegatedSkill;
    String? worktreePath;
    try {
      if (toolsEnabled) {
        final gitClient = _gitClient;
        final rootPath = _projectRootPath;
        if (gitClient == null || rootPath == null) {
          throw StateError(
            'Delegated-skill attachments require a git client and '
            'project checkout to run in an isolated worktree.',
          );
        }
        worktreePath = Directory.systemTemp
            .createTempSync('aion_skill_')
            .path;
        await gitClient.createWorktree(
          rootPath,
          worktreePath,
          'aion/skill-${attachment.id}-${_uuid.v4()}',
        );
      }
      final (model, provider) = await _resolveModelAndProvider(
        toolsEnabled ? ModelPhase.execution : ModelPhase.capable,
      );
      await ChatCubit.runChatTurn(
        client: provider.client,
        provider: provider,
        commentRepo: commentRepo,
        chatTicketId: persistedChat.id,
        prompt: prompt,
        model: model,
        toolsEnabled: toolsEnabled,
        workingDirectory: worktreePath,
      );
    } catch (e) {
      await commentRepo.addComment(
        TicketComment(
          id: '',
          ticketId: persistedChat.id,
          content: 'Skill attachment failed: $e',
          authorType: CommentAuthorType.system,
          createdAt: DateTime.now(),
        ),
      );
    } finally {
      if (worktreePath != null) {
        final gitClient = _gitClient;
        final rootPath = _projectRootPath;
        if (gitClient != null && rootPath != null) {
          try {
            await gitClient.removeWorktree(rootPath, worktreePath);
          } catch (_) {
            // Best-effort cleanup only, mirrors _runCodingExecution's
            // own finally block — createWorktree may itself have
            // failed, in which case there's nothing to remove.
          }
        }
      }
    }
  }

  /// Pending `SkillAttachment`s (confidence `gated`) awaiting user
  /// confirmation, keyed by the *parent* ticket id that just entered the
  /// attachment's target status/stage — mirrors [_pendingProposals]'
  /// shape, one level simpler (no [Completer] to resolve, since firing a
  /// skill attachment doesn't pause an in-flight model turn the way a
  /// `branch_ticket` tool call does). Each entry pairs the
  /// [SkillAttachment] shown by [TicketDetailLoaded.pendingSkillAttachment]
  /// with the actual fire action to run on confirm — see
  /// [_resolveAndFireAttachment]'s `fire` parameter for why this isn't
  /// always [_fireSkillAttachment]. Cleared by
  /// [confirmPendingSkillAttachment]/[rejectPendingSkillAttachment]. See
  /// `aion-arch/changes/workflow-skill-attachments/design.md` §3.3.
  final Map<String, ({SkillAttachment attachment, Future<void> Function() fire})>
  _pendingSkillAttachments = {};

  /// Resolves how [attachment] fires for [parent], per
  /// [attachment.confidence]: `auto` runs [fire] immediately, `unawaited`;
  /// `gated` records [parent.id] → `(attachment, fire)` in
  /// [_pendingSkillAttachments] and, if [parent]'s detail screen is
  /// currently open, re-emits [TicketDetailLoaded] carrying
  /// [TicketDetailLoaded.pendingSkillAttachment] (mirrors
  /// [_refreshDetailIfOpenAndAffected]'s existing "is this ticket's
  /// detail screen open" check); `manual` no-ops —
  /// [runAttachedSkillManually] is the only trigger.
  ///
  /// [fire] defaults to `() => _fireSkillAttachment(parent, attachment)`
  /// (spawning a fresh chat) — what [updateTicketStatus]/
  /// [updateStatusForTickets] pass via [_attachmentForStatus], since a
  /// status entry has no existing chat to run the attachment on. The
  /// [SddStage] hook ([_createStageChat]/[advanceSddStage], via
  /// [_attachmentForStage]) passes an explicit [fire] instead — one that
  /// runs [_runStageChatTurn] on the stage chat [_createStageChat]
  /// *already created* (with [_promptFor]'s output as its opening
  /// comment), per proposal.md's "inside the same existing
  /// `_createStageChat`/`_runStageChatTurn` flow" — reusing that chat
  /// rather than spawning a second, orphaned one.
  Future<void> _resolveAndFireAttachment(
    Ticket parent,
    SkillAttachment attachment, {
    Future<void> Function()? fire,
  }) async {
    final fireAction = fire ?? () => _fireSkillAttachment(parent, attachment);
    switch (attachment.confidence) {
      case AutomationConfidence.auto:
        unawaited(fireAction());
      case AutomationConfidence.gated:
        _pendingSkillAttachments[parent.id] = (
          attachment: attachment,
          fire: fireAction,
        );
        final current = state;
        if (current is TicketDetailLoaded && current.ticket.id == parent.id) {
          // copyWith, not a bare TicketDetailLoaded(parent, ...) — the
          // latter would silently reset every other computed field
          // (childDocs, gapsAndOpenQuestions, canAdvanceSddStage,
          // isExecuting, etc.) to its default. See TicketDetailLoaded
          // .copyWith's dartdoc.
          emit(
            current.copyWith(
              ticket: parent,
              pendingSkillAttachment: () => attachment,
            ),
          );
        }
      case AutomationConfidence.manual:
        break;
    }
  }

  /// Confirms [ticketId]'s pending [SkillAttachment] (if any): removes it
  /// from [_pendingSkillAttachments] and runs its recorded fire action,
  /// `unawaited` (mirrors [_resolveAndFireAttachment]'s own `auto`
  /// branch). If [ticketId]'s detail screen is currently open, re-emits
  /// [TicketDetailLoaded] via [TicketDetailLoaded.copyWith] with
  /// `pendingSkillAttachment` cleared — every other already-loaded field
  /// (`childDocs`, `canAdvanceSddStage`, `isExecuting`, etc.) is carried
  /// over unchanged, unlike the bare `TicketDetailLoaded(ticket)` this
  /// used to construct, which silently reset them all. No-ops if
  /// [ticketId] has no pending attachment. Mirrors
  /// [confirmPendingToolProposal]'s shape.
  Future<void> confirmPendingSkillAttachment(String ticketId) async {
    final pending = _pendingSkillAttachments.remove(ticketId);
    if (pending == null) return;
    unawaited(pending.fire());
    final current = state;
    if (current is TicketDetailLoaded && current.ticket.id == ticketId) {
      emit(current.copyWith(pendingSkillAttachment: () => null));
    }
  }

  /// Rejects [ticketId]'s pending [SkillAttachment]: removes it from
  /// [_pendingSkillAttachments] without ever running its fire action. If
  /// [ticketId]'s detail screen is currently open, re-emits
  /// [TicketDetailLoaded] via [TicketDetailLoaded.copyWith] with
  /// `pendingSkillAttachment` cleared, preserving every other
  /// already-loaded field — see [confirmPendingSkillAttachment]'s
  /// dartdoc for why this no longer constructs a bare
  /// `TicketDetailLoaded(ticket)`. No-ops if [ticketId] has no pending
  /// attachment. Mirrors [rejectPendingToolProposal]'s shape.
  Future<void> rejectPendingSkillAttachment(String ticketId) async {
    final pending = _pendingSkillAttachments.remove(ticketId);
    if (pending == null) return;
    final current = state;
    if (current is TicketDetailLoaded && current.ticket.id == ticketId) {
      emit(current.copyWith(pendingSkillAttachment: () => null));
    }
  }

  /// A human-readable name for [attachment] — the delegated skill's
  /// literal name, or its referenced `WorkflowPromptTemplate`'s name
  /// (falling back to a defensive placeholder if it no longer resolves,
  /// or if constructed without a [WorkflowPromptTemplateRepository]).
  /// Exposed for `_PendingSkillAttachmentBanner`/`_RunAttachedSkillButton`
  /// (`ticket_detail_screen.dart`), which have no direct
  /// `WorkflowPromptTemplateRepository` access of their own. Added for
  /// `aion-arch/changes/workflow-skill-attachments`.
  Future<String> attachmentDisplayName(SkillAttachment attachment) async {
    if (attachment.kind == SkillAttachmentKind.delegatedSkill) {
      return attachment.skillName ?? '';
    }
    final templateRepo = _workflowPromptTemplateRepository;
    final templateId = attachment.templateId;
    if (templateRepo == null || templateId == null) {
      return '(template not found)';
    }
    final templates = await templateRepo.getAll();
    return templates.where((t) => t.id == templateId).firstOrNull?.name ??
        '(deleted template)';
  }

  /// Resolves [ticket]'s current status/stage [SkillAttachment], or
  /// `null` — status takes precedence (a ticket's status and `sddStage`
  /// are independent axes, but only one is meaningful for a non-epic/
  /// story ticket). Shared by [runAttachedSkillManually] (which further
  /// filters on `confidence == manual` before firing) and exposed
  /// publicly, read-only, so `_RunAttachedSkillButton`
  /// (`ticket_detail_screen.dart`) can decide its own visibility without
  /// duplicating this resolution. Added for
  /// `aion-arch/changes/workflow-skill-attachments`.
  SkillAttachment? resolveCurrentAttachment(Ticket ticket) {
    final statusId = _resolveStatus(ticket.status)?.id;
    return (statusId != null ? _attachmentForStatus(statusId) : null) ??
        (ticket.sddStage != null
            ? _attachmentForStage(ticket.sddStage!)
            : null);
  }

  /// Always-available manual trigger: resolves [ticket]'s current
  /// [resolveCurrentAttachment] and fires it via [_fireSkillAttachment],
  /// `unawaited`. No-ops if [ticket] has no resolved attachment, or its
  /// confidence isn't [AutomationConfidence.manual] — every other
  /// confidence already has its own automatic firing path, so a manual
  /// re-trigger through this method would double-fire it.
  Future<void> runAttachedSkillManually(Ticket ticket) async {
    final attachment = resolveCurrentAttachment(ticket);
    if (attachment == null || attachment.confidence != AutomationConfidence.manual) {
      return;
    }
    unawaited(_fireSkillAttachment(ticket, attachment));
  }

  // ---------------------------------------------------------------------
  // Mid-task/issue chat branching — branch_ticket/close_branch tool
  // handlers, gated by AutomationContext.chatBranching. See
  // aion-arch/changes/mid-task-chat-branching/design.md §6.
  // ---------------------------------------------------------------------

  /// Pending `branch_ticket`/`close_branch` proposals awaiting user
  /// confirmation (`AutomationConfidence.gated`), keyed by the chat
  /// ticket id whose turn is paused. Each entry pairs the
  /// [PendingToolProposal] shown by [TicketDetailLoaded.pendingToolProposal]
  /// with the [Completer] [AgentRequest.onToolCall] is awaiting and the
  /// action to run on confirm. Cleared by
  /// [confirmPendingToolProposal]/[rejectPendingToolProposal]. Added for
  /// `aion-arch/changes/mid-task-chat-branching`; see that change's
  /// design.md §6.
  final Map<
    String,
    ({
      PendingToolProposal proposal,
      Completer<Map<String, dynamic>> completer,
      Future<Map<String, dynamic>> Function() onConfirm,
    })
  >
  _pendingProposals = {};

  /// Tools offered on [chatTicketId]'s next turn — this cubit's own copy of
  /// [ChatCubit._toolsFor], mirroring its shape independently rather than
  /// sharing an implementation across cubits (see that method's dartdoc
  /// for the underlying "exactly one of the two" rule). Added for
  /// `aion-arch/changes/mid-task-chat-branching`; see that change's
  /// design.md §6.
  Future<List<AgentToolDefinition>> _toolsFor(String chatTicketId) async {
    final chat = await _repository.getTicketById(chatTicketId);
    final parentId = chat?.parentId;
    if (parentId == null) return [branchTicketToolDefinition];
    final parent = await _repository.getTicketById(parentId);
    return parent?.type == TicketType.chat
        ? [closeBranchToolDefinition]
        : [branchTicketToolDefinition];
  }

  /// Resolves [ChatCubit.runChatTurn]'s `tools`/`onToolCall` for
  /// [chatTicketId] in one step, for the two call sites that build an
  /// `AgentRequest` for a chat turn from inside this cubit without already
  /// holding the chat [Ticket] in hand (`_runStageChatTurn`,
  /// `_runCodingExecution`'s execution-chat turns) — `tools` empty and
  /// `onToolCall` `null` together if [chatTicketId] can't be read back,
  /// keeping [AgentRequest]'s own "non-empty tools needs onToolCall"
  /// invariant honest rather than assumed (it should never actually be
  /// unreadable at these call sites). `retryDesignSync` does *not* call
  /// this: it already has its chat ticket as a parameter, so it inlines the
  /// equivalent `_toolsFor`/`_onToolCallFor` pair directly rather than
  /// paying for a redundant [TicketRepository.getTicketById] this helper's
  /// own lookup would otherwise duplicate. Added for
  /// `aion-arch/changes/mid-task-chat-branching`.
  Future<
    (
      List<AgentToolDefinition> tools,
      Future<Map<String, dynamic>> Function(
        String toolCallId,
        String toolName,
        Map<String, dynamic> arguments,
      )?
      onToolCall,
    )
  >
  _toolCallParamsFor(String chatTicketId) async {
    final chat = await _repository.getTicketById(chatTicketId);
    if (chat == null) return (const <AgentToolDefinition>[], null);
    return (await _toolsFor(chatTicketId), _onToolCallFor(chat));
  }

  /// Builds the `onToolCall` handler for [chat]'s next turn: dispatches a
  /// `close_branch` call to [_handleCloseBranchToolCall] and everything
  /// else (i.e. `branch_ticket`, the only other tool [_toolsFor] ever
  /// offers) to [_handleBranchToolCall] — both bound to [chat], the same
  /// ticket [_toolsFor] resolved tools for at this call site. Added for
  /// `aion-arch/changes/mid-task-chat-branching`.
  Future<Map<String, dynamic>> Function(
    String toolCallId,
    String toolName,
    Map<String, dynamic> arguments,
  )
  _onToolCallFor(Ticket chat) {
    return (toolCallId, toolName, arguments) =>
        toolName == closeBranchToolDefinition.name
        ? _handleCloseBranchToolCall(chat, arguments)
        : _handleBranchToolCall(chat, arguments);
  }

  /// Public entry point for a `chat` ticket's `branch_ticket`/
  /// `close_branch` tool calls, for callers outside this cubit that can't
  /// reach the private [_handleBranchToolCall]/[_handleCloseBranchToolCall]
  /// handlers directly — `TicketDetailScreen` wires this in as
  /// [ChatCubit.sendMessage]'s `onToolCall` for a human-initiated follow-up
  /// turn, since `ChatCubit` doesn't depend on this cubit (see
  /// [ChatCubit.sendMessage]'s dartdoc). Dispatches via [_onToolCallFor].
  /// Added for `aion-arch/changes/mid-task-chat-branching`.
  Future<Map<String, dynamic>> handleChatToolCall(
    Ticket chat,
    String toolCallId,
    String toolName,
    Map<String, dynamic> arguments,
  ) => _onToolCallFor(chat)(toolCallId, toolName, arguments);

  /// Whether [chat] (a `chat` ticket) may currently be branched via
  /// `branch_ticket` — instance-level depth-cap check, deliberately not on
  /// [TicketTypeHierarchy] (see that extension's `canParent` dartdoc for
  /// why): `false` if [chat] has no parent (an Inbox-spawned chat stays
  /// parentless) or its parent is itself a `chat` (a branch is a true
  /// leaf — no branch-of-a-branch). Added for
  /// `aion-arch/changes/mid-task-chat-branching`; see that change's
  /// design.md §6.
  Future<bool> _canBranch(Ticket chat) async {
    final parentId = chat.parentId;
    if (parentId == null) return false;
    final parent = await _repository.getTicketById(parentId);
    return parent != null && parent.type != TicketType.chat;
  }

  /// Creates a child `chat` ticket titled [title] (with optional
  /// [description]) under [chat] — mirrors [_createStageChat]'s direct-
  /// repository-create shape rather than the list-oriented public
  /// [createTicket]. Posts no comment on the new branch chat itself; its
  /// next turn (triggered separately, once navigated to or otherwise
  /// addressed) opens it like any other freshly created chat. Returns the
  /// persisted child's id. Added for
  /// `aion-arch/changes/mid-task-chat-branching`; see that change's
  /// design.md §6.
  Future<String> _createBranchChat(
    Ticket chat,
    String title,
    String? description,
  ) async {
    final now = DateTime.now();
    final branchChat = Ticket(
      id: _uuid.v4(),
      ticketId: '',
      type: TicketType.chat,
      title: title,
      description: description,
      status: _defaultCreationStatus,
      parentId: chat.id,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.createTicket(branchChat);
    return branchChat.id;
  }

  /// Folds [branchChat]'s resolution back into its parent ([parentId]):
  /// flips [branchChat]'s own status to a `done`-role status and posts one
  /// [CommentAuthorType.system] comment carrying [summary] onto
  /// [parentId]'s transcript — the "fold into documentation" `project.md`
  /// §2 describes, adapted to a chat ticket's comment-thread-as-content
  /// shape. No-ops the comment (but still closes [branchChat]) if
  /// constructed without a [CommentRepository] — real usage
  /// (`app_router.dart`) always supplies one. Added for
  /// `aion-arch/changes/mid-task-chat-branching`; see that change's
  /// design.md §6.
  Future<void> _closeBranch(
    Ticket branchChat,
    String parentId,
    String summary,
  ) async {
    await _repository.updateTicketStatus(branchChat.id, _doneStatus);
    final commentRepo = _commentRepository;
    if (commentRepo == null) return;
    await commentRepo.addComment(
      TicketComment(
        id: '',
        ticketId: parentId,
        content: summary,
        authorType: CommentAuthorType.system,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Registers [proposal] as [chat]'s pending tool-call confirmation,
  /// emits [TicketDetailLoaded] carrying it (driving `_ToolProposalBanner`),
  /// and returns a [Future] that resolves once
  /// [confirmPendingToolProposal]/[rejectPendingToolProposal] is called for
  /// [chat]'s id — the underlying model run stays paused on the awaited
  /// [AgentRequest.onToolCall] until then, per that field's "no timeout"
  /// contract (see proposal.md's Non-goals). [onConfirm] runs only if the
  /// user confirms, and its result becomes the resolved map; a reject
  /// resolves with a fixed decline map instead — see
  /// [confirmPendingToolProposal]/[rejectPendingToolProposal]. Added for
  /// `aion-arch/changes/mid-task-chat-branching`; see that change's
  /// design.md §6.
  Future<Map<String, dynamic>> _awaitProposalConfirmation(
    Ticket chat,
    PendingToolProposal proposal, {
    required Future<Map<String, dynamic>> Function() onConfirm,
  }) {
    final completer = Completer<Map<String, dynamic>>();
    _pendingProposals[chat.id] = (
      proposal: proposal,
      completer: completer,
      onConfirm: onConfirm,
    );
    emit(TicketDetailLoaded(chat, pendingToolProposal: proposal));
    return completer.future;
  }

  /// The `branch_ticket` tool's [AgentRequest.onToolCall] implementation:
  /// resolves [AutomationContext.chatBranching]'s confidence and switches
  /// on it — `manual` declines outright (never surfaces proactively, per
  /// proposal.md's Non-goals), `auto` creates the branch immediately via
  /// [_createBranchChat], `gated` surfaces a [BranchProposal] via
  /// [_awaitProposalConfirmation] and waits. [chat] must satisfy
  /// [_canBranch] or this declines with a depth-cap reason before ever
  /// checking automation confidence. Added for
  /// `aion-arch/changes/mid-task-chat-branching`; see that change's
  /// design.md §6.
  Future<Map<String, dynamic>> _handleBranchToolCall(
    Ticket chat,
    Map<String, dynamic> arguments,
  ) async {
    final title = arguments['title'] as String? ?? 'Untitled branch';
    final description = arguments['description'] as String?;

    if (!await _canBranch(chat)) {
      return {'accepted': false, 'reason': 'Already at branch depth cap.'};
    }

    final automationRepo = _automationSettingsRepository;
    final confidence = automationRepo == null
        ? AutomationConfidence.gated
        : await automationRepo.getConfidence(AutomationContext.chatBranching);

    switch (confidence) {
      case AutomationConfidence.manual:
        return {'accepted': false, 'reason': 'Automation set to manual.'};
      case AutomationConfidence.auto:
        final childId = await _createBranchChat(chat, title, description);
        return {'accepted': true, 'childChatId': childId};
      case AutomationConfidence.gated:
        return _awaitProposalConfirmation(
          chat,
          PendingToolProposal.branch(title: title, description: description),
          onConfirm: () async {
            final childId = await _createBranchChat(chat, title, description);
            return {'accepted': true, 'childChatId': childId};
          },
        );
    }
  }

  /// The `close_branch` tool's [AgentRequest.onToolCall] implementation —
  /// symmetric to [_handleBranchToolCall]. Declines unless [chat]'s own
  /// parent is itself a `chat` (i.e. [chat] actually is a branch);
  /// resolves [AutomationContext.chatBranching]'s confidence the same way,
  /// folding via [_closeBranch] on `auto`, or surfacing a
  /// [CloseBranchProposal] via [_awaitProposalConfirmation] on `gated`.
  /// Added for `aion-arch/changes/mid-task-chat-branching`; see that
  /// change's design.md §6.
  Future<Map<String, dynamic>> _handleCloseBranchToolCall(
    Ticket chat,
    Map<String, dynamic> arguments,
  ) async {
    final summary = arguments['summary'] as String? ?? 'Branch resolved.';
    final parentId = chat.parentId;
    final parent = parentId == null
        ? null
        : await _repository.getTicketById(parentId);
    if (parentId == null || parent?.type != TicketType.chat) {
      return {'accepted': false, 'reason': 'Not a branch chat.'};
    }

    final automationRepo = _automationSettingsRepository;
    final confidence = automationRepo == null
        ? AutomationConfidence.gated
        : await automationRepo.getConfidence(AutomationContext.chatBranching);

    switch (confidence) {
      case AutomationConfidence.manual:
        return {'accepted': false, 'reason': 'Automation set to manual.'};
      case AutomationConfidence.auto:
        await _closeBranch(chat, parentId, summary);
        return {'accepted': true};
      case AutomationConfidence.gated:
        return _awaitProposalConfirmation(
          chat,
          PendingToolProposal.close(summary: summary),
          onConfirm: () async {
            await _closeBranch(chat, parentId, summary);
            return {'accepted': true};
          },
        );
    }
  }

  /// Confirms [chatId]'s pending proposal (if any): runs its `onConfirm`
  /// action and resolves the held [AgentRequest.onToolCall] future with
  /// the result, letting the paused model run continue. Re-emits
  /// [TicketDetailLoaded] for [chatId] (with no `pendingToolProposal`)
  /// once resolved. No-ops if [chatId] has no pending proposal. Added for
  /// `aion-arch/changes/mid-task-chat-branching`; see that change's
  /// design.md §6.
  Future<void> confirmPendingToolProposal(String chatId) async {
    final pending = _pendingProposals.remove(chatId);
    if (pending == null) return;
    final (:proposal, :completer, :onConfirm) = pending;
    final result = await onConfirm();
    completer.complete(result);
    final chat = await _repository.getTicketById(chatId);
    if (chat != null) emit(TicketDetailLoaded(chat));
  }

  /// Rejects [chatId]'s pending proposal: resolves the held
  /// [AgentRequest.onToolCall] future with `{'accepted': false, 'reason':
  /// 'Declined by user.'}` — the model continues its turn knowing the
  /// branch/close didn't happen. Re-emits [TicketDetailLoaded] for
  /// [chatId] (with no `pendingToolProposal`). No-ops if [chatId] has no
  /// pending proposal. Added for `aion-arch/changes/mid-task-chat-branching`;
  /// see that change's design.md §6.
  Future<void> rejectPendingToolProposal(String chatId) async {
    final pending = _pendingProposals.remove(chatId);
    if (pending == null) return;
    pending.completer.complete({
      'accepted': false,
      'reason': 'Declined by user.',
    });
    final chat = await _repository.getTicketById(chatId);
    if (chat != null) emit(TicketDetailLoaded(chat));
  }

  /// Assembles the plain-text context a spawned stage chat opens with:
  /// [parent]'s title/description, a `## Related tickets` section from
  /// [_contextEnricher] (see
  /// [TicketContextEnricher.relatedTicketsSection] — omitted entirely
  /// when it returns `''`), and — for [SddStage.verifying]/
  /// [SddStage.archived] — its direct children's titles and statuses, or
  /// — for [SddStage.designBrief]/[SddStage.designSync] — the existing
  /// design-token file contents (see [_readTokenFilesForContext]) and,
  /// for [SddStage.designSync] specifically, the linked design Page's
  /// pasted content (see [_linkedDesignPage]), or — for
  /// [SddStage.proposed] — instructions to end the reply with a fenced
  /// `## Decomposition` block (parsed by [_parseDecomposition] once the
  /// turn completes, see [_materializeDecomposition]). Shared by
  /// [_createStageChat], [_runStageChatTurn], and [retryDesignSync] (which
  /// calls this method directly, so the related-tickets walk automatically
  /// re-runs on retry too).
  Future<String> _assembleStageContext(Ticket parent, SddStage stage) async {
    final buffer = StringBuffer()..writeln('# ${parent.title}');
    final description = parent.description;
    if (description != null && description.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(description);
    }

    final related = await _contextEnricher.relatedTicketsSection(parent);
    if (related.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(related);
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
              ? child.status
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
        status: _defaultCreationStatus,
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
  /// name instead (design.md §1.3). Resolves through
  /// [_sddStageConfigRepository]'s persisted display-name override first
  /// (`null` when this cubit was constructed without one, or when the
  /// project hasn't overridden [stage]), falling back to
  /// [_stageHardcodedPresentName] — today's exact hardcoded literal —
  /// otherwise. Added for `aion-arch/changes/configurable-ticket-workflow`.
  Future<String> _stagePresentName(SddStage stage) async {
    final override = await _sddStageConfigRepository?.getDisplayNameOverride(
      stage,
    );
    return override ?? _stageHardcodedPresentName(stage);
  }

  /// [stage]'s own hardcoded present-progressive name — the fallback
  /// [_stagePresentName] uses when no override is configured.
  String _stageHardcodedPresentName(SddStage stage) => switch (stage) {
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

  /// Fires [PageWikilinkIndexer.reindexAndCascade] for a `page` edit from
  /// [oldTicket] to [newTicket] — see [updateTicket]'s tail step, gated
  /// there exactly like the embedding-regen trigger (title/description
  /// actually changed), so a field-only edit (e.g. `syncStatus`) never
  /// re-parses content or rewrites `page_wikilinks` rows for nothing. A
  /// referrer whose content needs a title-anchored rewrite is applied by
  /// recursing through [updateTicket] itself (`applyRewrittenReferrer`
  /// below) — inheriting this method's own embedding-regen/rollup/
  /// wikilink-reindex side effects for free, and safe from further
  /// recursion since a rewrite call never itself changes a title. Never
  /// awaited by [updateTicket] — a wikilink reindex must never block a
  /// ticket save.
  Future<void> _reindexAndCascadeWikilinks(
    PageWikilinkIndexer indexer,
    Ticket oldTicket,
    Ticket newTicket,
  ) {
    return indexer.reindexAndCascade(
      oldTicket: oldTicket,
      newTicket: newTicket,
      applyRewrittenReferrer: (referrer, rewritten) =>
          updateTicket(referrer.copyWith(description: () => rewritten)),
    );
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
  Future<void> _recomputeRollupChain(Set<String> startIds, String eventLabel) {
    return _rollupRecomputer.recompute(startIds, eventLabel);
  }

  /// Declares which direct-child ticket types a parent's displayed detail
  /// state (`TicketDetailLoaded.canAdvanceSddStage`/`sddStageBlockReason`,
  /// computed from `getTicketsByParent` — see [getTicketById]'s dartdoc)
  /// depends on. Checked by [_refreshDetailIfOpenAndAffected]: whenever a
  /// write touches a ticket whose `(parent.type, ticket.type)` pair
  /// appears here, the parent's open detail screen (if that's what's
  /// currently shown) is silently re-fetched. Generalizes the single
  /// hardcoded `story → task/bug` case from
  /// `aion-arch/changes/live-refresh-open-ticket-detail-screen` — extend
  /// this map, not the surrounding method, if a third dependency is ever
  /// discovered. Added for
  /// `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`.
  static const Map<TicketType, Set<TicketType>> _liveRefreshDependents = {
    TicketType.story: {TicketType.task, TicketType.bug},
    TicketType.epic: {TicketType.story},
  };

  /// Re-fetches and silently re-emits [TicketDetailLoaded] for the
  /// currently open ticket detail screen when a background write may have
  /// changed data it depends on. Originally added for
  /// `aion-arch/changes/live-refresh-open-ticket-detail-screen`;
  /// generalized to a set of ids and a declarative dependency table
  /// ([_liveRefreshDependents]) by
  /// `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`.
  ///
  /// Two cases trigger a refresh, checked against every id in
  /// [writtenTicketIds] until one matches (no-ops the rest — a refresh is
  /// idempotent and only one screen can ever be open):
  /// - one of [writtenTicketIds] is the ticket currently shown
  ///   ([TicketDetailLoaded.ticket]'s `id` matches) — e.g. a passive
  ///   AI-suggestion landed for it (see [createTicket]/[updateTicket]'s
  ///   [_estimationSuggester] trigger).
  /// - the currently shown ticket's `type` is a key in
  ///   [_liveRefreshDependents], one of [writtenTicketIds]' tickets has a
  ///   `type` in that key's value set, and that ticket's `parentId`
  ///   matches the currently shown ticket's `id` — e.g. a sibling Task's
  ///   status changed via [updateTicketStatus], which may flip a Story's
  ///   [TicketDetailLoaded.canAdvanceSddStage]; or a Story's `sddStage`
  ///   advanced via [advanceSddStage], which may flip its parent Epic's.
  ///
  /// No-ops when [writtenTicketIds] is empty, no detail screen is open,
  /// or every written ticket is unrelated. Delegates to [getTicketById],
  /// which never flashes [TicketsLoading] and preserves the open
  /// ticket's already-loaded Documentation-section relations when
  /// re-entering for the same id — see that method's dartdoc.
  ///
  /// [fromState] defaults to a live read of [state] — correct for call
  /// sites that chain this onto some other async operation's completion
  /// well after their own synchronous emission (e.g. [createTicket]'s
  /// [_estimationSuggester] chain), so "is a detail screen open right
  /// now" is the right question. Call sites whose own write emits an
  /// intermediate state first ([updateTicketStatus],
  /// [updateStatusForTickets], [trashTicket], [trashTickets],
  /// [updateTicketParent], [advanceSddStage]) must instead pass the
  /// state captured *before* that emission — those emissions would
  /// otherwise have already overwritten [state] by the time this runs,
  /// permanently hiding the detail screen that was open when the call
  /// started.
  Future<void> _refreshDetailIfOpenAndAffected(
    Set<String> writtenTicketIds, {
    TicketsState? fromState,
  }) async {
    if (writtenTicketIds.isEmpty) return;
    final current = fromState ?? state;
    if (current is! TicketDetailLoaded) return;

    if (writtenTicketIds.contains(current.ticket.id)) {
      await getTicketById(current.ticket.id);
      return;
    }

    final childTypes = _liveRefreshDependents[current.ticket.type];
    if (childTypes == null) return;

    for (final id in writtenTicketIds) {
      final written = await _repository.getTicketById(id);
      if (written != null &&
          childTypes.contains(written.type) &&
          written.parentId == current.ticket.id) {
        await getTicketById(current.ticket.id);
        return;
      }
    }
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
  /// repository call throws — unless the current state is already
  /// [TicketDetailLoaded] for this exact [id], in which case the
  /// [TicketsLoading] emission is skipped (mirrors [searchTickets]'s
  /// existing no-flash-over-content-already-shown precedent, scoped
  /// per-id instead of per-list) and the refreshed [TicketDetailLoaded]
  /// carries forward that previous state's [TicketDetailLoaded.childDocs]/
  /// [TicketDetailLoaded.linkedTickets]/[TicketDetailLoaded.backlinks]/
  /// [TicketDetailLoaded.gapsAndOpenQuestions]/
  /// [TicketDetailLoaded.pendingToolProposal] unchanged, since this
  /// method's own fetch never recomputes those Documentation-section/
  /// chat-branching fields (only [loadDocumentRelations] does) and a
  /// same-id re-fetch shouldn't silently blow them away. Added for
  /// `aion-arch/changes/live-refresh-open-ticket-detail-screen`, so
  /// [_refreshDetailIfOpenAndAffected]'s silent background refresh lands
  /// invisibly instead of flickering the screen or dropping already-loaded
  /// relations — and, as a side effect, every pre-existing same-id
  /// re-fetch-via-[getTicketById] call site (e.g. [updateTicket],
  /// [changeTicketStatus], [regenerateComplexitySuggestion], the
  /// post-run coding-execution refresh, the post-stage-advance refresh)
  /// is quietly smoothed too, none of which depended on a
  /// [TicketsLoading] flash occurring. For an `epic`/`story` ticket, also fetches
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
  /// Also batch-seeds [_executionTokenTotals] for [id] (see
  /// [_seedExecutionTokenTotals]) and populates
  /// [TicketDetailLoaded.executionTokenTotal] from it. Added for
  /// `aion-arch/changes/token-cost-prediction`. Carries forward
  /// [TicketDetailLoaded.pendingSkillAttachment] unchanged from
  /// [previousDetail], mirroring [pendingToolProposal]'s own carry-forward
  /// — this method never recomputes it, only
  /// [_resolveAndFireAttachment]/[confirmPendingSkillAttachment]/
  /// [rejectPendingSkillAttachment] do. Added for
  /// `aion-arch/changes/workflow-skill-attachments`.
  Future<void> getTicketById(String id) async {
    final current = state;
    final previousDetail = current is TicketDetailLoaded && current.ticket.id == id
        ? current
        : null;
    if (previousDetail == null) {
      emit(const TicketsLoading());
    }
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
            : await _storyNeedsDesignReview(tasks);
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
        isExecuting = _inFlightExecutionIds.contains(ticket.id);
        final queueIndex = _executionQueue.indexOf(ticket.id);
        // 1-based: the first entry in the FIFO queue is "next in line"
        // (position 1) once the in-flight run finishes — nothing *in the
        // queue* is ahead of it. The in-flight run itself never reaches
        // this branch (isExecuting is checked separately above).
        executionQueuePosition = queueIndex >= 0 ? queueIndex + 1 : null;
        if (!isExecuting &&
            executionQueuePosition == null &&
            _roleOf(ticket.status) == WorkflowStatusRole.executionTrigger) {
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

      await _seedExecutionTokenTotals([ticket.id]);

      emit(
        TicketDetailLoaded(
          ticket,
          childDocs: previousDetail?.childDocs ?? const [],
          linkedTickets: previousDetail?.linkedTickets ?? const [],
          backlinks: previousDetail?.backlinks ?? const [],
          gapsAndOpenQuestions: previousDetail?.gapsAndOpenQuestions ?? const [],
          pendingToolProposal: previousDetail?.pendingToolProposal,
          pendingSkillAttachment: previousDetail?.pendingSkillAttachment,
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
          executionTokenTotal: _executionTokenTotals[ticket.id],
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

  /// Moves ticket [id] to trash via [TicketParentTrashService.trash]
  /// (which carries [TicketRepository.trashTicket]'s descendant-cascade
  /// write plus the same git-projection/rollup-recompute side effects
  /// this method used to trigger inline — see [_parentTrashService]).
  /// Context-aware on the state active before the call: if it was
  /// [TicketDetailLoaded] **for [id] itself** (the caller is
  /// `TicketDetailScreen` trashing the ticket it's showing), emits
  /// [TicketTrashed] on success so the screen navigates away; any other
  /// previous state — list/board-shaped, or [TicketDetailLoaded] for a
  /// *different* ticket (e.g. an agent trashing a Task while a human has
  /// some other ticket's detail screen open) — re-fetches (re-applying
  /// the filters [searchTickets] was last called with, requesting at
  /// least as many tickets as were already loaded) and emits
  /// [TicketsLoaded] instead, so `TicketsListScreen`/`TicketBoardView`
  /// never fall into a blank state. The id-equality check (not just "was
  /// *a* detail screen open") was added by
  /// `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`
  /// — previously this branched on [TicketDetailLoaded] alone, which
  /// mishandled the different-ticket case by navigating away from
  /// whichever detail screen happened to be open regardless of which
  /// ticket was actually trashed. Trash never fails except on a genuine
  /// unexpected repository error, which emits [TicketsError].
  ///
  /// Whenever the trashed ticket is *not* the one currently open (the
  /// list/board case, or the different-ticket-open case above), also
  /// fires a fire-and-forget [_refreshDetailIfOpenAndAffected] call so a
  /// different, already-open Story's or Epic's detail screen
  /// live-refreshes when [id] is one of its direct children. Added for
  /// `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`.
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
      await _parentTrashService.trash(id);
      if (previousState is TicketDetailLoaded && previousState.ticket.id == id) {
        emit(const TicketTrashed());
      } else {
        if (previousState is! TicketDetailLoaded) {
          final page = await _repository.searchTickets(
            query: _lastQuery,
            statuses: _lastStatuses,
            types: _lastTypes,
            priorities: _lastPriorities,
            sort: _lastSort,
            limit: max(_pageSize, currentTickets.length),
            statusSortOrder: _statusSortOrder,
          );
          emit(TicketsLoaded(page.tickets, hasMore: page.hasMore));
        }
        unawaited(
          _refreshDetailIfOpenAndAffected(
            {id},
            fromState: previousState,
          ),
        );
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
  ///
  /// Also fires a fire-and-forget [_refreshDetailIfOpenAndAffected] call
  /// for the explicitly-passed [ids] (not their cascaded descendants,
  /// same documented scope simplification as the git-projection side
  /// effect above), so a Story's or Epic's already-open detail screen
  /// live-refreshes when this bulk trash touches one of its direct
  /// children. Added for
  /// `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`.
  Future<void> trashTickets(List<String> ids) async {
    // Captured before this call's own TicketsBatchTrashing/
    // TicketsBatchTrashed emissions below overwrite `state` — see
    // _refreshDetailIfOpenAndAffected's dartdoc for why a live `state`
    // read after those emissions would never see a detail screen that
    // was open when this call started.
    final stateBeforeThisWrite = state;
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
        for (final id in ids)
          id: (await _repository.getTicketById(id))?.parentId,
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
        statusSortOrder: _statusSortOrder,
      );
      emit(
        TicketsBatchTrashed(page.tickets, trashedCount, hasMore: page.hasMore),
      );
      unawaited(
        _refreshDetailIfOpenAndAffected(
          ids.toSet(),
          fromState: stateBeforeThisWrite,
        ),
      );
    } catch (e) {
      emit(TicketsError(e.toString()));
    }
  }

  /// Sets [status] on every ticket in [ids], via
  /// [TicketRepository.updateStatusForIds] — but only for the subset that
  /// passes the same two per-ticket gates [updateTicketStatus] already
  /// enforces for a single ticket moving to an `executionTrigger`-role status: the
  /// Blocked-dependency gate ([_isTicketBlocked]) and, for Task/Bug
  /// tickets ([TicketTypeHierarchy.isExecutable]), the coding-execution
  /// gate ([_codingExecutionGateCheck]). Both gates only apply when
  /// [status] is an `executionTrigger`-role status — every other target status
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
  /// triggers), and — for a Task/Bug moving to an `executionTrigger`-role status —
  /// starts or queues its coding-execution run via
  /// [_triggerOrQueueCodingExecution], identical to [updateTicketStatus]'s
  /// own post-write side effects. Also calls [_refreshBlockedBoardState]
  /// on completion, since a written ticket may be another ticket's
  /// blocker. For every successfully-written ticket, also fires
  /// [status]'s configured [_attachmentForStatus] (if any) via
  /// [_resolveAndFireAttachment] — same hook [updateTicketStatus] gained.
  /// Added for `aion-arch/changes/workflow-skill-attachments`.
  ///
  /// Also fires a fire-and-forget [_refreshDetailIfOpenAndAffected] call,
  /// passing every successfully-written id at once, so a Story's or
  /// Epic's already-open detail screen live-refreshes when this bulk
  /// write touches one of its direct children — the bulk counterpart of
  /// [updateTicketStatus]'s own single-ticket live-refresh. The
  /// per-ticket [_attachmentForStatus] loop above is chained onto this
  /// call's completion (`.then()`, mirroring [updateTicketStatus]'s own
  /// chaining), not run alongside it, so a `gated` attachment's
  /// [TicketDetailLoaded.pendingSkillAttachment] emission is guaranteed
  /// to land after — and not be silently overwritten by —
  /// [_refreshDetailIfOpenAndAffected]'s own re-emission. Added for
  /// `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`;
  /// the chaining was a `/verify`-time fix — see that change's `tasks.md`
  /// task 3 correction note.
  Future<void> updateStatusForTickets(
    List<String> ids,
    String status,
  ) async {
    // Captured before this call's own TicketsBatchStatusUpdating/
    // TicketsBatchStatusUpdated emissions below overwrite `state` — see
    // _refreshDetailIfOpenAndAffected's dartdoc for why a live `state`
    // read after those emissions would never see a detail screen that
    // was open when this call started.
    final stateBeforeThisWrite = state;
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
      if (_roleOf(status) == WorkflowStatusRole.executionTrigger) {
        for (final id in ids) {
          final ticket = await _repository.getTicketById(id);
          if (ticket == null) continue;
          if (await _isTicketBlocked(ticket)) continue;
          if (ticket.type.isExecutable) {
            final check = await _codingExecutionGateCheck(ticket);
            if (!check.canStart) continue;
            // Mirrors _interceptTaskExecutionTrigger's own capture, for
            // cancelCodingExecution's status-revert on this batch-
            // triggered path too. Added for
            // `aion-arch/changes/parallel-work`.
            _preExecutionStatus[id] = ticket.status;
          }
          writableIds.add(id);
        }
      } else {
        writableIds.addAll(ids);
      }

      // Deferred until after this method's own final emit below — see
      // that emit's own comment for why a `gated` attachment's pending
      // emission must not land before it. Added for
      // `aion-arch/changes/workflow-skill-attachments`.
      final pendingAttachmentFires = <(Ticket, SkillAttachment)>[];
      if (writableIds.isNotEmpty) {
        await _repository.updateStatusForIds(writableIds, status);
        final attachment = _resolveStatus(status)?.id != null
            ? _attachmentForStatus(_resolveStatus(status)!.id)
            : null;
        for (final id in writableIds) {
          final updated = await _repository.getTicketById(id);
          if (updated != null) {
            unawaited(_triggerGitProjection(updated, 'status-changed'));
            if (updated.type.isExecutable &&
                _roleOf(status) == WorkflowStatusRole.executionTrigger) {
              unawaited(_triggerOrQueueCodingExecution(updated));
            }
            if (attachment != null) {
              pendingAttachmentFires.add((updated, attachment));
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
        statusSortOrder: _statusSortOrder,
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
      // The attachment-firing loop is chained *after*
      // _refreshDetailIfOpenAndAffected resolves, not run alongside it —
      // mirrors updateTicketStatus's own .then() chaining, for the same
      // reason: both are otherwise-unawaited, but a `gated` attachment's
      // own TicketDetailLoaded(pendingSkillAttachment: ...) emission must
      // be the truly final one for this write. A same-statement-order
      // "refresh call, then loop below it" is NOT equivalent to that —
      // getTicketById captures its own `previousDetail` synchronously,
      // before this method ever yields control to the loop (calling an
      // async function runs synchronously up to its own first internal
      // `await`), so an un-chained loop still races: attachment's
      // synchronous gated-branch emission (no internal `await`) lands
      // first, then refresh's later re-emission carries forward the
      // *stale*, pre-attachment `previousDetail?.pendingSkillAttachment`,
      // silently clobbering the banner the loop just set. Found during
      // `/verify` on `aion-arch/changes/generalized-live-refresh-for-all-ticket-writes`
      // — the original un-chained placement (still visible in tasks.md's
      // task 3) looked ordered correctly by statement position but wasn't.
      unawaited(
        _refreshDetailIfOpenAndAffected(
          writableIds.toSet(),
          fromState: stateBeforeThisWrite,
        ).then((_) {
          for (final (updated, attachment) in pendingAttachmentFires) {
            unawaited(_resolveAndFireAttachment(updated, attachment));
          }
        }),
      );
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
        statusSortOrder: _statusSortOrder,
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
  ///
  /// Also populates `gapsAndOpenQuestions`: every `knownGap`/
  /// `openQuestion` ticket `relatesTo`-linked to [ticketId] itself or to
  /// any descendant of it, recursively — an Epic's section shows
  /// everything raised anywhere in its subtree, however deep, each entry
  /// naming the specific subtree member ([GapOrQuestionRef.raisedOn]) it
  /// was raised on. Built from the same bulk
  /// [TicketLinkRepository.getLinksByTypes] shape
  /// `_refreshBlockedBoardState` already uses for `blocks`/`blockedBy` —
  /// one app-wide query, no N+1 across the subtree. Sorted per Component
  /// Spec §2.4: directly-raised entries (raised on [ticketId] itself)
  /// before rolled-up ones (raised on a descendant), each group ordered
  /// by descending `createdAt`. Added for
  /// `aion-arch/changes/idea-gap-question-ticket-types`; see that
  /// change's design.md §3.4.
  ///
  /// [backlinks] merges two sources into one [BacklinkRef] list, each
  /// mapped to its [BacklinkOrigin]: `TicketLink` rows where the other
  /// side is `page`/`resource` ([BacklinkOrigin.explicitLink], as
  /// before), plus — when [ticketId]'s own type is `page`/`resource`
  /// **and** this cubit was constructed with a [PageWikilinkRepository] —
  /// every page whose content resolves an inline `[[...]]` reference to
  /// [ticketId] ([BacklinkOrigin.wikilink]). A page linked via both
  /// mechanisms produces two separate rows — each represents a distinct,
  /// independently-true relationship, not deduplicated. Added for
  /// `aion-arch/changes/inline-wikilink-backlinks`.
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
    final backlinks = <BacklinkRef>[];
    final linkRepo = _linkRepository;
    if (linkRepo != null) {
      final links = await linkRepo.getLinksForTicket(ticket.id);
      for (final link in links) {
        final otherId = link.sourceTicketId == ticket.id
            ? link.targetTicketId
            : link.sourceTicketId;
        final other = await _repository.getTicketById(otherId);
        if (other == null) continue;
        if (other.type == TicketType.page ||
            other.type == TicketType.resource) {
          backlinks.add(
            BacklinkRef(ticket: other, origin: BacklinkOrigin.explicitLink),
          );
        } else {
          linkedTickets.add((
            ticket: other,
            relativeType: relativeLinkType(link, ticket.id),
            linkId: link.id,
          ));
        }
      }
    }
    final wikilinkRepo = _pageWikilinkRepository;
    if (wikilinkRepo != null &&
        (ticket.type == TicketType.page ||
            ticket.type == TicketType.resource)) {
      final incoming = await wikilinkRepo.getIncomingLinks(ticket.id);
      for (final link in incoming) {
        final source = await _repository.getTicketById(link.sourcePageId);
        if (source == null) continue;
        backlinks.add(
          BacklinkRef(ticket: source, origin: BacklinkOrigin.wikilink),
        );
      }
    }

    final gapsAndOpenQuestions = <GapOrQuestionRef>[];
    if (linkRepo != null) {
      final all = await _repository.getAllTickets();
      final byId = {for (final t in all) t.id: t};
      final subtreeIds = {ticket.id, ..._descendantIds(ticket.id, all)};
      final relatesToLinks = await linkRepo.getLinksByTypes([
        TicketLinkType.relatesTo,
      ]);
      for (final link in relatesToLinks) {
        final source = byId[link.sourceTicketId];
        final target = byId[link.targetTicketId];
        if (source == null || target == null) continue;
        // The gap/question ticket is always the `relatesTo` link's
        // *source* — createGapOrQuestion/reclassifyIdea always create it
        // that way — so only that direction is checked.
        if ((source.type == TicketType.knownGap ||
                source.type == TicketType.openQuestion) &&
            subtreeIds.contains(target.id)) {
          gapsAndOpenQuestions.add((
            ticket: source,
            raisedOn: target,
            linkId: link.id,
          ));
        }
      }
      // Component Spec §2.4: directly-raised entries (raised on `ticket`
      // itself) sort before rolled-up ones (raised on a descendant), each
      // group ordered by descending `createdAt` of the gap/question
      // ticket itself.
      gapsAndOpenQuestions.sort((a, b) {
        final aDirect = a.raisedOn.id == ticket.id;
        final bDirect = b.raisedOn.id == ticket.id;
        if (aDirect != bDirect) return aDirect ? -1 : 1;
        return b.ticket.createdAt.compareTo(a.ticket.createdAt);
      });
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
        gapsAndOpenQuestions: gapsAndOpenQuestions,
      ),
    );
  }

  /// Resolves the `knownGap`/`openQuestion` ticket [gapOrQuestionId]'s
  /// single outgoing `relatesTo` link to the target ticket it was raised
  /// on — the "Raised on" indicator's data source. `knownGap`/
  /// `openQuestion` are excluded from [loadDocumentRelations]'s gated
  /// type list (their one relationship is fixed at creation, never a
  /// generic Linked Tickets use case), so this is a narrow, standalone
  /// query rather than reusing that method's broader aggregation. Returns
  /// `null` if [gapOrQuestionId] doesn't exist, has no outgoing
  /// `relatesTo` link, or was constructed without a
  /// [TicketLinkRepository]. Added for
  /// `aion-arch/changes/idea-gap-question-ticket-types`; see that
  /// change's design.md §4.3.
  Future<Ticket?> getRaisedOnTicket(String gapOrQuestionId) async {
    final linkRepo = _linkRepository;
    if (linkRepo == null) return null;
    final links = await linkRepo.getLinksForTicket(gapOrQuestionId);
    for (final link in links) {
      if (link.sourceTicketId == gapOrQuestionId &&
          link.linkType == TicketLinkType.relatesTo.name) {
        return _repository.getTicketById(link.targetTicketId);
      }
    }
    return null;
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
  /// root `idea` ticket per finding, each linked
  /// ([TicketLinkType.relatesTo]) back to a "Codebase Analysis —
  /// `<project name>`" run-record `idea` ticket that records the scan
  /// itself (both depths get a run-record ticket, for consistent
  /// traceability; only [SummarizationDepth.full] also spawns a visible
  /// `chat` child under it, since only that depth's agentic turn has a
  /// transcript worth persisting — see [_runFullSummarization]).
  /// Every resulting `idea` ticket flows through the existing,
  /// unmodified `promoteIdea` — no automatic ticket creation beyond
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
      type: TicketType.idea,
      title: 'Codebase Analysis — ${_projectName ?? 'this project'}',
      description: depth == SummarizationDepth.shallow
          ? 'Shallow structural scan — detected stack and directory '
                'listing only, no file contents read.'
          : 'Full agentic scan — read the project\'s actual files via an '
                'isolated, read-only worktree.',
      status: _defaultCreationStatus,
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
          type: TicketType.idea,
          title: finding.title,
          description: description,
          status: _defaultCreationStatus,
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
        case AgentToolCallEvent():
          break; // This call sends no tools — never emitted, ignored defensively.
        case AgentCancelledEvent():
          break; // No `runId` is passed above — never emitted, ignored defensively.
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
      status: _defaultCreationStatus,
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
      final result = await ChatCubit.runChatTurn(
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
      // ChatTurnCancelled is unreachable here — this call passes no
      // `runId` — but is still treated the same as a failure defensively,
      // preserving today's exact bool-equivalent behavior.
      if (result is! ChatTurnSuccess) {
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
