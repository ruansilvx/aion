import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/core/database/app_database.dart';
import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/core/git/github_cli_client.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/execution_scheduling_repository.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/data/services/active_ticket_view_registry.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_sort_repository.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

class MockTicketGitProjector extends Mock implements TicketGitProjector {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockAgentProvider extends Mock implements AgentProvider {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

class MockCommentRepository extends Mock implements CommentRepository {}

class MockAutomationSettingsRepository extends Mock
    implements AutomationSettingsRepository {}

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

class MockGitRepositoryClient extends Mock implements GitRepositoryClient {}

class MockGitHubCliClient extends Mock implements GitHubCliClient {}

class MockBaselineRepository extends Mock implements BaselineRepository {}

class MockTicketListFilterRepository extends Mock
    implements TicketListFilterRepository {}

class MockTicketListSortRepository extends Mock
    implements TicketListSortRepository {}

class MockPageWikilinkRepository extends Mock implements PageWikilinkRepository {}

class MockExecutionSchedulingRepository extends Mock
    implements ExecutionSchedulingRepository {}

class MockExecutionQueueRepository extends Mock
    implements ExecutionQueueRepository {}

/// Stubs [gitClient]/[gitHubClient] for a coding-execution run that
/// isolates cleanly, pushes, and opens a PR — the happy path most
/// `_runCodingExecution` tests exercise. Whether the run actually
/// *reaches* that push/PR step now depends on the agentic verify turn's
/// reply (see [stubStatefulComments]/[stubEmptyBaseline]), not on
/// anything stubbed here. Added for `aion-arch/changes/coding-
/// execution-reliability-and-safety`; simplified for `aion-arch/
/// changes/project-type-aware-conventions-and-verification` (dropped
/// the `FlutterVerifier` stubs it used to also set up here).
void stubSuccessfulCodingExecutionInfra(
  MockGitRepositoryClient gitClient,
  MockGitHubCliClient gitHubClient,
) {
  when(
    () => gitClient.createWorktree(any(), any(), any()),
  ).thenAnswer((_) async {});
  when(() => gitClient.push(any(), any())).thenAnswer((_) async {});
  when(
    () => gitHubClient.openPullRequest(
      rootPath: any(named: 'rootPath'),
      branch: any(named: 'branch'),
      title: any(named: 'title'),
      body: any(named: 'body'),
    ),
  ).thenAnswer((_) async => 'https://example/pr/mock');
  when(() => gitClient.removeWorktree(any(), any())).thenAnswer((_) async {});
}

/// Stubs [baselineRepository] with an empty manifest for [baselineVersion]
/// — the minimal wiring `TicketsCubit._effectiveAssetContent` needs to
/// resolve every asset key to `null` (no `Project conventions` section,
/// no `skills/verify` guidance beyond the fallback sentence) without
/// throwing, for tests that don't care about that content. Added for
/// `aion-arch/changes/project-type-aware-conventions-and-verification`.
void stubEmptyBaseline(
  MockBaselineRepository baselineRepository, {
  String baselineVersion = '0.1.0',
}) {
  when(() => baselineRepository.getManifest(baselineVersion)).thenAnswer(
    (_) async => BaselineManifest(version: baselineVersion, assets: const []),
  );
}

/// A minimal append-only comment store wired into [commentRepository]'s
/// `getCommentsForTicket`/`addComment` stubs for ticket [chatId] — so
/// `TicketsCubit`'s mid-run read (the agentic verify turn reading back
/// its own reply, see `_lastCommentContent`) and its end-of-run read
/// (`_executionSucceededWithPr`) each see comments in the order
/// production code actually posts them, rather than a single static
/// snapshot frozen at "final state" (which can't represent both reads
/// correctly once there's more than one). Added for `aion-arch/
/// changes/project-type-aware-conventions-and-verification`.
void stubStatefulComments(
  MockCommentRepository commentRepository,
  String chatId,
) {
  final comments = <TicketComment>[];
  when(
    () => commentRepository.getCommentsForTicket(chatId),
  ).thenAnswer((_) async => List<TicketComment>.of(comments));
  when(() => commentRepository.addComment(any())).thenAnswer((
    invocation,
  ) async {
    final comment = invocation.positionalArguments[0] as TicketComment;
    if (comment.ticketId == chatId) comments.add(comment);
  });
}

const _sonnet = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'claude-sonnet-5',
  label: 'Sonnet 5',
  contextWindowTokens: 200000,
);
const _opus = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'claude-opus-4-8',
  label: 'Opus 4.8',
  contextWindowTokens: 200000,
);
const _haiku = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'claude-haiku-4-5',
  label: 'Haiku 4.5',
  contextWindowTokens: 200000,
);

/// Wires a [MockAgentProvider]/[MockProviderRegistry] pair around
/// [client] — [provider.client] returns [client], `normalizeErrorMessage`/
/// `describeOverage` are identity-ish pass-throughs, and
/// `availableModels` lists [_sonnet] first (so `_resolveModel`'s
/// no-[ModelRoutingRepository] fallback — `registry.availableProviders
/// .first.availableModels.first` — resolves to `_sonnet`, preserving
/// every existing test's prior `AgentModel.sonnet`-fallback assumption).
({MockAgentProvider provider, MockProviderRegistry registry})
buildProviderStack(MockAgentModelClient client) {
  final provider = MockAgentProvider();
  final registry = MockProviderRegistry();
  when(() => provider.client).thenReturn(client);
  when(
    () => provider.availableModels,
  ).thenReturn(const [_sonnet, _opus, _haiku]);
  when(
    () => provider.normalizeErrorMessage(any()),
  ).thenAnswer((invocation) => invocation.positionalArguments[0] as String);
  when(() => provider.describeOverage(any())).thenAnswer(
    (invocation) =>
        UsageWindowConsumption(invocation.positionalArguments[0] as String),
  );
  when(() => registry.availableProviders).thenReturn([provider]);
  when(
    () => registry.providerById(ProviderId.claudeAgentSdk),
  ).thenReturn(provider);
  return (provider: provider, registry: registry);
}

void main() {
  late MockTicketRepository repository;

  final ticket = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Test ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  // Multi-level hierarchy fixture: ticket (root) -> child -> grandchild,
  // plus an unrelated ticket with no parent (a valid reparent target).
  final child = Ticket(
    id: '2',
    ticketId: 'AIO-2',
    type: TicketType.task,
    title: 'Child ticket',
    status: TicketStatus.backlog,
    parentId: ticket.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final grandchild = Ticket(
    id: '3',
    ticketId: 'AIO-3',
    type: TicketType.task,
    title: 'Grandchild ticket',
    status: TicketStatus.backlog,
    parentId: child.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  // Type is story (not task, unlike the rest of this hierarchy fixture) so
  // it remains a valid reparent target for `ticket` (a task) under the
  // type-compatibility rule: story can parent task, task cannot parent task.
  final unrelated = Ticket(
    id: '4',
    ticketId: 'AIO-4',
    type: TicketType.story,
    title: 'Unrelated ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final reparented = Ticket(
    id: ticket.id,
    ticketId: ticket.ticketId,
    type: ticket.type,
    title: ticket.title,
    status: ticket.status,
    parentId: unrelated.id,
    createdAt: ticket.createdAt,
    updatedAt: ticket.updatedAt,
  );
  final cleared = Ticket(
    id: ticket.id,
    ticketId: ticket.ticketId,
    type: ticket.type,
    title: ticket.title,
    status: ticket.status,
    createdAt: ticket.createdAt,
    updatedAt: ticket.updatedAt,
  );
  final epic = Ticket(
    id: '5',
    ticketId: 'AIO-5',
    type: TicketType.epic,
    title: 'Epic ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  // Additional type-variety fixtures for type-compatibility test cases.
  final story = Ticket(
    id: '6',
    ticketId: 'AIO-6',
    type: TicketType.story,
    title: 'Story ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final resourceTicket = Ticket(
    id: '7',
    ticketId: 'AIO-7',
    type: TicketType.resource,
    title: 'Resource ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final otherTask = Ticket(
    id: '8',
    ticketId: 'AIO-8',
    type: TicketType.task,
    title: 'Another task ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final chatTicket = Ticket(
    id: '9',
    ticketId: 'AIO-9',
    type: TicketType.chat,
    title: 'Chat ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final chatReparented = Ticket(
    id: chatTicket.id,
    ticketId: chatTicket.ticketId,
    type: chatTicket.type,
    title: chatTicket.title,
    status: chatTicket.status,
    parentId: ticket.id,
    createdAt: chatTicket.createdAt,
    updatedAt: chatTicket.updatedAt,
  );
  final ideaTicket = Ticket(
    id: '10',
    ticketId: 'AIO-10',
    type: TicketType.idea,
    title: 'Idea ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final releaseTicket = Ticket(
    id: '11',
    ticketId: 'AIO-11',
    type: TicketType.release,
    title: 'Release ticket',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  // SDD-stage fixtures.
  final storyProposed = Ticket(
    id: '12',
    ticketId: 'AIO-12',
    type: TicketType.story,
    title: 'Proposed story',
    status: TicketStatus.backlog,
    sddStage: SddStage.proposed,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final taskChildDone = Ticket(
    id: '13',
    ticketId: 'AIO-13',
    type: TicketType.task,
    title: 'Done task child',
    status: TicketStatus.done,
    parentId: storyProposed.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final taskChildNotDone = Ticket(
    id: '14',
    ticketId: 'AIO-14',
    type: TicketType.task,
    title: 'In-progress task child',
    status: TicketStatus.inProgress,
    parentId: storyProposed.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final dummyChatTicket = Ticket(
    id: 'dummy-chat',
    ticketId: 'AIO-99',
    type: TicketType.chat,
    title: 'Spawned chat',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  // sdd-design-gate fixtures.
  final taskChildUi = Ticket(
    id: '15',
    ticketId: 'AIO-15',
    type: TicketType.task,
    title: 'Redesign the ticket filter widget',
    status: TicketStatus.done,
    parentId: storyProposed.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final storyDesignBrief = Ticket(
    id: '16',
    ticketId: 'AIO-16',
    type: TicketType.story,
    title: 'Design-briefed story',
    status: TicketStatus.backlog,
    sddStage: SddStage.designBrief,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final storyDesignSync = Ticket(
    id: '17',
    ticketId: 'AIO-17',
    type: TicketType.story,
    title: 'Design-synced story',
    status: TicketStatus.backlog,
    sddStage: SddStage.designSync,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final designPageEmpty = Ticket(
    id: '18',
    ticketId: 'AIO-18',
    type: TicketType.page,
    title: 'Design — Design-briefed story',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final designPageFilled = Ticket(
    id: '19',
    ticketId: 'AIO-19',
    type: TicketType.page,
    title: 'Design — Design-synced story',
    description: 'Pasted Claude Design export.',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final designSyncChat = Ticket(
    id: '20',
    ticketId: 'AIO-20',
    type: TicketType.chat,
    title: 'Design Sync — Design-synced story',
    status: TicketStatus.backlog,
    parentId: storyDesignSync.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  // task-to-coding-execution-trigger fixtures.
  final taskNoStory = Ticket(
    id: '21',
    ticketId: 'AIO-21',
    type: TicketType.task,
    title: 'Task with no governing Story',
    status: TicketStatus.todo,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final storyForExecution = Ticket(
    id: '22',
    ticketId: 'AIO-22',
    type: TicketType.story,
    title: 'Story governing a Task execution',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final taskUnderStory = Ticket(
    id: '23',
    ticketId: 'AIO-23',
    type: TicketType.task,
    title: 'Redesign the ticket filter widget',
    status: TicketStatus.todo,
    parentId: storyForExecution.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final designSyncChatForExecution = Ticket(
    id: '24',
    ticketId: 'AIO-24',
    type: TicketType.chat,
    title: 'Design Sync — Story governing a Task execution',
    status: TicketStatus.backlog,
    parentId: storyForExecution.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final dummyExecutionChatTicket = Ticket(
    id: 'dummy-exec-chat',
    ticketId: 'AIO-97',
    type: TicketType.chat,
    title: 'Coding Execution — ${taskUnderStory.title}',
    status: TicketStatus.backlog,
    parentId: taskUnderStory.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  // A Story whose Tasks carry none of _storyNeedsDesignReview's keywords
  // ("widget"/"screen"/"component"/"ui") — the gate must skip the
  // design-approval check entirely for a Task under it.
  final storyNoDesignNeeded = Ticket(
    id: '25',
    ticketId: 'AIO-25',
    type: TicketType.story,
    title: 'Story with no UI-indicating Tasks',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final taskUnderStoryNoDesign = Ticket(
    id: '26',
    ticketId: 'AIO-26',
    type: TicketType.task,
    title: 'Refactor the sync engine retry backoff',
    status: TicketStatus.todo,
    parentId: storyNoDesignNeeded.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  // A Task parented directly under an Epic (ad hoc, no governing Story) —
  // _governingStory must stop walking at the Epic and return null.
  final taskUnderEpic = Ticket(
    id: '27',
    ticketId: 'AIO-27',
    type: TicketType.task,
    title: 'Ad hoc task filed straight under the Epic',
    status: TicketStatus.todo,
    parentId: epic.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  // bug-ticket-type fixtures: execution parity between Task and Bug.
  final bugNoStory = Ticket(
    id: '28',
    ticketId: 'AIO-28',
    type: TicketType.bug,
    title: 'Bug with no governing Story',
    status: TicketStatus.todo,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final bugUnderStory = Ticket(
    id: '29',
    ticketId: 'AIO-29',
    type: TicketType.bug,
    title: 'Redesign the ticket filter widget',
    status: TicketStatus.todo,
    parentId: storyForExecution.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(ticket);
    registerFallbackValue(TicketStatus.backlog);
    registerFallbackValue(TicketPriority.none);
    registerFallbackValue(const TicketListFilters());
    registerFallbackValue(
      const TicketListSort(
        field: TicketSortField.createdAt,
        direction: TicketSortDirection.descending,
      ),
    );
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const AgentRequest(prompt: '', model: ''));
    registerFallbackValue(SddStage.exploring);
    registerFallbackValue(<TicketType>[]);
    registerFallbackValue(<String>{});
    registerFallbackValue(
      TicketComment(
        id: '',
        ticketId: '',
        content: '',
        authorType: CommentAuthorType.system,
        createdAt: DateTime(2026),
      ),
    );
  });

  setUp(() {
    repository = MockTicketRepository();
    // Default for TicketContextEnricher's bulk read (see
    // _assembleExecutionContext/_assembleStageContext) — empty means no
    // ancestor/link/similarity matches, so `## Related tickets` never
    // appears unless a test overrides this with its own tickets. Keeps
    // every pre-existing test's assertions about today's exact prompt
    // output correct without each one having to know about the walk.
    when(() => repository.getAllTickets()).thenAnswer((_) async => []);
    // Default for _seedExecutionTokenTotals, called by searchTickets/
    // loadMoreTickets/getTicketById on every page/ticket load — empty
    // means no ticket has any recorded execution spend, so
    // TicketsLoaded.executionTokenTotals/TicketDetailLoaded
    // .executionTokenTotal stay at their own defaults unless a test
    // overrides this with its own totals. Added for
    // `aion-arch/changes/token-cost-prediction`.
    when(
      () => repository.getExecutionTokenTotals(any()),
    ).thenAnswer((_) async => {});
  });

  group('TicketsCubit', () {
    blocTest<TicketsCubit, TicketsState>(
      'searchTickets from TicketsInitial emits [TicketsLoading, TicketsLoaded] on success',
      setUp: () {
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async => TicketSearchPage(tickets: [ticket], hasMore: false),
        );
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.searchTickets(),
      expect: () => [
        const TicketsLoading(),
        TicketsLoaded([ticket], hasMore: false),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'searchTickets from TicketsInitial emits [TicketsLoading, TicketsError] on exception',
      setUp: () {
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.searchTickets(),
      expect: () => [const TicketsLoading(), isA<TicketsError>()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'searchTickets with a list already visible emits only [TicketsLoaded] '
      '(no intervening TicketsLoading)',
      setUp: () {
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async => TicketSearchPage(tickets: [ticket], hasMore: false),
        );
      },
      build: () => TicketsCubit(repository),
      seed: () => const TicketsLoaded([], hasMore: false),
      act: (cubit) => cubit.searchTickets(query: 'test'),
      expect: () => [
        TicketsLoaded([ticket], hasMore: false),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'createTicket emits [TicketCreating, TicketCreated] on success',
      setUp: () {
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => ticket);
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async => TicketSearchPage(tickets: [ticket], hasMore: false),
        );
      },
      build: () => TicketsCubit(repository),
      act: (cubit) =>
          cubit.createTicket(type: TicketType.task, title: 'New ticket'),
      expect: () => [
        const TicketCreating([]),
        TicketCreated([ticket], hasMore: false),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'createTicket emits [TicketCreating, TicketsError] on exception',
      setUp: () {
        when(() => repository.createTicket(any())).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      // createTicket now returns Future<Ticket> and rethrows after
      // emitting TicketsError (see tickets_cubit.dart), so
      // PageTicketProviderImpl.createPage can propagate a failure to
      // PagesCubit — swallow the rethrow here, only the emitted states
      // matter for this test.
      act: (cubit) async {
        try {
          await cubit.createTicket(type: TicketType.task, title: 'New ticket');
        } catch (_) {}
      },
      expect: () => [const TicketCreating([]), isA<TicketsError>()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicketStatus emits [TicketStatusUpdating, TicketStatusUpdated] on success',
      setUp: () {
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => ticket.copyWith(status: TicketStatus.done));
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async => TicketSearchPage(
            tickets: [ticket.copyWith(status: TicketStatus.done)],
            hasMore: false,
          ),
        );
      },
      build: () => TicketsCubit(repository),
      seed: () => TicketsLoaded([ticket], hasMore: false),
      act: (cubit) => cubit.updateTicketStatus(ticket.id, TicketStatus.done),
      expect: () => [
        TicketStatusUpdating([ticket.copyWith(status: TicketStatus.done)]),
        TicketStatusUpdated([
          ticket.copyWith(status: TicketStatus.done),
        ], hasMore: false),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicketStatus emits [TicketStatusUpdating, TicketsError] on exception',
      setUp: () {
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      seed: () => TicketsLoaded([ticket], hasMore: false),
      act: (cubit) => cubit.updateTicketStatus(ticket.id, TicketStatus.done),
      expect: () => [
        TicketStatusUpdating([ticket.copyWith(status: TicketStatus.done)]),
        isA<TicketsError>(),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicket emits [TicketDetailLoaded] with the refreshed ticket on success',
      setUp: () {
        when(() => repository.updateTicket(any())).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket.copyWith(title: 'Updated title'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) =>
          cubit.updateTicket(ticket.copyWith(title: 'Updated title')),
      expect: () => [
        TicketDetailLoaded(ticket.copyWith(title: 'Updated title')),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicket emits [TicketsError] when the repository throws',
      setUp: () {
        when(() => repository.updateTicket(any())).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      // updateTicket now returns Future<Ticket> and rethrows after
      // emitting TicketsError (see tickets_cubit.dart) — swallow the
      // rethrow here, only the emitted states matter for this test.
      act: (cubit) async {
        try {
          await cubit.updateTicket(ticket);
        } catch (_) {}
      },
      expect: () => [isA<TicketsError>()],
    );

    group('updateTicket complexityEdited/estimateEdited threading', () {
      test('a plain call (neither flag set) calls '
          'repository.updateTicket(ticket) with no named args, preserving '
          'the existing call shape', () async {
        when(() => repository.updateTicket(any())).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
        final cubit = TicketsCubit(repository);

        await cubit.updateTicket(ticket.copyWith(title: 'New title'));

        final captured = verify(
          () => repository.updateTicket(captureAny()),
        ).captured;
        expect(captured, hasLength(1));
        await cubit.close();
      });

      test(
        'complexityEdited: true is forwarded to the repository call',
        () async {
          when(
            () => repository.updateTicket(
              any(),
              complexityEdited: any(named: 'complexityEdited'),
              estimateEdited: any(named: 'estimateEdited'),
            ),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
          final cubit = TicketsCubit(repository);

          await cubit.updateTicket(
            ticket.copyWith(complexity: () => TicketComplexity.large),
            complexityEdited: true,
          );

          verify(
            () => repository.updateTicket(
              any(),
              complexityEdited: true,
              estimateEdited: false,
            ),
          ).called(1);
          await cubit.close();
        },
      );

      test(
        'estimateEdited: true is forwarded to the repository call',
        () async {
          when(
            () => repository.updateTicket(
              any(),
              complexityEdited: any(named: 'complexityEdited'),
              estimateEdited: any(named: 'estimateEdited'),
            ),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
          final cubit = TicketsCubit(repository);

          await cubit.updateTicket(
            ticket.copyWith(estimate: () => 90),
            estimateEdited: true,
          );

          verify(
            () => repository.updateTicket(
              any(),
              complexityEdited: false,
              estimateEdited: true,
            ),
          ).called(1);
          await cubit.close();
        },
      );
    });

    group('updateTicket wikilink reindex/rename-cascade', () {
      late MockPageWikilinkRepository wikilinkRepository;
      late ActiveTicketViewRegistry activeTicketViewRegistry;

      final pageA = Ticket(
        id: 'page-a',
        ticketId: 'AIO-100',
        type: TicketType.page,
        title: 'Page A',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      // Two live pages sharing the exact same title, distinguished by
      // createdAt — the duplicate-title case a bare-title `[[Page B]]`
      // reference resolves via first-match, while `[[AIO-102]]` resolves
      // unambiguously via ticketId regardless of the collision.
      final pageB = Ticket(
        id: 'page-b',
        ticketId: 'AIO-101',
        type: TicketType.page,
        title: 'Page B',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
      );
      final pageBDuplicateTitle = Ticket(
        id: 'page-b2',
        ticketId: 'AIO-102',
        type: TicketType.page,
        title: 'Page B',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026, 1, 3),
        updatedAt: DateTime(2026, 1, 3),
      );

      setUp(() {
        wikilinkRepository = MockPageWikilinkRepository();
        activeTicketViewRegistry = ActiveTicketViewRegistry();
        when(
          () => wikilinkRepository.replaceOutgoingLinks(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => wikilinkRepository.getIncomingLinks(any()),
        ).thenAnswer((_) async => []);
      });

      TicketsCubit buildCubit() => TicketsCubit(
        repository,
        pageWikilinkRepository: wikilinkRepository,
        activeTicketViewRegistry: activeTicketViewRegistry,
      );

      test(
        'reindexes outgoing links against a widened page/resource candidate '
        'set, resolving a bare-title and a bare-ticketId reference in the '
        'same content',
        () async {
          final edited = pageA.copyWith(
            description: () => 'See [[Page B]] and [[AIO-102]].',
          );
          var callCount = 0;
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(() => repository.getTicketById(pageA.id)).thenAnswer((_) async {
            callCount++;
            // previous (call 1) is the pre-edit ticket, with no description
            // yet — refreshed (call 2) is the edited one — updateTicket's
            // own before/after reads. The reindex is gated on
            // description actually changing, so the two calls must differ.
            return callCount == 1 ? pageA : edited;
          });
          when(
            () => repository.getAllTicketsByType([
              TicketType.page,
              TicketType.resource,
            ]),
          ).thenAnswer((_) async => [pageA, pageB, pageBDuplicateTitle]);
          final cubit = buildCubit();

          await cubit.updateTicket(edited);
          await Future<void>.delayed(Duration.zero);

          verify(
            () => wikilinkRepository.replaceOutgoingLinks(edited.id, {
              pageB.id,
              pageBDuplicateTitle.id,
            }),
          ).called(1);
          await cubit.close();
        },
      );

      test(
        'no-ops entirely when pageWikilinkRepository is null',
        () async {
          final edited = pageA.copyWith(
            description: () => 'See [[Page B]].',
          );
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(pageA.id),
          ).thenAnswer((_) async => edited);
          final cubit = TicketsCubit(repository); // no pageWikilinkRepository

          await cubit.updateTicket(edited);
          await Future<void>.delayed(Duration.zero);

          verifyNever(
            () => repository.getAllTicketsByType([
              TicketType.page,
              TicketType.resource,
            ]),
          );
          await cubit.close();
        },
      );

      test(
        'no-ops when neither title nor description changed — same content '
        'gate the embedding-regen trigger uses, per design.md',
        () async {
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(pageA.id),
          ).thenAnswer((_) async => pageA);
          final cubit = buildCubit();

          // Only a field the wikilink reindex has no business touching
          // (title/description both unchanged from the stored ticket).
          await cubit.updateTicket(pageA);
          await Future<void>.delayed(Duration.zero);

          verifyNever(
            () => repository.getAllTicketsByType([
              TicketType.page,
              TicketType.resource,
            ]),
          );
          verifyNever(() => wikilinkRepository.replaceOutgoingLinks(any(), any()));
          await cubit.close();
        },
      );

      test(
        'rename triggers getIncomingLinks and rewrites a referrer whose '
        'content has a title-anchored occurrence, recursing through '
        'updateTicket',
        () async {
          final referrer = Ticket(
            id: 'referrer-1',
            ticketId: 'AIO-200',
            type: TicketType.page,
            title: 'Referrer',
            description: 'Links to [[Page A]] and [[AIO-100|alias]].',
            status: TicketStatus.backlog,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          );
          final renamed = pageA.copyWith(title: 'Page A Renamed');

          var callCount = 0;
          when(() => repository.getTicketById(pageA.id)).thenAnswer((_) async {
            callCount++;
            // previous (call 1) is the pre-rename ticket; refreshed (call
            // 2) is the renamed one — updateTicket's own before/after reads.
            return callCount == 1 ? pageA : renamed;
          });
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getAllTicketsByType([
              TicketType.page,
              TicketType.resource,
            ]),
          ).thenAnswer((_) async => [renamed]);
          when(
            () => wikilinkRepository.getIncomingLinks(pageA.id),
          ).thenAnswer(
            (_) async => [
              PageWikilink(
                id: 'wl-1',
                sourcePageId: referrer.id,
                targetPageId: pageA.id,
                createdAt: DateTime(2026, 1, 1),
              ),
            ],
          );
          when(
            () => repository.getTicketById(referrer.id),
          ).thenAnswer((_) async => referrer);
          final cubit = buildCubit();

          await cubit.updateTicket(renamed);
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);

          // Only the title-anchored `[[Page A]]` occurrence is rewritten —
          // the id-anchored `[[AIO-100|alias]]` occurrence's target is
          // never a title, so it's left untouched even though its own
          // alias is irrelevant here.
          final captured = verify(
            () => repository.updateTicket(captureAny()),
          ).captured;
          final referrerUpdate = captured.cast<Ticket>().firstWhere(
            (t) => t.id == referrer.id,
          );
          expect(
            referrerUpdate.description,
            'Links to [[Page A Renamed]] and [[AIO-100|alias]].',
          );
          await cubit.close();
        },
      );

      test(
        'skips a referrer whose content does not actually contain the old '
        'title (no redundant recursive update)',
        () async {
          final referrer = Ticket(
            id: 'referrer-2',
            ticketId: 'AIO-201',
            type: TicketType.page,
            title: 'Referrer',
            description: 'Links via [[AIO-100]] only.',
            status: TicketStatus.backlog,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          );
          final renamed = pageA.copyWith(title: 'Page A Renamed');

          var callCount = 0;
          when(() => repository.getTicketById(pageA.id)).thenAnswer((_) async {
            callCount++;
            return callCount == 1 ? pageA : renamed;
          });
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getAllTicketsByType([
              TicketType.page,
              TicketType.resource,
            ]),
          ).thenAnswer((_) async => [renamed]);
          when(
            () => wikilinkRepository.getIncomingLinks(pageA.id),
          ).thenAnswer(
            (_) async => [
              PageWikilink(
                id: 'wl-1',
                sourcePageId: referrer.id,
                targetPageId: pageA.id,
                createdAt: DateTime(2026, 1, 1),
              ),
            ],
          );
          when(
            () => repository.getTicketById(referrer.id),
          ).thenAnswer((_) async => referrer);
          final cubit = buildCubit();

          await cubit.updateTicket(renamed);
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);

          // The only updateTicket call captured is the primary rename
          // itself — no second call for the referrer, since its content
          // has no title-anchored occurrence of the old title.
          final captured = verify(
            () => repository.updateTicket(captureAny()),
          ).captured;
          expect(captured.cast<Ticket>().map((t) => t.id), [renamed.id]);
          await cubit.close();
        },
      );

      test(
        'defers rewriting a referrer the user currently has open, then '
        'rewrites it once activeTicketId changes away',
        () async {
          final referrer = Ticket(
            id: 'referrer-3',
            ticketId: 'AIO-202',
            type: TicketType.page,
            title: 'Referrer',
            description: 'Links to [[Page A]].',
            status: TicketStatus.backlog,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          );
          final renamed = pageA.copyWith(title: 'Page A Renamed');

          var callCount = 0;
          when(() => repository.getTicketById(pageA.id)).thenAnswer((_) async {
            callCount++;
            return callCount == 1 ? pageA : renamed;
          });
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getAllTicketsByType([
              TicketType.page,
              TicketType.resource,
            ]),
          ).thenAnswer((_) async => [renamed]);
          when(
            () => wikilinkRepository.getIncomingLinks(pageA.id),
          ).thenAnswer(
            (_) async => [
              PageWikilink(
                id: 'wl-1',
                sourcePageId: referrer.id,
                targetPageId: pageA.id,
                createdAt: DateTime(2026, 1, 1),
              ),
            ],
          );
          when(
            () => repository.getTicketById(referrer.id),
          ).thenAnswer((_) async => referrer);
          activeTicketViewRegistry.activeTicketId.value = referrer.ticketId;
          final cubit = buildCubit();

          await cubit.updateTicket(renamed);
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);

          // Deferred — no rewrite yet while the referrer is the active view.
          verifyNever(
            () => repository.updateTicket(
              any(that: predicate<Ticket>((t) => t.id == referrer.id)),
            ),
          );

          activeTicketViewRegistry.activeTicketId.value = null;
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);

          final captured = verify(
            () => repository.updateTicket(captureAny()),
          ).captured;
          final referrerUpdate = captured
              .cast<Ticket>()
              .where((t) => t.id == referrer.id);
          expect(referrerUpdate, hasLength(1));
          expect(referrerUpdate.single.description, 'Links to [[Page A Renamed]].');
          await cubit.close();
        },
      );

      test(
        'a thrown error from the wikilink step does not affect the primary '
        'update\'s emitted state',
        () async {
          final edited = pageA.copyWith(description: () => 'See [[Page B]].');
          var callCount = 0;
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(() => repository.getTicketById(pageA.id)).thenAnswer((_) async {
            callCount++;
            // The reindex step only fires when description actually
            // changed, so the pre-write (previous) read must differ from
            // the post-write (refreshed) one for this test to genuinely
            // exercise the swallowed-throw path.
            return callCount == 1 ? pageA : edited;
          });
          when(
            () => repository.getAllTicketsByType([
              TicketType.page,
              TicketType.resource,
            ]),
          ).thenThrow(Exception('boom'));
          final cubit = buildCubit();
          final states = <TicketsState>[];
          final sub = cubit.stream.listen(states.add);

          final result = await cubit.updateTicket(edited);
          await Future<void>.delayed(Duration.zero);

          expect(result, edited);
          expect(states, [TicketDetailLoaded(edited)]);
          await sub.cancel();
          await cubit.close();
        },
      );
    });

    blocTest<TicketsCubit, TicketsState>(
      'changeTicketStatus emits [TicketDetailLoaded] with the refreshed ticket on success',
      setUp: () {
        when(
          () => repository.updateTicketStatus(ticket.id, TicketStatus.done),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket.copyWith(status: TicketStatus.done));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.changeTicketStatus(ticket, TicketStatus.done),
      expect: () => [
        TicketDetailLoaded(ticket.copyWith(status: TicketStatus.done)),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'changeTicketStatus emits [TicketsError] when the repository throws',
      setUp: () {
        when(
          () => repository.updateTicketStatus(ticket.id, TicketStatus.done),
        ).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.changeTicketStatus(ticket, TicketStatus.done),
      verify: (_) {
        verifyNever(() => repository.getTicketById(any()));
      },
      expect: () => [isA<TicketsError>()],
    );

    group('previewTrashCount', () {
      test('delegates to TicketRepository.previewTrashCount and returns '
          'its result', () async {
        when(
          () => repository.previewTrashCount([ticket.id]),
        ).thenAnswer((_) async => 3);

        final total = await TicketsCubit(
          repository,
        ).previewTrashCount([ticket.id]);

        expect(total, 3);
        verify(() => repository.previewTrashCount([ticket.id])).called(1);
      });

      test(
        'returns whatever count the repository reports, unmodified',
        () async {
          when(
            () => repository.previewTrashCount([ticket.id, unrelated.id]),
          ).thenAnswer((_) async => 1);

          final total = await TicketsCubit(
            repository,
          ).previewTrashCount([ticket.id, unrelated.id]);

          expect(total, 1);
        },
      );
    });

    blocTest<TicketsCubit, TicketsState>(
      'trashTicket from a TicketDetailLoaded previous state emits '
      '[TicketTrashing, TicketTrashed] on success',
      setUp: () {
        when(() => repository.trashTicket(ticket.id)).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
      },
      build: () => TicketsCubit(repository),
      seed: () => TicketDetailLoaded(ticket),
      act: (cubit) => cubit.trashTicket(ticket.id),
      expect: () => [const TicketTrashing(), const TicketTrashed()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'trashTicket emits [TicketTrashing, TicketsError] on a generic failure',
      setUp: () {
        when(
          () => repository.trashTicket(ticket.id),
        ).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      seed: () => TicketDetailLoaded(ticket),
      act: (cubit) => cubit.trashTicket(ticket.id),
      expect: () => [const TicketTrashing(), isA<TicketsError>()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'trashTicket from a TicketsLoaded previous state emits '
      '[TicketTrashing, TicketsLoaded] with the refreshed list on success',
      setUp: () {
        when(() => repository.trashTicket(ticket.id)).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async => const TicketSearchPage(tickets: [], hasMore: false),
        );
      },
      build: () => TicketsCubit(repository),
      seed: () => TicketsLoaded([ticket], hasMore: false),
      act: (cubit) => cubit.trashTicket(ticket.id),
      expect: () => [
        const TicketTrashing(),
        const TicketsLoaded([], hasMore: false),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'trashTickets emits [TicketsBatchTrashing, TicketsBatchTrashed] '
      'carrying the refreshed list and trashed count on success',
      setUp: () {
        when(
          () => repository.trashTickets([ticket.id]),
        ).thenAnswer((_) async => 1);
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async => const TicketSearchPage(tickets: [], hasMore: false),
        );
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.trashTickets([ticket.id]),
      expect: () => [
        const TicketsBatchTrashing(),
        const TicketsBatchTrashed([], 1, hasMore: false),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'trashTickets emits [TicketsBatchTrashing, TicketsError] on a '
      'generic failure',
      setUp: () {
        when(() => repository.trashTickets(any())).thenThrow(Exception('boom'));
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.trashTickets([ticket.id]),
      expect: () => [const TicketsBatchTrashing(), isA<TicketsError>()],
    );

    group('updateStatusForTickets / updatePriorityForTickets '
        '(bulk-status-and-priority-edit-for-ticket-selection)', () {
      late MockTicketLinkRepository linkRepository;
      late MockCommentRepository commentRepository;
      late MockTicketGitProjector gitProjector;
      const rootPath = '/root';

      // Rejected by the Blocked-dependency gate (_isTicketBlocked) — has
      // an unresolved blockedBy link.
      final bulkBlockedTask = Ticket(
        id: 'bulk-blocked-1',
        ticketId: 'AIO-90',
        type: TicketType.task,
        title: 'Blocked bulk task',
        status: TicketStatus.todo,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final bulkBlockerTask = Ticket(
        id: 'bulk-blocker-1',
        ticketId: 'AIO-91',
        type: TicketType.task,
        title: 'Blocker task',
        status: TicketStatus.todo,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      // Not blocked, but rejected by the coding-execution gate — reuses
      // the existing task-to-coding-execution-trigger fixtures (a Task
      // under a Story whose design review is still PENDING).
      final bulkCodingGatedTask = taskUnderStory;
      // Passes both gates — no governing Story, no blockedBy link.
      final bulkCleanTask = Ticket(
        id: 'bulk-clean-1',
        ticketId: 'AIO-92',
        type: TicketType.task,
        title: 'Clean bulk task',
        status: TicketStatus.inProgress,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      setUp(() {
        linkRepository = MockTicketLinkRepository();
        commentRepository = MockCommentRepository();
        gitProjector = MockTicketGitProjector();
      });

      TicketsCubit buildCubit() => TicketsCubit(
        repository,
        linkRepository: linkRepository,
        commentRepository: commentRepository,
        gitProjector: gitProjector,
        projectRootPath: rootPath,
      );

      void stubEmptySearch() {
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => const TicketSearchPage(tickets: [], hasMore: false),
        );
      }

      /// Stubs the three-way mixed selection (blocked / coding-execution
      /// -gated / clean) so only [bulkCleanTask] is writable.
      void stubMixedSelection() {
        when(
          () => repository.getTicketById(bulkBlockedTask.id),
        ).thenAnswer((_) async => bulkBlockedTask);
        when(
          () => linkRepository.getLinksForTicket(bulkBlockedTask.id),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'bulk-gate-link-1',
              sourceTicketId: bulkBlockedTask.id,
              targetTicketId: bulkBlockerTask.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(
          () => repository.getTicketById(bulkBlockerTask.id),
        ).thenAnswer((_) async => bulkBlockerTask);

        when(
          () => repository.getTicketById(bulkCodingGatedTask.id),
        ).thenAnswer((_) async => bulkCodingGatedTask);
        when(
          () => linkRepository.getLinksForTicket(bulkCodingGatedTask.id),
        ).thenAnswer((_) async => []);
        when(
          () => repository.getTicketById(storyForExecution.id),
        ).thenAnswer((_) async => storyForExecution);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [bulkCodingGatedTask]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'bulk-comment-1',
              ticketId: designSyncChatForExecution.id,
              content: 'Found one issue.\n\nDESIGN GATE: PENDING',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );

        when(
          () => repository.getTicketById(bulkCleanTask.id),
        ).thenAnswer((_) async => bulkCleanTask);
        when(
          () => linkRepository.getLinksForTicket(bulkCleanTask.id),
        ).thenAnswer((_) async => []);
        when(
          () => repository.updateStatusForIds([
            bulkCleanTask.id,
          ], TicketStatus.inProgress),
        ).thenAnswer((_) async {});
        when(
          () => gitProjector.project(any(), any(), any()),
        ).thenAnswer((_) async {});
        stubEmptySearch();
      }

      blocTest<TicketsCubit, TicketsState>(
        'target inProgress with a mixed selection emits '
        '[TicketsBatchStatusUpdating, TicketsBatchStatusUpdated] with the '
        'correct updated/skipped split, and only the writable id reaches '
        'updateStatusForIds',
        setUp: stubMixedSelection,
        build: buildCubit,
        act: (cubit) => cubit.updateStatusForTickets([
          bulkBlockedTask.id,
          bulkCodingGatedTask.id,
          bulkCleanTask.id,
        ], TicketStatus.inProgress),
        verify: (_) {
          verify(
            () => repository.updateStatusForIds([
              bulkCleanTask.id,
            ], TicketStatus.inProgress),
          ).called(1);
        },
        expect: () => [
          const TicketsBatchStatusUpdating(),
          const TicketsBatchStatusUpdated([], 1, 2, hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'git-projection fires only for the successfully-written ticket, '
        'never for the blocked or coding-execution-gated ones',
        setUp: stubMixedSelection,
        build: buildCubit,
        act: (cubit) => cubit.updateStatusForTickets([
          bulkBlockedTask.id,
          bulkCodingGatedTask.id,
          bulkCleanTask.id,
        ], TicketStatus.inProgress),
        verify: (_) {
          verify(
            () =>
                gitProjector.project(bulkCleanTask, rootPath, 'status-changed'),
          ).called(1);
          verifyNever(
            () => gitProjector.project(bulkBlockedTask, any(), any()),
          );
          verifyNever(
            () => gitProjector.project(bulkCodingGatedTask, any(), any()),
          );
        },
        expect: () => [
          const TicketsBatchStatusUpdating(),
          const TicketsBatchStatusUpdated([], 1, 2, hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'a target status other than inProgress skips gating entirely — '
        'skippedCount is always 0 and no link data is queried',
        setUp: () {
          when(() => repository.getTicketById(bulkBlockedTask.id)).thenAnswer(
            (_) async => bulkBlockedTask.copyWith(status: TicketStatus.done),
          );
          when(
            () => repository.updateStatusForIds([
              bulkBlockedTask.id,
            ], TicketStatus.done),
          ).thenAnswer((_) async {});
          when(
            () => gitProjector.project(any(), any(), any()),
          ).thenAnswer((_) async {});
          stubEmptySearch();
        },
        build: buildCubit,
        act: (cubit) => cubit.updateStatusForTickets([
          bulkBlockedTask.id,
        ], TicketStatus.done),
        verify: (_) {
          verifyNever(() => linkRepository.getLinksForTicket(any()));
          verify(
            () => repository.updateStatusForIds([
              bulkBlockedTask.id,
            ], TicketStatus.done),
          ).called(1);
        },
        expect: () => [
          const TicketsBatchStatusUpdating(),
          const TicketsBatchStatusUpdated([], 1, 0, hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateStatusForTickets emits [TicketsBatchStatusUpdating, '
        'TicketsError] when the repository throws',
        setUp: () {
          when(
            () => repository.updateStatusForIds(any(), any()),
          ).thenThrow(Exception('boom'));
        },
        build: () => TicketsCubit(repository),
        act: (cubit) =>
            cubit.updateStatusForTickets([ticket.id], TicketStatus.done),
        expect: () => [const TicketsBatchStatusUpdating(), isA<TicketsError>()],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updatePriorityForTickets always writes unconditionally — '
        'updatedCount equals ids.length and no git projection is '
        'triggered',
        setUp: () {
          when(
            () => repository.updatePriorityForIds([
              ticket.id,
              unrelated.id,
            ], TicketPriority.critical),
          ).thenAnswer((_) async {});
          when(
            () => gitProjector.project(any(), any(), any()),
          ).thenAnswer((_) async {});
          stubEmptySearch();
        },
        build: buildCubit,
        act: (cubit) => cubit.updatePriorityForTickets([
          ticket.id,
          unrelated.id,
        ], TicketPriority.critical),
        verify: (_) {
          verify(
            () => repository.updatePriorityForIds([
              ticket.id,
              unrelated.id,
            ], TicketPriority.critical),
          ).called(1);
          verifyNever(() => gitProjector.project(any(), any(), any()));
        },
        expect: () => [
          const TicketsBatchPriorityUpdating(),
          const TicketsBatchPriorityUpdated([], 2, hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updatePriorityForTickets emits [TicketsBatchPriorityUpdating, '
        'TicketsError] when the repository throws',
        setUp: () {
          when(
            () => repository.updatePriorityForIds(any(), any()),
          ).thenThrow(Exception('boom'));
        },
        build: () => TicketsCubit(repository),
        act: (cubit) =>
            cubit.updatePriorityForTickets([ticket.id], TicketPriority.low),
        expect: () => [
          const TicketsBatchPriorityUpdating(),
          isA<TicketsError>(),
        ],
      );
    });

    group('loadMoreTickets', () {
      blocTest<TicketsCubit, TicketsState>(
        'appends the next page and emits TicketsLoaded with the combined list',
        setUp: () {
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer(
            (_) async => TicketSearchPage(tickets: [child], hasMore: false),
          );
        },
        build: () => TicketsCubit(repository),
        seed: () => TicketsLoaded([ticket], hasMore: true),
        act: (cubit) => cubit.loadMoreTickets(),
        verify: (_) {
          verify(
            () => repository.searchTickets(
              query: null,
              statuses: const {},
              types: const {},
              priorities: const {},
              sort: const TicketListSort(
                field: TicketSortField.createdAt,
                direction: TicketSortDirection.descending,
              ),
              limit: 50,
              offset: 1,
            ),
          ).called(1);
        },
        expect: () => [
          TicketsLoadingMore([ticket]),
          TicketsLoaded([ticket, child], hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'no-ops when hasMore is false',
        build: () => TicketsCubit(repository),
        seed: () => TicketsLoaded([ticket], hasMore: false),
        act: (cubit) => cubit.loadMoreTickets(),
        verify: (_) {
          verifyNever(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          );
        },
        expect: () => [],
      );

      blocTest<TicketsCubit, TicketsState>(
        'no-ops while a load-more is already in flight',
        build: () => TicketsCubit(repository),
        seed: () => TicketsLoadingMore([ticket]),
        act: (cubit) => cubit.loadMoreTickets(),
        verify: (_) {
          verifyNever(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          );
        },
        expect: () => [],
      );

      blocTest<TicketsCubit, TicketsState>(
        'emits TicketsLoadMoreFailed preserving the existing tickets on a '
        'repository throw',
        setUp: () {
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenThrow(Exception('boom'));
        },
        build: () => TicketsCubit(repository),
        seed: () => TicketsLoaded([ticket], hasMore: true),
        act: (cubit) => cubit.loadMoreTickets(),
        expect: () => [
          TicketsLoadingMore([ticket]),
          TicketsLoadMoreFailed([ticket], hasMore: true),
        ],
      );

      test(
        'a searchTickets call issued while a loadMoreTickets is in flight '
        'discards the stale load-more result instead of appending it',
        () async {
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer(
            (_) async => TicketSearchPage(tickets: [ticket], hasMore: true),
          );

          final cubit = TicketsCubit(repository);
          await cubit.searchTickets();
          expect(cubit.state, TicketsLoaded([ticket], hasMore: true));

          final loadMoreCompleter = Completer<TicketSearchPage>();
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer((_) => loadMoreCompleter.future);

          final loadMoreFuture = cubit.loadMoreTickets();
          expect(cubit.state, TicketsLoadingMore([ticket]));

          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer(
            (_) async => TicketSearchPage(tickets: [unrelated], hasMore: false),
          );
          await cubit.searchTickets(query: 'x');
          expect(cubit.state, TicketsLoaded([unrelated], hasMore: false));

          loadMoreCompleter.complete(
            TicketSearchPage(tickets: [grandchild], hasMore: false),
          );
          await loadMoreFuture;

          expect(cubit.state, TicketsLoaded([unrelated], hasMore: false));

          await cubit.close();
        },
      );
    });

    group('toggleStatusFilter/toggleTypeFilter/togglePriorityFilter/'
        'loadPersistedFilters', () {
      late MockTicketListFilterRepository filterRepository;

      setUp(() {
        filterRepository = MockTicketListFilterRepository();
      });

      void stubEmptySearch() {
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => const TicketSearchPage(tickets: [], hasMore: false),
        );
      }

      test('toggleStatusFilter adds the value when absent, removes it when '
          'present', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(repository);

        await cubit.toggleStatusFilter(TicketStatus.todo);
        expect(cubit.selectedStatuses, {TicketStatus.todo});

        await cubit.toggleStatusFilter(TicketStatus.todo);
        expect(cubit.selectedStatuses, isEmpty);
      });

      test('toggleTypeFilter adds the value when absent, removes it when '
          'present', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(repository);

        await cubit.toggleTypeFilter(TicketType.bug);
        expect(cubit.selectedTypes, {TicketType.bug});

        await cubit.toggleTypeFilter(TicketType.bug);
        expect(cubit.selectedTypes, isEmpty);
      });

      test('togglePriorityFilter adds the value when absent, removes it '
          'when present', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(repository);

        await cubit.togglePriorityFilter(TicketPriority.high);
        expect(cubit.selectedPriorities, {TicketPriority.high});

        await cubit.togglePriorityFilter(TicketPriority.high);
        expect(cubit.selectedPriorities, isEmpty);
      });

      test('a toggle re-runs searchTickets with the updated set and the '
          'other two dimensions unchanged', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(repository);
        await cubit.toggleTypeFilter(TicketType.bug);

        await cubit.toggleStatusFilter(TicketStatus.todo);

        verify(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: {TicketStatus.todo},
            types: {TicketType.bug},
            priorities: const {},
            sort: const TicketListSort(
              field: TicketSortField.createdAt,
              direction: TicketSortDirection.descending,
            ),
            limit: any(named: 'limit'),
          ),
        ).called(1);
      });

      test('a toggle persists the updated selection when filterRepository '
          'and projectId are both supplied', () async {
        stubEmptySearch();
        when(
          () => filterRepository.setFilters(any(), any()),
        ).thenAnswer((_) async {});
        final cubit = TicketsCubit(
          repository,
          filterRepository: filterRepository,
          projectId: 'proj-1',
        );

        await cubit.toggleStatusFilter(TicketStatus.todo);

        verify(
          () => filterRepository.setFilters(
            'proj-1',
            const TicketListFilters(statuses: {TicketStatus.todo}),
          ),
        ).called(1);
      });

      test('a toggle does not persist when filterRepository is null', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(repository, projectId: 'proj-1');

        // No filterRepository supplied — nothing to verify a call
        // against; this only needs to complete without throwing.
        await cubit.toggleStatusFilter(TicketStatus.todo);

        expect(cubit.selectedStatuses, {TicketStatus.todo});
      });

      test('a toggle does not persist when projectId is null', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(
          repository,
          filterRepository: filterRepository,
        );

        await cubit.toggleStatusFilter(TicketStatus.todo);

        verifyNever(() => filterRepository.setFilters(any(), any()));
      });

      test('loadPersistedFilters populates the remembered-filter fields '
          'from the repository without emitting a state', () async {
        when(() => filterRepository.getFilters('proj-1')).thenAnswer(
          (_) async => const TicketListFilters(
            statuses: {TicketStatus.todo},
            types: {TicketType.bug},
            priorities: {TicketPriority.high},
          ),
        );
        final cubit = TicketsCubit(
          repository,
          filterRepository: filterRepository,
          projectId: 'proj-1',
        );
        final states = <TicketsState>[];
        final subscription = cubit.stream.listen(states.add);

        await cubit.loadPersistedFilters();

        expect(cubit.selectedStatuses, {TicketStatus.todo});
        expect(cubit.selectedTypes, {TicketType.bug});
        expect(cubit.selectedPriorities, {TicketPriority.high});
        expect(states, isEmpty);
        await subscription.cancel();
      });

      test(
        'loadPersistedFilters no-ops when filterRepository is null',
        () async {
          final cubit = TicketsCubit(repository, projectId: 'proj-1');

          await cubit.loadPersistedFilters();

          expect(cubit.selectedStatuses, isEmpty);
        },
      );

      test('loadPersistedFilters no-ops when projectId is null', () async {
        final cubit = TicketsCubit(
          repository,
          filterRepository: filterRepository,
        );

        await cubit.loadPersistedFilters();

        verifyNever(() => filterRepository.getFilters(any()));
        expect(cubit.selectedStatuses, isEmpty);
      });
    });

    group('setSort/loadPersistedSort/sort resolution '
        '(ticket-sort-control-and-board-as-default-view)', () {
      late MockTicketListSortRepository sortRepository;

      const createdAtDesc = TicketListSort(
        field: TicketSortField.createdAt,
        direction: TicketSortDirection.descending,
      );
      const relevanceDesc = TicketListSort(
        field: TicketSortField.relevance,
        direction: TicketSortDirection.descending,
      );
      const priorityAsc = TicketListSort(
        field: TicketSortField.priority,
        direction: TicketSortDirection.ascending,
      );

      setUp(() {
        sortRepository = MockTicketListSortRepository();
      });

      void stubEmptySearch({bool hasMore = false}) {
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async => TicketSearchPage(tickets: const [], hasMore: hasMore),
        );
      }

      test('searchTickets with no query passes the implicit createdAt '
          'descending sort', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(repository);

        await cubit.searchTickets();

        verify(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: createdAtDesc,
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).called(1);
        expect(cubit.currentSort, createdAtDesc);
      });

      test('searchTickets with a non-empty query passes the implicit '
          'relevance sort', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(repository);

        await cubit.searchTickets(query: 'bug');

        verify(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: relevanceDesc,
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).called(1);
        expect(cubit.currentSort, relevanceDesc);
      });

      test('setSort persists via sortRepository when projectId is supplied, '
          'and re-searches with the new sort', () async {
        stubEmptySearch();
        when(
          () => sortRepository.setSort(any(), any()),
        ).thenAnswer((_) async {});
        final cubit = TicketsCubit(
          repository,
          sortRepository: sortRepository,
          projectId: 'proj-1',
        );

        await cubit.setSort(priorityAsc);

        verify(() => sortRepository.setSort('proj-1', priorityAsc)).called(1);
        expect(cubit.currentSort, priorityAsc);
        verify(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: priorityAsc,
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).called(1);
      });

      test('setSort does not persist when sortRepository is null', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(repository, projectId: 'proj-1');

        await cubit.setSort(priorityAsc);

        expect(cubit.currentSort, priorityAsc);
      });

      test('setSort does not persist when projectId is null', () async {
        stubEmptySearch();
        final cubit = TicketsCubit(repository, sortRepository: sortRepository);

        await cubit.setSort(priorityAsc);

        verifyNever(() => sortRepository.setSort(any(), any()));
        expect(cubit.currentSort, priorityAsc);
      });

      test(
        'an explicit sort stays sticky even after the query is cleared',
        () async {
          stubEmptySearch();
          final cubit = TicketsCubit(repository);
          await cubit.setSort(priorityAsc);

          await cubit.searchTickets(query: 'anything');
          await cubit.searchTickets(query: '');

          expect(cubit.currentSort, priorityAsc);
        },
      );

      test('loadPersistedSort populates currentSort from a fake repository '
          'without emitting a state', () async {
        when(
          () => sortRepository.getSort('proj-1'),
        ).thenAnswer((_) async => priorityAsc);
        final cubit = TicketsCubit(
          repository,
          sortRepository: sortRepository,
          projectId: 'proj-1',
        );
        final states = <TicketsState>[];
        final subscription = cubit.stream.listen(states.add);

        await cubit.loadPersistedSort();

        expect(cubit.currentSort, priorityAsc);
        expect(states, isEmpty);
        await subscription.cancel();
      });

      test('loadPersistedSort no-ops when sortRepository is null', () async {
        final cubit = TicketsCubit(repository, projectId: 'proj-1');

        await cubit.loadPersistedSort();

        expect(cubit.currentSort, createdAtDesc);
      });

      test('loadPersistedSort no-ops when projectId is null', () async {
        final cubit = TicketsCubit(repository, sortRepository: sortRepository);

        await cubit.loadPersistedSort();

        verifyNever(() => sortRepository.getSort(any()));
        expect(cubit.currentSort, createdAtDesc);
      });

      test('loadMoreTickets reuses the last resolved sort', () async {
        stubEmptySearch(hasMore: true);
        final cubit = TicketsCubit(repository);
        await cubit.setSort(priorityAsc);
        await cubit.searchTickets();

        await cubit.loadMoreTickets();

        // setSort's own re-search, the explicit searchTickets() call,
        // and loadMoreTickets' reuse of _lastSort all resolved
        // sort: priorityAsc — 3 calls total.
        verify(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: priorityAsc,
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).called(3);
      });

      test(
        'createTicket refresh search passes the current resolved sort',
        () async {
          stubEmptySearch();
          when(() => repository.createTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket);
          final cubit = TicketsCubit(repository);
          await cubit.setSort(priorityAsc);
          clearInteractions(repository);
          stubEmptySearch();
          when(() => repository.createTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket);

          await cubit.createTicket(type: TicketType.task, title: 'New');

          verify(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: priorityAsc,
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).called(1);
        },
      );

      test('updateTicketStatus refresh search passes the current resolved '
          'sort', () async {
        stubEmptySearch();
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => ticket);
        final cubit = TicketsCubit(repository);
        await cubit.setSort(priorityAsc);
        clearInteractions(repository);
        stubEmptySearch();
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => ticket);

        await cubit.updateTicketStatus(ticket.id, TicketStatus.done);

        verify(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: priorityAsc,
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).called(1);
      });

      test(
        'trashTicket refresh search passes the current resolved sort',
        () async {
          stubEmptySearch();
          when(
            () => repository.trashTicket(ticket.id),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket);
          final cubit = TicketsCubit(repository);
          await cubit.setSort(priorityAsc);
          clearInteractions(repository);
          stubEmptySearch();
          when(
            () => repository.trashTicket(ticket.id),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket);

          await cubit.trashTicket(ticket.id);

          verify(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: priorityAsc,
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).called(1);
        },
      );

      test(
        'trashTickets refresh search passes the current resolved sort',
        () async {
          stubEmptySearch();
          when(
            () => repository.trashTickets([ticket.id]),
          ).thenAnswer((_) async => 1);
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket);
          final cubit = TicketsCubit(repository);
          await cubit.setSort(priorityAsc);
          clearInteractions(repository);
          stubEmptySearch();
          when(
            () => repository.trashTickets([ticket.id]),
          ).thenAnswer((_) async => 1);
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket);

          await cubit.trashTickets([ticket.id]);

          verify(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: priorityAsc,
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).called(1);
        },
      );

      test('updateStatusForTickets refresh search passes the current '
          'resolved sort', () async {
        stubEmptySearch();
        when(
          () => repository.updateStatusForIds(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => ticket);
        final cubit = TicketsCubit(repository);
        await cubit.setSort(priorityAsc);
        clearInteractions(repository);
        stubEmptySearch();
        when(
          () => repository.updateStatusForIds(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => ticket);

        await cubit.updateStatusForTickets([ticket.id], TicketStatus.done);

        verify(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: priorityAsc,
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).called(1);
      });

      test('updatePriorityForTickets refresh search passes the current '
          'resolved sort', () async {
        stubEmptySearch();
        when(
          () => repository.updatePriorityForIds(any(), any()),
        ).thenAnswer((_) async {});
        final cubit = TicketsCubit(repository);
        await cubit.setSort(priorityAsc);
        clearInteractions(repository);
        stubEmptySearch();
        when(
          () => repository.updatePriorityForIds(any(), any()),
        ).thenAnswer((_) async {});

        await cubit.updatePriorityForTickets([ticket.id], TicketPriority.high);

        verify(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: priorityAsc,
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).called(1);
      });
    });

    group('getValidParentCandidates', () {
      test('excludes self and the full multi-level descendant chain', () async {
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [ticket, child, grandchild, unrelated]);

        final candidates = await TicketsCubit(
          repository,
        ).getValidParentCandidates(ticket);

        expect(candidates.map((t) => t.id), [unrelated.id]);
      });

      test('excludes candidates whose type cannot parent the ticket type, '
          'keeps compatible ones', () async {
        when(() => repository.getAllTickets()).thenAnswer(
          (_) async => [ticket, unrelated, otherTask, resourceTicket],
        );

        final candidates = await TicketsCubit(
          repository,
        ).getValidParentCandidates(ticket);

        // unrelated (story) can parent ticket (task): kept.
        // otherTask (task) cannot parent ticket (task, same rank): excluded.
        // resourceTicket (leaf) can never parent anything: excluded.
        expect(candidates.map((t) => t.id).toSet(), {unrelated.id});
      });
    });

    group('getValidParentCandidatesForType', () {
      test('returns only tickets whose type can parent the given child type, '
          'with no self/descendant exclusion', () async {
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [ticket, story, resourceTicket, otherTask]);

        final candidates = await TicketsCubit(
          repository,
        ).getValidParentCandidatesForType(TicketType.task);

        // story can parent task; ticket/otherTask (task) cannot parent
        // task (same rank); resourceTicket (leaf) can never parent.
        expect(candidates.map((t) => t.id).toSet(), {story.id});
      });
    });

    group('getAllTickets', () {
      test('forwards the repository result unmodified', () async {
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [ticket, child, grandchild, unrelated]);

        final all = await TicketsCubit(repository).getAllTickets();

        expect(all, [ticket, child, grandchild, unrelated]);
      });

      blocTest<TicketsCubit, TicketsState>(
        'emits no state',
        setUp: () {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [ticket]);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.getAllTickets(),
        expect: () => [],
      );
    });

    group('updateTicketParent', () {
      blocTest<TicketsCubit, TicketsState>(
        'persists a valid reparent and emits [TicketDetailLoaded]',
        setUp: () {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [ticket, child, unrelated]);
          when(
            () => repository.updateTicketParent(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => reparented);
          when(
            () => repository.getTicketById(unrelated.id),
          ).thenAnswer((_) async => unrelated);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, unrelated.id),
        verify: (_) {
          verify(
            () => repository.updateTicketParent(ticket.id, unrelated.id),
          ).called(1);
        },
        expect: () => [TicketDetailLoaded(reparented)],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects self-parenting without calling the repository',
        setUp: () {
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, ticket.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(ticket),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting an epic without calling the repository',
        setUp: () {
          when(
            () => repository.getTicketById(epic.id),
          ).thenAnswer((_) async => epic);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(epic, unrelated.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(epic),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting an idea ticket without calling the repository',
        setUp: () {
          when(
            () => repository.getTicketById(ideaTicket.id),
          ).thenAnswer((_) async => ideaTicket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ideaTicket, unrelated.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(ideaTicket),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting a release ticket without calling the repository',
        setUp: () {
          when(
            () => repository.getTicketById(releaseTicket.id),
          ).thenAnswer((_) async => releaseTicket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(releaseTicket, unrelated.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(releaseTicket),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting an Inbox-purpose chat (inboxPurpose set) '
        'without calling the repository, even though chat is not '
        'type-level isAlwaysRoot',
        setUp: () {
          final inboxChat = chatTicket.copyWith(
            inboxPurpose: () => InboxPurpose.qa,
          );
          when(
            () => repository.getTicketById(inboxChat.id),
          ).thenAnswer((_) async => inboxChat);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(
          chatTicket.copyWith(inboxPurpose: () => InboxPurpose.qa),
          ticket.id,
        ),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(
            chatTicket.copyWith(inboxPurpose: () => InboxPurpose.qa),
          ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting onto a descendant without calling the repository',
        setUp: () {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [ticket, child, unrelated]);
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, child.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(ticket),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting under a type-incompatible candidate '
        '(task under task) without calling the repository',
        setUp: () {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [ticket, otherTask]);
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
          when(
            () => repository.getTicketById(otherTask.id),
          ).thenAnswer((_) async => otherTask);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, otherTask.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(ticket),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting a story under a task without calling the '
        'repository',
        setUp: () {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [story, ticket]);
          when(
            () => repository.getTicketById(story.id),
          ).thenAnswer((_) async => story);
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(story, ticket.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(story),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejects reparenting under a resource (a leaf type that can never '
        'parent) without calling the repository',
        setUp: () {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [ticket, resourceTicket]);
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
          when(
            () => repository.getTicketById(resourceTicket.id),
          ).thenAnswer((_) async => resourceTicket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, resourceTicket.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(ticket),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'persists a valid reparent for a leaf type under a task '
        '(chat under task) and emits [TicketDetailLoaded]',
        setUp: () {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [chatTicket, ticket]);
          when(
            () => repository.updateTicketParent(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
          when(
            () => repository.getTicketById(chatTicket.id),
          ).thenAnswer((_) async => chatReparented);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(chatTicket, ticket.id),
        verify: (_) {
          verify(
            () => repository.updateTicketParent(chatTicket.id, ticket.id),
          ).called(1);
        },
        expect: () => [TicketDetailLoaded(chatReparented)],
      );

      blocTest<TicketsCubit, TicketsState>(
        'persists clearing the parent to null',
        setUp: () {
          when(
            () => repository.updateTicketParent(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => cleared);
          // Stubbed for the rollup-recompute walk this now also triggers
          // (estimate-timespent-rollup-for-ticket-hierarchy) — empty means
          // neither ticket.id nor the old parentId is found, so no
          // updateRollup/projectBatch call follows.
          when(() => repository.getAllTickets()).thenAnswer((_) async => []);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(ticket, null),
        verify: (_) {
          verify(
            () => repository.updateTicketParent(ticket.id, null),
          ).called(1);
        },
        expect: () => [TicketDetailLoaded(cleared)],
      );
    });

    group('embedding + git-projection triggers', () {
      late MockEmbeddingProvider embeddingProvider;
      late MockTicketGitProjector gitProjector;
      const rootPath = '/root';

      setUp(() {
        embeddingProvider = MockEmbeddingProvider();
        gitProjector = MockTicketGitProjector();
        when(
          () => embeddingProvider.embed(any()),
        ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
        when(
          () => gitProjector.project(any(), any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.updateEmbedding(any(), any()),
        ).thenAnswer((_) async {});
      });

      TicketsCubit buildCubit() => TicketsCubit(
        repository,
        embeddingProvider: embeddingProvider,
        gitProjector: gitProjector,
        projectRootPath: rootPath,
      );

      blocTest<TicketsCubit, TicketsState>(
        'createTicket always triggers embedding regen and a "created" projection',
        setUp: () {
          when(() => repository.createTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket);
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer(
            (_) async => TicketSearchPage(tickets: [ticket], hasMore: false),
          );
        },
        build: buildCubit,
        act: (cubit) =>
            cubit.createTicket(type: TicketType.task, title: 'New ticket'),
        verify: (_) {
          verify(() => embeddingProvider.embed(any())).called(1);
          verify(
            () => gitProjector.project(ticket, rootPath, 'created'),
          ).called(1);
        },
        expect: () => [
          const TicketCreating([]),
          TicketCreated([ticket], hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicket triggers embedding regen only when title/description changed',
        setUp: () {
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(() => repository.getTicketById(ticket.id)).thenAnswer(
            (_) async => ticket, // "previous" and "refreshed" both unchanged
          );
        },
        build: buildCubit,
        act: (cubit) =>
            cubit.updateTicket(ticket.copyWith(priority: TicketPriority.high)),
        verify: (_) {
          verifyNever(() => embeddingProvider.embed(any()));
          verifyNever(() => gitProjector.project(any(), any(), any()));
        },
        expect: () => [TicketDetailLoaded(ticket)],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicketStatus (board path) triggers a "status-changed" projection, no embedding',
        setUp: () {
          when(
            () => repository.updateTicketStatus(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket.copyWith(status: TicketStatus.done));
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer(
            (_) async => TicketSearchPage(
              tickets: [ticket.copyWith(status: TicketStatus.done)],
              hasMore: false,
            ),
          );
        },
        build: buildCubit,
        seed: () => TicketsLoaded([ticket], hasMore: false),
        act: (cubit) => cubit.updateTicketStatus(ticket.id, TicketStatus.done),
        verify: (_) {
          verifyNever(() => embeddingProvider.embed(any()));
          verify(
            () => gitProjector.project(
              ticket.copyWith(status: TicketStatus.done),
              rootPath,
              'status-changed',
            ),
          ).called(1);
        },
        expect: () => [
          TicketStatusUpdating([ticket.copyWith(status: TicketStatus.done)]),
          TicketStatusUpdated([
            ticket.copyWith(status: TicketStatus.done),
          ], hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'trashTicket triggers a "trashed" projection',
        setUp: () {
          when(
            () => repository.trashTicket(ticket.id),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
        },
        build: buildCubit,
        seed: () => TicketDetailLoaded(ticket),
        act: (cubit) => cubit.trashTicket(ticket.id),
        verify: (_) {
          verify(
            () => gitProjector.project(ticket, rootPath, 'trashed'),
          ).called(1);
        },
        expect: () => [const TicketTrashing(), const TicketTrashed()],
      );

      blocTest<TicketsCubit, TicketsState>(
        'when no embeddingProvider/gitProjector/projectRootPath is given, both no-op',
        setUp: () {
          when(() => repository.createTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket);
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer(
            (_) async => TicketSearchPage(tickets: [ticket], hasMore: false),
          );
        },
        build: () => TicketsCubit(repository), // no optional params
        act: (cubit) =>
            cubit.createTicket(type: TicketType.task, title: 'New ticket'),
        expect: () => [
          const TicketCreating([]),
          TicketCreated([ticket], hasMore: false),
        ],
      );
    });

    group('estimation-suggestion triggers '
        '(ai-assisted-complexity-and-estimate-suggestions)', () {
      late MockEmbeddingProvider embeddingProvider;
      late MockProviderRegistry providerRegistry;
      late MockAgentProvider agentProvider;
      late MockAgentModelClient client;
      late MockModelRoutingRepository modelRoutingRepository;

      setUp(() {
        embeddingProvider = MockEmbeddingProvider();
        providerRegistry = MockProviderRegistry();
        agentProvider = MockAgentProvider();
        client = MockAgentModelClient();
        modelRoutingRepository = MockModelRoutingRepository();

        when(
          () => embeddingProvider.embed(any()),
        ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
        when(() => agentProvider.client).thenReturn(client);
        when(
          () => providerRegistry.providerById(ProviderId.claudeAgentSdk),
        ).thenReturn(agentProvider);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).thenAnswer((_) async => _sonnet);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('COMPLEXITY: medium\nESTIMATE_MINUTES: 60'),
            AgentDoneEvent(),
          ]),
        );
        when(() => repository.getAllTickets()).thenAnswer((_) async => []);
        when(
          () => repository.applyEstimationSuggestion(
            any(),
            complexity: any(named: 'complexity'),
            estimate: any(named: 'estimate'),
          ),
        ).thenAnswer((_) async {});
        // Also fires alongside the estimation suggester (both are
        // unawaited background calls off create/update) — stubbed so it
        // doesn't throw an unstubbed-call error.
        when(
          () => repository.updateEmbedding(any(), any()),
        ).thenAnswer((_) async {});
      });

      TicketsCubit buildCubit() => TicketsCubit(
        repository,
        embeddingProvider: embeddingProvider,
        providerRegistry: providerRegistry,
        modelRoutingRepository: modelRoutingRepository,
      );

      blocTest<TicketsCubit, TicketsState>(
        'createTicket always fires the estimation suggester in the '
        'background',
        setUp: () {
          when(() => repository.createTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => ticket);
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer(
            (_) async => TicketSearchPage(tickets: [ticket], hasMore: false),
          );
        },
        build: buildCubit,
        act: (cubit) =>
            cubit.createTicket(type: TicketType.task, title: 'New ticket'),
        wait: const Duration(milliseconds: 10),
        verify: (_) {
          verify(
            () => repository.applyEstimationSuggestion(
              ticket.id,
              complexity: any(named: 'complexity'),
              estimate: any(named: 'estimate'),
            ),
          ).called(1);
        },
        expect: () => [
          const TicketCreating([]),
          TicketCreated([ticket], hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicket does not fire the estimation suggester when title/'
        'description are unchanged',
        setUp: () {
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(() => repository.getTicketById(ticket.id)).thenAnswer(
            (_) async => ticket, // "previous" and "refreshed" both unchanged
          );
        },
        build: buildCubit,
        act: (cubit) =>
            cubit.updateTicket(ticket.copyWith(priority: TicketPriority.high)),
        wait: const Duration(milliseconds: 10),
        verify: (_) {
          verifyNever(
            () => repository.applyEstimationSuggestion(
              any(),
              complexity: any(named: 'complexity'),
              estimate: any(named: 'estimate'),
            ),
          );
        },
        expect: () => [TicketDetailLoaded(ticket)],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicket fires the estimation suggester when the title '
        'changed',
        setUp: () {
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          var callCount = 0;
          when(() => repository.getTicketById(ticket.id)).thenAnswer((_) async {
            callCount++;
            // First call ("previous") returns the original ticket;
            // second call ("refreshed") returns the title-changed one.
            return callCount == 1 ? ticket : ticket.copyWith(title: 'New');
          });
        },
        build: buildCubit,
        act: (cubit) => cubit.updateTicket(ticket.copyWith(title: 'New')),
        wait: const Duration(milliseconds: 10),
        verify: (_) {
          verify(
            () => repository.applyEstimationSuggestion(
              ticket.id,
              complexity: any(named: 'complexity'),
              estimate: any(named: 'estimate'),
            ),
          ).called(1);
        },
        expect: () => [TicketDetailLoaded(ticket.copyWith(title: 'New'))],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicket live-refreshes the ticket\'s own already-open detail '
        'screen once the passive suggestion lands, with no intervening '
        'TicketsLoading (live-refresh-open-ticket-detail-screen)',
        setUp: () {
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          var callCount = 0;
          when(() => repository.getTicketById(ticket.id)).thenAnswer((_) async {
            callCount++;
            // 1st call: updateTicket's "previous" fetch — must return the
            // *unchanged* title, or the title-changed check that gates
            // firing the estimation suggester never sees a difference and
            // the whole chain this test exists to cover never fires. 2nd
            // call: updateTicket's own "refreshed" fetch (emitted
            // synchronously). 3rd+ call: the live-refresh triggered once
            // the background suggestion lands, via
            // _refreshDetailIfOpenAndAffected.
            return switch (callCount) {
              1 => ticket,
              2 => ticket.copyWith(title: 'New'),
              _ => ticket.copyWith(
                title: 'New',
                complexity: () => TicketComplexity.medium,
                estimate: () => 60,
              ),
            };
          });
        },
        build: buildCubit,
        seed: () => TicketDetailLoaded(ticket),
        act: (cubit) => cubit.updateTicket(ticket.copyWith(title: 'New')),
        wait: const Duration(milliseconds: 10),
        expect: () => [
          TicketDetailLoaded(ticket.copyWith(title: 'New')),
          TicketDetailLoaded(
            ticket.copyWith(
              title: 'New',
              complexity: () => TicketComplexity.medium,
              estimate: () => 60,
            ),
          ),
        ],
      );
    });

    group('token-prediction triggers (token-cost-prediction)', () {
      late MockEmbeddingProvider embeddingProvider;

      // `Ticket.embedding` (unlike `ticket` above) is required for
      // `TicketTokenPredictor.suggest` to get past its own-embedding
      // guard — built directly rather than via `copyWith` since
      // `embedding` isn't a settable `copyWith` parameter.
      final embeddedTicket = Ticket(
        id: ticket.id,
        ticketId: ticket.ticketId,
        type: TicketType.task,
        title: ticket.title,
        status: ticket.status,
        createdAt: ticket.createdAt,
        updatedAt: ticket.updatedAt,
        embedding: Uint8List.fromList([1, 2, 3, 4]),
      );
      final comparableTicket = Ticket(
        id: 'other',
        ticketId: 'AIO-other',
        type: TicketType.task,
        title: 'Other ticket',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        embedding: Uint8List.fromList([1, 2, 3, 4]),
      );

      setUp(() {
        embeddingProvider = MockEmbeddingProvider();
        // Also fires alongside the token predictor (both are unawaited
        // background calls off create/update) — stubbed so it doesn't
        // throw an unstubbed-call error, mirroring the estimation-
        // suggestion trigger group above.
        when(
          () => embeddingProvider.embed(any()),
        ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
        when(
          () => repository.updateEmbedding(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketsByParent(
            any(),
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => []);
        when(
          () => repository.getAllTicketsByType(any()),
        ).thenAnswer((_) async => [comparableTicket]);
        when(
          () => repository.getExecutionTokenTotals(any()),
        ).thenAnswer((_) async => {'other': 20000});
        when(
          () => repository.applyTokenPrediction(
            any(),
            low: any(named: 'low'),
            high: any(named: 'high'),
          ),
        ).thenAnswer((_) async {});
      });

      TicketsCubit buildCubit() =>
          TicketsCubit(repository, embeddingProvider: embeddingProvider);

      blocTest<TicketsCubit, TicketsState>(
        'createTicket fires the token predictor in the background',
        setUp: () {
          when(() => repository.createTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(any()),
          ).thenAnswer((_) async => embeddedTicket);
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer(
            (_) async =>
                TicketSearchPage(tickets: [embeddedTicket], hasMore: false),
          );
        },
        build: buildCubit,
        act: (cubit) =>
            cubit.createTicket(type: TicketType.task, title: 'New ticket'),
        wait: const Duration(milliseconds: 10),
        verify: (_) {
          verify(
            () => repository.applyTokenPrediction(
              embeddedTicket.id,
              low: any(named: 'low'),
              high: any(named: 'high'),
            ),
          ).called(1);
        },
        expect: () => [
          const TicketCreating([]),
          TicketCreated([embeddedTicket], hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicket fires the token predictor when the title changed',
        setUp: () {
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          var callCount = 0;
          when(() => repository.getTicketById(embeddedTicket.id)).thenAnswer((
            _,
          ) async {
            callCount++;
            // First call ("previous") returns the original ticket; second
            // call ("refreshed") returns the title-changed one.
            return callCount == 1
                ? embeddedTicket
                : embeddedTicket.copyWith(title: 'New');
          });
        },
        build: buildCubit,
        act: (cubit) =>
            cubit.updateTicket(embeddedTicket.copyWith(title: 'New')),
        wait: const Duration(milliseconds: 10),
        verify: (_) {
          verify(
            () => repository.applyTokenPrediction(
              embeddedTicket.id,
              low: any(named: 'low'),
              high: any(named: 'high'),
            ),
          ).called(1);
        },
        expect: () => [TicketDetailLoaded(embeddedTicket.copyWith(title: 'New'))],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicket does not fire the token predictor when title/'
        'description are unchanged',
        setUp: () {
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(() => repository.getTicketById(embeddedTicket.id)).thenAnswer(
            (_) async => embeddedTicket, // "previous" and "refreshed" match
          );
        },
        build: buildCubit,
        act: (cubit) => cubit.updateTicket(
          embeddedTicket.copyWith(priority: TicketPriority.high),
        ),
        wait: const Duration(milliseconds: 10),
        verify: (_) {
          verifyNever(
            () => repository.applyTokenPrediction(
              any(),
              low: any(named: 'low'),
              high: any(named: 'high'),
            ),
          );
        },
        expect: () => [TicketDetailLoaded(embeddedTicket)],
      );
    });

    group('regenerateComplexitySuggestion / regenerateEstimateSuggestion '
        '(ai-assisted-complexity-and-estimate-suggestions)', () {
      final sizedTicket = ticket.copyWith(
        complexity: () => TicketComplexity.medium,
        estimate: () => 60,
      );

      blocTest<TicketsCubit, TicketsState>(
        'regenerateComplexitySuggestion no-ops on a ticket with no '
        'complexity set',
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.regenerateComplexitySuggestion(ticket),
        expect: () => [],
        verify: (_) {
          verifyNever(() => repository.getTicketById(any()));
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'regenerateEstimateSuggestion no-ops on a ticket with no estimate '
        'set',
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.regenerateEstimateSuggestion(ticket),
        expect: () => [],
        verify: (_) {
          verifyNever(() => repository.getTicketById(any()));
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'regenerateComplexitySuggestion re-fetches and emits '
        'TicketDetailLoaded once the suggester call resolves (including '
        'a silent suggester failure — no embeddingProvider/'
        'providerRegistry supplied here)',
        setUp: () {
          when(
            () => repository.getTicketById(sizedTicket.id),
          ).thenAnswer((_) async => sizedTicket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.regenerateComplexitySuggestion(sizedTicket),
        expect: () => [TicketDetailLoaded(sizedTicket)],
      );

      blocTest<TicketsCubit, TicketsState>(
        'regenerateEstimateSuggestion emits TicketsError only if the '
        'repository re-fetch itself throws',
        setUp: () {
          when(
            () => repository.getTicketById(sizedTicket.id),
          ).thenThrow(Exception('db unavailable'));
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.regenerateEstimateSuggestion(sizedTicket),
        expect: () => [isA<TicketsError>()],
      );
    });

    group('rollup recompute triggers '
        '(estimate-timespent-rollup-for-ticket-hierarchy)', () {
      late MockTicketGitProjector gitProjector;
      const rootPath = '/root';

      final rollupEpic = Ticket(
        id: 'rollup-epic',
        ticketId: 'AIO-200',
        type: TicketType.epic,
        title: 'Rollup epic',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final rollupStory = Ticket(
        id: 'rollup-story',
        ticketId: 'AIO-201',
        type: TicketType.story,
        title: 'Rollup story',
        status: TicketStatus.backlog,
        parentId: rollupEpic.id,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final rollupTask = Ticket(
        id: 'rollup-task',
        ticketId: 'AIO-202',
        type: TicketType.task,
        title: 'Rollup task',
        status: TicketStatus.backlog,
        parentId: rollupStory.id,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      // updateTicket's rollup trigger checks estimate/timeSpent on the
      // *edited* ticket it's given, so this is the value `act` passes
      // in and `setUp`'s "refreshed" stub returns.
      final rollupTaskEdited = rollupTask.copyWith(estimate: () => 60);

      setUp(() {
        gitProjector = MockTicketGitProjector();
        // Single-ticket projection — used by trashTicket/trashTickets'
        // own existing per-ticket git-projection trigger, unrelated to
        // the rollup recompute's own batched projection below, but
        // still exercised whenever gitProjector/projectRootPath are
        // supplied.
        when(
          () => gitProjector.project(any(), any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => gitProjector.projectBatch(any(), any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.updateRollup(
            any(),
            estimateRollup: any(named: 'estimateRollup'),
            timeSpentRollup: any(named: 'timeSpentRollup'),
          ),
        ).thenAnswer((_) async {});
      });

      TicketsCubit buildCubit() => TicketsCubit(
        repository,
        gitProjector: gitProjector,
        projectRootPath: rootPath,
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicket changing estimate/timeSpent recomputes every '
        'ancestor up to the root',
        setUp: () {
          var getTicketByIdCallCount = 0;
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(() => repository.getTicketById(rollupTask.id)).thenAnswer((
            _,
          ) async {
            getTicketByIdCallCount++;
            // First call is updateTicket's "previous" fetch (before the
            // write); second is its "refreshed" fetch (after).
            return getTicketByIdCallCount == 1 ? rollupTask : rollupTaskEdited;
          });
          when(() => repository.getAllTickets()).thenAnswer(
            (_) async => [rollupEpic, rollupStory, rollupTaskEdited],
          );
        },
        build: buildCubit,
        act: (cubit) => cubit.updateTicket(rollupTaskEdited),
        verify: (_) {
          verify(
            () => repository.updateRollup(
              rollupStory.id,
              estimateRollup: 60,
              timeSpentRollup: null,
            ),
          ).called(1);
          verify(
            () => repository.updateRollup(
              rollupEpic.id,
              estimateRollup: 60,
              timeSpentRollup: null,
            ),
          ).called(1);
          // The edited leaf itself has no children, so it never gets a
          // rollup of its own.
          verifyNever(
            () => repository.updateRollup(
              rollupTask.id,
              estimateRollup: any(named: 'estimateRollup'),
              timeSpentRollup: any(named: 'timeSpentRollup'),
            ),
          );
        },
        expect: () => [TicketDetailLoaded(rollupTaskEdited)],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicket changing an unrelated field (priority only) does '
        'not trigger a recompute',
        setUp: () {
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(rollupTask.id),
          ).thenAnswer((_) async => rollupTask);
        },
        build: buildCubit,
        act: (cubit) => cubit.updateTicket(
          rollupTask.copyWith(priority: TicketPriority.high),
        ),
        verify: (_) {
          verifyNever(() => repository.getAllTickets());
          verifyNever(
            () => repository.updateRollup(
              any(),
              estimateRollup: any(named: 'estimateRollup'),
              timeSpentRollup: any(named: 'timeSpentRollup'),
            ),
          );
        },
        expect: () => [TicketDetailLoaded(rollupTask)],
      );

      final reparentOldParent = Ticket(
        id: 'rollup-old-parent',
        ticketId: 'AIO-210',
        type: TicketType.story,
        title: 'Old parent',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        // Stale — reflects the moved task's contribution, which needs
        // to be removed now that it's leaving.
        estimateRollup: 100,
      );
      final reparentNewParent = Ticket(
        id: 'rollup-new-parent',
        ticketId: 'AIO-211',
        type: TicketType.story,
        title: 'New parent',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final reparentSibling = Ticket(
        id: 'rollup-sibling-task',
        ticketId: 'AIO-212',
        type: TicketType.task,
        title: 'Sibling task',
        status: TicketStatus.backlog,
        parentId: reparentOldParent.id,
        estimate: 55,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final reparentMovedTaskBefore = Ticket(
        id: 'rollup-moved-task',
        ticketId: 'AIO-213',
        type: TicketType.task,
        title: 'Moved task',
        status: TicketStatus.backlog,
        parentId: reparentOldParent.id,
        estimate: 45,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final reparentMovedTaskAfter = Ticket(
        id: reparentMovedTaskBefore.id,
        ticketId: reparentMovedTaskBefore.ticketId,
        type: reparentMovedTaskBefore.type,
        title: reparentMovedTaskBefore.title,
        status: reparentMovedTaskBefore.status,
        parentId: reparentNewParent.id,
        estimate: 45,
        createdAt: reparentMovedTaskBefore.createdAt,
        updatedAt: reparentMovedTaskBefore.updatedAt,
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicketParent recomputes both the old and new parent '
        'chains in one operation',
        setUp: () {
          when(
            () => repository.getTicketById(reparentNewParent.id),
          ).thenAnswer((_) async => reparentNewParent);
          when(
            () => repository.updateTicketParent(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(reparentMovedTaskBefore.id),
          ).thenAnswer((_) async => reparentMovedTaskAfter);
          when(() => repository.getAllTickets()).thenAnswer(
            (_) async => [
              reparentOldParent,
              reparentNewParent,
              reparentSibling,
              reparentMovedTaskAfter,
            ],
          );
        },
        build: buildCubit,
        act: (cubit) => cubit.updateTicketParent(
          reparentMovedTaskBefore,
          reparentNewParent.id,
        ),
        verify: (_) {
          verify(
            () => repository.updateRollup(
              reparentOldParent.id,
              estimateRollup: 55,
              timeSpentRollup: null,
            ),
          ).called(1);
          verify(
            () => repository.updateRollup(
              reparentNewParent.id,
              estimateRollup: 45,
              timeSpentRollup: null,
            ),
          ).called(1);
        },
        expect: () => [TicketDetailLoaded(reparentMovedTaskAfter)],
      );

      final trashParent = Ticket(
        id: 'rollup-trash-parent',
        ticketId: 'AIO-220',
        type: TicketType.story,
        title: 'Trash parent',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        estimateRollup: 45,
      );
      final trashedChild = Ticket(
        id: 'rollup-trash-child',
        ticketId: 'AIO-221',
        type: TicketType.task,
        title: 'Trashed child',
        status: TicketStatus.backlog,
        parentId: trashParent.id,
        estimate: 45,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      blocTest<TicketsCubit, TicketsState>(
        'trashTicket recomputes the former parent, excluding the trashed '
        'subtree from the new total',
        setUp: () {
          when(
            () => repository.trashTicket(trashedChild.id),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(trashedChild.id),
          ).thenAnswer((_) async => trashedChild);
          // Excludes trashedChild — mirrors getAllTickets()'s real
          // deleted_at IS NULL filter once the trash write has landed.
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [trashParent]);
        },
        build: buildCubit,
        seed: () => TicketDetailLoaded(trashedChild),
        act: (cubit) => cubit.trashTicket(trashedChild.id),
        verify: (_) {
          verify(
            () => repository.updateRollup(
              trashParent.id,
              estimateRollup: null,
              timeSpentRollup: null,
            ),
          ).called(1);
        },
        expect: () => [const TicketTrashing(), const TicketTrashed()],
      );

      final bulkTrashParent = Ticket(
        id: 'rollup-bulk-trash-parent',
        ticketId: 'AIO-230',
        type: TicketType.story,
        title: 'Bulk trash parent',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        estimateRollup: 45,
      );
      final bulkTrashedChild = Ticket(
        id: 'rollup-bulk-trash-child',
        ticketId: 'AIO-231',
        type: TicketType.task,
        title: 'Bulk trashed child',
        status: TicketStatus.backlog,
        parentId: bulkTrashParent.id,
        estimate: 45,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      blocTest<TicketsCubit, TicketsState>(
        'trashTickets recomputes the (now-former) parent for every '
        'explicitly-trashed id, in one recompute operation',
        setUp: () {
          when(
            () => repository.trashTickets([bulkTrashedChild.id]),
          ).thenAnswer((_) async => 1);
          when(
            () => repository.getTicketById(bulkTrashedChild.id),
          ).thenAnswer((_) async => bulkTrashedChild);
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [bulkTrashParent]);
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              statuses: any(named: 'statuses'),
              types: any(named: 'types'),
              priorities: any(named: 'priorities'),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
            ),
          ).thenAnswer(
            (_) async => const TicketSearchPage(tickets: [], hasMore: false),
          );
        },
        build: buildCubit,
        act: (cubit) => cubit.trashTickets([bulkTrashedChild.id]),
        verify: (_) {
          verify(
            () => repository.updateRollup(
              bulkTrashParent.id,
              estimateRollup: null,
              timeSpentRollup: null,
            ),
          ).called(1);
        },
        expect: () => [
          const TicketsBatchTrashing(),
          isA<TicketsBatchTrashed>(),
        ],
      );

      final noChangeGrandparent = Ticket(
        id: 'rollup-nochange-grandparent',
        ticketId: 'AIO-240',
        type: TicketType.epic,
        title: 'No-change grandparent',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        // Already the value a fresh computeRollups walk will produce —
        // its own rollup is not actually stale here, even though it's
        // on [noChangeParent]'s ancestor chain.
        estimateRollup: 10,
      );
      final noChangeParent = Ticket(
        id: 'rollup-nochange-parent',
        ticketId: 'AIO-241',
        type: TicketType.story,
        title: 'No-change parent',
        status: TicketStatus.backlog,
        parentId: noChangeGrandparent.id,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        // Stale — really does need updating to 10.
      );
      final noChangeEditedChild = Ticket(
        id: 'rollup-nochange-child',
        ticketId: 'AIO-242',
        type: TicketType.task,
        title: 'Edited child',
        status: TicketStatus.backlog,
        parentId: noChangeParent.id,
        estimate: 10,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      blocTest<TicketsCubit, TicketsState>(
        "an ancestor whose computed rollup didn't actually change is not "
        're-written or re-projected, even though it is on the walked path',
        setUp: () {
          when(() => repository.updateTicket(any())).thenAnswer((_) async {});
          var getTicketByIdCallCount = 0;
          when(
            () => repository.getTicketById(noChangeEditedChild.id),
          ).thenAnswer((_) async {
            getTicketByIdCallCount++;
            return getTicketByIdCallCount == 1
                ? noChangeEditedChild.copyWith(estimate: () => null)
                : noChangeEditedChild;
          });
          when(() => repository.getAllTickets()).thenAnswer(
            (_) async => [
              noChangeGrandparent,
              noChangeParent,
              noChangeEditedChild,
            ],
          );
        },
        build: buildCubit,
        act: (cubit) => cubit.updateTicket(noChangeEditedChild),
        verify: (_) {
          verify(
            () => repository.updateRollup(
              noChangeParent.id,
              estimateRollup: 10,
              timeSpentRollup: null,
            ),
          ).called(1);
          verifyNever(
            () => repository.updateRollup(
              noChangeGrandparent.id,
              estimateRollup: any(named: 'estimateRollup'),
              timeSpentRollup: any(named: 'timeSpentRollup'),
            ),
          );
          final projected = verify(
            () => gitProjector.projectBatch(
              captureAny(),
              rootPath,
              'rollup updated',
            ),
          ).captured;
          expect(projected, hasLength(1));
          expect((projected.first as List<Ticket>).map((t) => t.id), [
            noChangeParent.id,
          ]);
        },
        expect: () => [TicketDetailLoaded(noChangeEditedChild)],
      );
    });

    group(
      'getRollupCounts (estimate-timespent-rollup-for-ticket-hierarchy)',
      () {
        test('returns the correct estimateCount/timeSpentCount for a '
            'multi-level subtree, performing no repository writes', () async {
          final grandparent = Ticket(
            id: 'counts-grandparent',
            ticketId: 'AIO-250',
            type: TicketType.epic,
            title: 'Counts grandparent',
            status: TicketStatus.backlog,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );
          final parent = Ticket(
            id: 'counts-parent',
            ticketId: 'AIO-251',
            type: TicketType.story,
            title: 'Counts parent',
            status: TicketStatus.backlog,
            parentId: grandparent.id,
            estimate: 30,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );
          final child1 = Ticket(
            id: 'counts-child-1',
            ticketId: 'AIO-252',
            type: TicketType.task,
            title: 'Counts child 1',
            status: TicketStatus.backlog,
            parentId: parent.id,
            estimate: 15,
            timeSpent: 5,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );
          final child2 = Ticket(
            id: 'counts-child-2',
            ticketId: 'AIO-253',
            type: TicketType.task,
            title: 'Counts child 2',
            status: TicketStatus.backlog,
            parentId: parent.id,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );

          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [grandparent, parent, child1, child2]);

          final counts = await TicketsCubit(
            repository,
          ).getRollupCounts(grandparent);

          // grandparent itself contributes nothing; parent (30) and
          // child1 (15) contribute an estimate; only child1 contributes
          // a timeSpent.
          expect(counts.estimateCount, 2);
          expect(counts.timeSpentCount, 1);
          verifyNever(
            () => repository.updateRollup(
              any(),
              estimateRollup: any(named: 'estimateRollup'),
              timeSpentRollup: any(named: 'timeSpentRollup'),
            ),
          );
        });

        test('returns 0/0 for a childless ticket', () async {
          when(
            () => repository.getAllTickets(),
          ).thenAnswer((_) async => [ticket]);

          final counts = await TicketsCubit(repository).getRollupCounts(ticket);

          expect(counts.estimateCount, 0);
          expect(counts.timeSpentCount, 0);
        });
      },
    );
  });

  group('loadDocumentRelations', () {
    late MockTicketLinkRepository linkRepository;
    late MockPageWikilinkRepository wikilinkRepository;

    final page = Ticket(
      id: 'page-1',
      ticketId: 'AIO-10',
      type: TicketType.page,
      title: 'Doc page',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final childPage = Ticket(
      id: 'page-2',
      ticketId: 'AIO-11',
      type: TicketType.page,
      title: 'Child page',
      status: TicketStatus.backlog,
      parentId: page.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final linkedTask = Ticket(
      id: 'task-1',
      ticketId: 'AIO-12',
      type: TicketType.task,
      title: 'Linked task',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final backlinkPage = Ticket(
      id: 'page-3',
      ticketId: 'AIO-13',
      type: TicketType.page,
      title: 'Backlinking page',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final resourceTicket = Ticket(
      id: 'resource-1',
      ticketId: 'AIO-14',
      type: TicketType.resource,
      title: 'A resource',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUpAll(() {
      registerFallbackValue(TicketLinkType.relatesTo);
      registerFallbackValue(const [TicketLinkType.relatesTo]);
    });

    setUp(() {
      linkRepository = MockTicketLinkRepository();
      wikilinkRepository = MockPageWikilinkRepository();
      // Default (empty) stubs for the recursive gaps-and-open-questions
      // rollup's reads, added for
      // `aion-arch/changes/idea-gap-question-ticket-types` — every gated
      // ticket's `loadDocumentRelations` call now performs these
      // unconditionally alongside the pre-existing `linkedTickets`/
      // `backlinks` reads. Individual tests override these where the
      // rollup itself is under test. Default (empty) stub for the
      // wikilink-origin backlinks merge, added for
      // `aion-arch/changes/inline-wikilink-backlinks` — individual tests
      // override this where the merge itself is under test.
      when(() => repository.getAllTickets()).thenAnswer((_) async => []);
      when(
        () => linkRepository.getLinksByTypes(any()),
      ).thenAnswer((_) async => []);
      when(
        () => wikilinkRepository.getIncomingLinks(any()),
      ).thenAnswer((_) async => []);
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      linkRepository: linkRepository,
      pageWikilinkRepository: wikilinkRepository,
    );

    blocTest<TicketsCubit, TicketsState>(
      'populates childDocs/linkedTickets/backlinks for a page ticket',
      setUp: () {
        when(
          () => repository.getTicketById(page.id),
        ).thenAnswer((_) async => page);
        when(
          () => repository.getTicketsByParent(
            page.id,
            types: const [TicketType.page, TicketType.resource],
          ),
        ).thenAnswer((_) async => [childPage]);
        when(() => linkRepository.getLinksForTicket(page.id)).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: page.id,
              targetTicketId: linkedTask.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
            TicketLinkData(
              id: 'link-2',
              sourceTicketId: backlinkPage.id,
              targetTicketId: page.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          ],
        );
        when(
          () => repository.getTicketById(linkedTask.id),
        ).thenAnswer((_) async => linkedTask);
        when(
          () => repository.getTicketById(backlinkPage.id),
        ).thenAnswer((_) async => backlinkPage);
      },
      build: buildCubit,
      seed: () => TicketDetailLoaded(page),
      act: (cubit) => cubit.loadDocumentRelations(page.id),
      expect: () => [
        isA<TicketDetailLoaded>()
            .having((s) => s.ticket, 'ticket', page)
            .having((s) => s.childDocs, 'childDocs', [childPage])
            .having(
              (s) => s.linkedTickets.map((r) => r.ticket),
              'linkedTickets tickets',
              [linkedTask],
            )
            .having(
              (s) => s.linkedTickets.single.relativeType,
              'linkedTickets relativeType',
              TicketLinkType.relatesTo,
            )
            .having(
              (s) => s.backlinks.map((r) => r.ticket),
              'backlinks tickets',
              [backlinkPage],
            )
            .having(
              (s) => s.backlinks.single.origin,
              'backlinks origin',
              BacklinkOrigin.explicitLink,
            ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'merges wikilink-origin backlinks alongside explicit-link ones for a '
      'page-gated ticket, including a two-rows-for-one-ticket case',
      setUp: () {
        when(
          () => repository.getTicketById(page.id),
        ).thenAnswer((_) async => page);
        when(
          () => repository.getTicketsByParent(
            page.id,
            types: const [TicketType.page, TicketType.resource],
          ),
        ).thenAnswer((_) async => []);
        // backlinkPage links via both an explicit TicketLink *and* an
        // inline wikilink — a deliberate two-rows-for-one-ticket case,
        // each representing a distinct, independently-true relationship.
        when(() => linkRepository.getLinksForTicket(page.id)).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: backlinkPage.id,
              targetTicketId: page.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          ],
        );
        when(
          () => repository.getTicketById(backlinkPage.id),
        ).thenAnswer((_) async => backlinkPage);
        when(
          () => wikilinkRepository.getIncomingLinks(page.id),
        ).thenAnswer(
          (_) async => [
            PageWikilink(
              id: 'wl-1',
              sourcePageId: backlinkPage.id,
              targetPageId: page.id,
              createdAt: DateTime(2026),
            ),
          ],
        );
      },
      build: buildCubit,
      seed: () => TicketDetailLoaded(page),
      act: (cubit) => cubit.loadDocumentRelations(page.id),
      expect: () => [
        isA<TicketDetailLoaded>().having((s) => s.backlinks, 'backlinks', [
          BacklinkRef(ticket: backlinkPage, origin: BacklinkOrigin.explicitLink),
          BacklinkRef(ticket: backlinkPage, origin: BacklinkOrigin.wikilink),
        ]),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'merges wikilink-origin backlinks for a resource-gated ticket',
      setUp: () {
        when(
          () => repository.getTicketById(resourceTicket.id),
        ).thenAnswer((_) async => resourceTicket);
        when(
          () => linkRepository.getLinksForTicket(resourceTicket.id),
        ).thenAnswer((_) async => []);
        when(
          () => wikilinkRepository.getIncomingLinks(resourceTicket.id),
        ).thenAnswer(
          (_) async => [
            PageWikilink(
              id: 'wl-2',
              sourcePageId: page.id,
              targetPageId: resourceTicket.id,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(
          () => repository.getTicketById(page.id),
        ).thenAnswer((_) async => page);
      },
      build: buildCubit,
      seed: () => TicketDetailLoaded(resourceTicket),
      act: (cubit) => cubit.loadDocumentRelations(resourceTicket.id),
      expect: () => [
        isA<TicketDetailLoaded>().having((s) => s.backlinks, 'backlinks', [
          BacklinkRef(ticket: page, origin: BacklinkOrigin.wikilink),
        ]),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'resource tickets never fetch childDocs (always empty)',
      setUp: () {
        when(
          () => repository.getTicketById(resourceTicket.id),
        ).thenAnswer((_) async => resourceTicket);
        when(
          () => linkRepository.getLinksForTicket(resourceTicket.id),
        ).thenAnswer((_) async => []);
      },
      build: buildCubit,
      seed: () => TicketDetailLoaded(resourceTicket),
      act: (cubit) => cubit.loadDocumentRelations(resourceTicket.id),
      // Cubit.emit skips re-emitting a state Equatable-equal to the
      // current one — the seed's default childDocs/linkedTickets/
      // backlinks (all `const []`) already match what this resolves to,
      // so no new state is emitted. The `verify` below is what actually
      // confirms the empty-childDocs behavior.
      expect: () => [],
      verify: (_) {
        verifyNever(
          () =>
              repository.getTicketsByParent(any(), types: any(named: 'types')),
        );
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      // `task` used to no-op here too, before
      // `aion-arch/changes/board-task-ordering-indication` widened the
      // gate to include `epic`/`story`/`task` alongside `page`/
      // `resource`/`bug` — `chat` remains one of the few types with no
      // `TicketLink` use case, so it still exercises the no-op path.
      'no-ops for a chat ticket (still outside the widened gate)',
      setUp: () {
        when(
          () => repository.getTicketById(chatTicket.id),
        ).thenAnswer((_) async => chatTicket);
      },
      build: buildCubit,
      seed: () => TicketDetailLoaded(chatTicket),
      act: (cubit) => cubit.loadDocumentRelations(chatTicket.id),
      expect: () => [],
    );

    blocTest<TicketsCubit, TicketsState>(
      'populates linkedTickets for a bug ticket linked to a release',
      setUp: () {
        final bugTicket = Ticket(
          id: 'bug-1',
          ticketId: 'AIO-15',
          type: TicketType.bug,
          title: 'A bug',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final linkedRelease = Ticket(
          id: 'release-1',
          ticketId: 'AIO-16',
          type: TicketType.release,
          title: 'v1.0',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => repository.getTicketById(bugTicket.id),
        ).thenAnswer((_) async => bugTicket);
        when(
          () => repository.getTicketById(linkedRelease.id),
        ).thenAnswer((_) async => linkedRelease);
        when(() => linkRepository.getLinksForTicket(bugTicket.id)).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-3',
              sourceTicketId: bugTicket.id,
              targetTicketId: linkedRelease.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          ],
        );
      },
      build: buildCubit,
      seed: () => TicketDetailLoaded(
        Ticket(
          id: 'bug-1',
          ticketId: 'AIO-15',
          type: TicketType.bug,
          title: 'A bug',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
      act: (cubit) => cubit.loadDocumentRelations('bug-1'),
      expect: () => [
        isA<TicketDetailLoaded>().having(
          (s) => s.linkedTickets.map((r) => r.ticket.id),
          'linkedTickets ids',
          ['release-1'],
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'no-ops when no TicketLinkRepository was provided',
      setUp: () {
        when(
          () => repository.getTicketById(page.id),
        ).thenAnswer((_) async => page);
        when(
          () => repository.getTicketsByParent(
            page.id,
            types: const [TicketType.page, TicketType.resource],
          ),
        ).thenAnswer((_) async => []);
      },
      build: () => TicketsCubit(repository), // no linkRepository
      seed: () => TicketDetailLoaded(page),
      act: (cubit) => cubit.loadDocumentRelations(page.id),
      // Same Equatable short-circuit as above: the resolved
      // childDocs/linkedTickets/backlinks match the seed's defaults, so
      // no new state is emitted.
      expect: () => [],
      verify: (_) {
        verify(
          () => repository.getTicketsByParent(
            page.id,
            types: const [TicketType.page, TicketType.resource],
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'gapsAndOpenQuestions recursively rolls up a gap raised on a '
      'grandchild Task onto its ancestor Epic, correctly attributing '
      'raisedOn',
      setUp: () {
        final rollupEpic = Ticket(
          id: 'rollup-epic',
          ticketId: 'AIO-30',
          type: TicketType.epic,
          title: 'Rollup epic',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final rollupStory = Ticket(
          id: 'rollup-story',
          ticketId: 'AIO-31',
          type: TicketType.story,
          title: 'Rollup story',
          status: TicketStatus.backlog,
          parentId: rollupEpic.id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final rollupTask = Ticket(
          id: 'rollup-task',
          ticketId: 'AIO-32',
          type: TicketType.task,
          title: 'Rollup task',
          status: TicketStatus.backlog,
          parentId: rollupStory.id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final gap = Ticket(
          id: 'rollup-gap',
          ticketId: 'AIO-33',
          type: TicketType.knownGap,
          title: 'Grandchild gap',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final unrelatedGap = Ticket(
          id: 'unrelated-gap',
          ticketId: 'AIO-34',
          type: TicketType.knownGap,
          title: 'Unrelated gap',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        // A ticket outside `rollupEpic`'s subtree entirely — `unrelatedGap`
        // is raised on this one, not on anything under `rollupEpic`, so it
        // must not roll up onto `rollupEpic`'s section.
        final outsideTicket = Ticket(
          id: 'outside-ticket',
          ticketId: 'AIO-35',
          type: TicketType.task,
          title: 'Outside ticket',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

        when(
          () => repository.getTicketById(rollupEpic.id),
        ).thenAnswer((_) async => rollupEpic);
        when(() => repository.getAllTickets()).thenAnswer(
          (_) async => [
            rollupEpic,
            rollupStory,
            rollupTask,
            gap,
            unrelatedGap,
            outsideTicket,
          ],
        );
        when(
          () => linkRepository.getLinksForTicket(rollupEpic.id),
        ).thenAnswer((_) async => []);
        when(
          () => linkRepository.getLinksByTypes([TicketLinkType.relatesTo]),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'gap-link',
              sourceTicketId: gap.id,
              targetTicketId: rollupTask.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
            TicketLinkData(
              id: 'unrelated-link',
              sourceTicketId: unrelatedGap.id,
              targetTicketId: outsideTicket.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          ],
        );
      },
      build: buildCubit,
      seed: () => TicketDetailLoaded(
        Ticket(
          id: 'rollup-epic',
          ticketId: 'AIO-30',
          type: TicketType.epic,
          title: 'Rollup epic',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
      act: (cubit) => cubit.loadDocumentRelations('rollup-epic'),
      expect: () => [
        isA<TicketDetailLoaded>()
            .having(
              (s) => s.gapsAndOpenQuestions.map((r) => r.ticket.id),
              'gapsAndOpenQuestions ticket ids',
              ['rollup-gap'],
            )
            .having(
              (s) => s.gapsAndOpenQuestions.single.raisedOn.id,
              'gapsAndOpenQuestions raisedOn id',
              'rollup-task',
            ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'gapsAndOpenQuestions sorts directly-raised entries before '
      'rolled-up ones, each group by descending createdAt (Component '
      'Spec §2.4)',
      setUp: () {
        final sortEpic = Ticket(
          id: 'sort-epic',
          ticketId: 'AIO-36',
          type: TicketType.epic,
          title: 'Sort epic',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final sortStory = Ticket(
          id: 'sort-story',
          ticketId: 'AIO-37',
          type: TicketType.story,
          title: 'Sort story',
          status: TicketStatus.backlog,
          parentId: sortEpic.id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        // Direct entries — raised on `sortEpic` itself.
        final directOld = Ticket(
          id: 'direct-old',
          ticketId: 'AIO-38',
          type: TicketType.knownGap,
          title: 'Direct old',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
        final directNew = Ticket(
          id: 'direct-new',
          ticketId: 'AIO-39',
          type: TicketType.openQuestion,
          title: 'Direct new',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026, 6, 1),
          updatedAt: DateTime(2026, 6, 1),
        );
        // Rolled-up entries — raised on `sortStory`, a descendant.
        final rolledUpOld = Ticket(
          id: 'rolled-up-old',
          ticketId: 'AIO-40',
          type: TicketType.knownGap,
          title: 'Rolled up old',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026, 2, 1),
          updatedAt: DateTime(2026, 2, 1),
        );
        final rolledUpNew = Ticket(
          id: 'rolled-up-new',
          ticketId: 'AIO-41',
          type: TicketType.openQuestion,
          title: 'Rolled up new',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
        );

        when(
          () => repository.getTicketById(sortEpic.id),
        ).thenAnswer((_) async => sortEpic);
        when(() => repository.getAllTickets()).thenAnswer(
          (_) async => [
            sortEpic,
            sortStory,
            directOld,
            directNew,
            rolledUpOld,
            rolledUpNew,
          ],
        );
        when(
          () => linkRepository.getLinksForTicket(sortEpic.id),
        ).thenAnswer((_) async => []);
        when(
          () => linkRepository.getLinksByTypes([TicketLinkType.relatesTo]),
        ).thenAnswer(
          (_) async => [
            // Deliberately out of the expected final order, so the
            // assertion below can't pass by accident of query order.
            TicketLinkData(
              id: 'rolled-up-old-link',
              sourceTicketId: rolledUpOld.id,
              targetTicketId: sortStory.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
            TicketLinkData(
              id: 'direct-old-link',
              sourceTicketId: directOld.id,
              targetTicketId: sortEpic.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
            TicketLinkData(
              id: 'rolled-up-new-link',
              sourceTicketId: rolledUpNew.id,
              targetTicketId: sortStory.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
            TicketLinkData(
              id: 'direct-new-link',
              sourceTicketId: directNew.id,
              targetTicketId: sortEpic.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          ],
        );
      },
      build: buildCubit,
      seed: () => TicketDetailLoaded(
        Ticket(
          id: 'sort-epic',
          ticketId: 'AIO-36',
          type: TicketType.epic,
          title: 'Sort epic',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
      act: (cubit) => cubit.loadDocumentRelations('sort-epic'),
      expect: () => [
        isA<TicketDetailLoaded>().having(
          (s) => s.gapsAndOpenQuestions.map((r) => r.ticket.id),
          'gapsAndOpenQuestions ticket ids, in order',
          ['direct-new', 'direct-old', 'rolled-up-new', 'rolled-up-old'],
        ),
      ],
    );
  });

  group('createTicketLink / deleteTicketLink / updateTicketLinkType', () {
    late MockTicketLinkRepository linkRepository;

    final sourceTicket = Ticket(
      id: 'src-1',
      ticketId: 'AIO-20',
      type: TicketType.task,
      title: 'Source ticket',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final targetTicket = Ticket(
      id: 'target-1',
      ticketId: 'AIO-21',
      type: TicketType.task,
      title: 'Target ticket',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUp(() {
      linkRepository = MockTicketLinkRepository();
    });

    TicketsCubit buildCubit() =>
        TicketsCubit(repository, linkRepository: linkRepository);

    /// Stubs [loadDocumentRelations]'s own repository reads for
    /// [ticket] so the create/delete/update methods' internal refresh
    /// call doesn't throw — doesn't stub anything about the mutation
    /// itself. Also stubs the recursive gaps-and-open-questions rollup's
    /// `getAllTickets`/`getLinksByTypes` reads (empty by default) added
    /// for `aion-arch/changes/idea-gap-question-ticket-types` — every
    /// gated ticket's `loadDocumentRelations` call now performs these
    /// unconditionally alongside the pre-existing `linkedTickets`/
    /// `backlinks` reads.
    void stubDocumentRelationsRefresh(Ticket ticket) {
      when(
        () => repository.getTicketById(ticket.id),
      ).thenAnswer((_) async => ticket);
      when(
        () => linkRepository.getLinksForTicket(ticket.id),
      ).thenAnswer((_) async => []);
      when(() => repository.getAllTickets()).thenAnswer((_) async => [ticket]);
      when(
        () => linkRepository.getLinksByTypes(any()),
      ).thenAnswer((_) async => []);
    }

    group('createTicketLink', () {
      blocTest<TicketsCubit, TicketsState>(
        'creates the link, then refreshes document relations',
        setUp: () {
          when(
            () => linkRepository.createLink(
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.relatesTo,
            ),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
        },
        build: buildCubit,
        seed: () => TicketDetailLoaded(sourceTicket),
        act: (cubit) => cubit.createTicketLink(
          sourceTicket.id,
          targetTicket.id,
          TicketLinkType.relatesTo,
        ),
        expect: () => [],
        verify: (_) {
          verify(
            () => linkRepository.createLink(
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.relatesTo,
            ),
          ).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'refreshes the Board blocked-badge state for a blocks link',
        setUp: () {
          when(
            () => linkRepository.createLink(
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.blocks,
            ),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
          when(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          ).thenAnswer((_) async => []);
        },
        build: buildCubit,
        seed: () => TicketsLoaded([sourceTicket], hasMore: false),
        act: (cubit) => cubit.createTicketLink(
          sourceTicket.id,
          targetTicket.id,
          TicketLinkType.blocks,
        ),
        expect: () => [],
        verify: (_) {
          verify(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          ).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'does not refresh blocked-badge state for a relatesTo link',
        setUp: () {
          when(
            () => linkRepository.createLink(
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.relatesTo,
            ),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
        },
        build: buildCubit,
        seed: () => TicketsLoaded([sourceTicket], hasMore: false),
        act: (cubit) => cubit.createTicketLink(
          sourceTicket.id,
          targetTicket.id,
          TicketLinkType.relatesTo,
        ),
        expect: () => [],
        verify: (_) {
          verifyNever(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          );
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'no-ops when constructed without a TicketLinkRepository',
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.createTicketLink(
          sourceTicket.id,
          targetTicket.id,
          TicketLinkType.relatesTo,
        ),
        expect: () => [],
        verify: (_) {
          verifyNever(() => repository.getTicketById(any()));
        },
      );
    });

    group('deleteTicketLink', () {
      blocTest<TicketsCubit, TicketsState>(
        'deletes the row, then refreshes document relations',
        setUp: () {
          when(() => linkRepository.getLinkById('link-1')).thenAnswer(
            (_) async => TicketLinkData(
              id: 'link-1',
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          );
          when(
            () => linkRepository.deleteLink('link-1'),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
        },
        build: buildCubit,
        seed: () => TicketDetailLoaded(sourceTicket),
        act: (cubit) => cubit.deleteTicketLink(sourceTicket.id, 'link-1'),
        expect: () => [],
        verify: (_) {
          verify(() => linkRepository.deleteLink('link-1')).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'refreshes blocked-badge state when the deleted link was blocks/'
        'blockedBy',
        setUp: () {
          when(() => linkRepository.getLinkById('link-1')).thenAnswer(
            (_) async => TicketLinkData(
              id: 'link-1',
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.blocks.name,
            ),
          );
          when(
            () => linkRepository.deleteLink('link-1'),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
          when(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          ).thenAnswer((_) async => []);
        },
        build: buildCubit,
        seed: () => TicketsLoaded([sourceTicket], hasMore: false),
        act: (cubit) => cubit.deleteTicketLink(sourceTicket.id, 'link-1'),
        expect: () => [],
        verify: (_) {
          verify(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          ).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'does not refresh blocked-badge state for a relatesTo/duplicates '
        'link',
        setUp: () {
          when(() => linkRepository.getLinkById('link-1')).thenAnswer(
            (_) async => TicketLinkData(
              id: 'link-1',
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.duplicates.name,
            ),
          );
          when(
            () => linkRepository.deleteLink('link-1'),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
        },
        build: buildCubit,
        seed: () => TicketDetailLoaded(sourceTicket),
        act: (cubit) => cubit.deleteTicketLink(sourceTicket.id, 'link-1'),
        expect: () => [],
        verify: (_) {
          verifyNever(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          );
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'no-ops when constructed without a TicketLinkRepository',
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.deleteTicketLink(sourceTicket.id, 'link-1'),
        expect: () => [],
        verify: (_) {
          verifyNever(() => repository.getTicketById(any()));
        },
      );
    });

    group('updateTicketLinkType', () {
      blocTest<TicketsCubit, TicketsState>(
        "translates the relative selection to canonical (viewing ticket "
        "is the row's target)",
        setUp: () {
          // sourceTicket is the row's TARGET here, so a "blocks" relative
          // selection (as picked from sourceTicket's own side) must be
          // persisted as its inverse, "blockedBy".
          when(() => linkRepository.getLinkById('link-1')).thenAnswer(
            (_) async => TicketLinkData(
              id: 'link-1',
              sourceTicketId: targetTicket.id,
              targetTicketId: sourceTicket.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          );
          when(
            () => linkRepository.updateLinkType(
              'link-1',
              TicketLinkType.blockedBy,
            ),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
          when(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          ).thenAnswer((_) async => []);
        },
        build: buildCubit,
        seed: () => TicketsLoaded([sourceTicket], hasMore: false),
        act: (cubit) => cubit.updateTicketLinkType(
          sourceTicket.id,
          'link-1',
          TicketLinkType.blocks,
        ),
        expect: () => [],
        verify: (_) {
          verify(
            () => linkRepository.updateLinkType(
              'link-1',
              TicketLinkType.blockedBy,
            ),
          ).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'persists the relative selection unchanged when the viewing '
        "ticket is the row's source",
        setUp: () {
          when(() => linkRepository.getLinkById('link-1')).thenAnswer(
            (_) async => TicketLinkData(
              id: 'link-1',
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          );
          when(
            () => linkRepository.updateLinkType(
              'link-1',
              TicketLinkType.duplicates,
            ),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
        },
        build: buildCubit,
        seed: () => TicketDetailLoaded(sourceTicket),
        act: (cubit) => cubit.updateTicketLinkType(
          sourceTicket.id,
          'link-1',
          TicketLinkType.duplicates,
        ),
        expect: () => [],
        verify: (_) {
          verify(
            () => linkRepository.updateLinkType(
              'link-1',
              TicketLinkType.duplicates,
            ),
          ).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'refreshes blocked-badge state when the OLD type was blocking',
        setUp: () {
          when(() => linkRepository.getLinkById('link-1')).thenAnswer(
            (_) async => TicketLinkData(
              id: 'link-1',
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.blocks.name,
            ),
          );
          when(
            () => linkRepository.updateLinkType(
              'link-1',
              TicketLinkType.relatesTo,
            ),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
          when(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          ).thenAnswer((_) async => []);
        },
        build: buildCubit,
        seed: () => TicketsLoaded([sourceTicket], hasMore: false),
        act: (cubit) => cubit.updateTicketLinkType(
          sourceTicket.id,
          'link-1',
          TicketLinkType.relatesTo,
        ),
        expect: () => [],
        verify: (_) {
          verify(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          ).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'refreshes blocked-badge state when the NEW type is blocking',
        setUp: () {
          when(() => linkRepository.getLinkById('link-1')).thenAnswer(
            (_) async => TicketLinkData(
              id: 'link-1',
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          );
          when(
            () =>
                linkRepository.updateLinkType('link-1', TicketLinkType.blocks),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
          when(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          ).thenAnswer((_) async => []);
        },
        build: buildCubit,
        seed: () => TicketsLoaded([sourceTicket], hasMore: false),
        act: (cubit) => cubit.updateTicketLinkType(
          sourceTicket.id,
          'link-1',
          TicketLinkType.blocks,
        ),
        expect: () => [],
        verify: (_) {
          verify(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          ).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'does not refresh blocked-badge state when neither old nor new '
        'type is blocking',
        setUp: () {
          when(() => linkRepository.getLinkById('link-1')).thenAnswer(
            (_) async => TicketLinkData(
              id: 'link-1',
              sourceTicketId: sourceTicket.id,
              targetTicketId: targetTicket.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          );
          when(
            () => linkRepository.updateLinkType(
              'link-1',
              TicketLinkType.duplicates,
            ),
          ).thenAnswer((_) async {});
          stubDocumentRelationsRefresh(sourceTicket);
        },
        build: buildCubit,
        seed: () => TicketDetailLoaded(sourceTicket),
        act: (cubit) => cubit.updateTicketLinkType(
          sourceTicket.id,
          'link-1',
          TicketLinkType.duplicates,
        ),
        expect: () => [],
        verify: (_) {
          verifyNever(
            () => linkRepository.getLinksByTypes([
              TicketLinkType.blocks,
              TicketLinkType.blockedBy,
            ]),
          );
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'no-ops when constructed without a TicketLinkRepository',
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketLinkType(
          sourceTicket.id,
          'link-1',
          TicketLinkType.blocks,
        ),
        expect: () => [],
        verify: (_) {
          verifyNever(() => repository.getTicketById(any()));
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'no-ops when the link id no longer exists',
        setUp: () {
          when(
            () => linkRepository.getLinkById('missing'),
          ).thenAnswer((_) async => null);
        },
        build: buildCubit,
        act: (cubit) => cubit.updateTicketLinkType(
          sourceTicket.id,
          'missing',
          TicketLinkType.blocks,
        ),
        expect: () => [],
        verify: (_) {
          verifyNever(() => linkRepository.updateLinkType(any(), any()));
        },
      );
    });
  });

  group('advanceSddStage', () {
    late MockAgentModelClient agentClient;
    late MockProviderRegistry registry;
    late MockCommentRepository commentRepository;
    late MockTicketLinkRepository linkRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
      registry = buildProviderStack(agentClient).registry;
      commentRepository = MockCommentRepository();
      linkRepository = MockTicketLinkRepository();
      when(
        () => linkRepository.getLinksForTicket(any()),
      ).thenAnswer((_) async => []);
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      providerRegistry: registry,
      commentRepository: commentRepository,
      linkRepository: linkRepository,
    );

    blocTest<TicketsCubit, TicketsState>(
      'rejects a non-epic/story ticket type without calling the repository',
      setUp: () {
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(ticket),
      verify: (_) {
        verifyNever(() => repository.updateTicketSddStage(any(), any()));
      },
      expect: () => [
        const TicketsError(
          '',
          reason: TicketsErrorReason.sddStagePreconditionNotMet,
        ),
        TicketDetailLoaded(ticket),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'rejects proposed to verifying when a child Task is not done',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyProposed.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => [taskChildDone, taskChildNotDone]);
        when(
          () => repository.getTicketById(storyProposed.id),
        ).thenAnswer((_) async => storyProposed);
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyProposed),
      verify: (_) {
        verifyNever(() => repository.updateTicketSddStage(any(), any()));
      },
      expect: () => [
        const TicketsError(
          '',
          reason: TicketsErrorReason.sddStagePreconditionNotMet,
        ),
        TicketDetailLoaded(storyProposed),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'persists the next stage and spawns a chat ticket once the '
      'precondition is met, falling back to the first registered '
      'provider\'s first model when no '
      'ModelRoutingRepository was supplied',
      setUp: () {
        final advancedEpic = Ticket(
          id: epic.id,
          ticketId: epic.ticketId,
          type: epic.type,
          title: epic.title,
          status: epic.status,
          sddStage: SddStage.exploring,
          createdAt: epic.createdAt,
          updatedAt: epic.updatedAt,
        );
        when(
          () => repository.updateTicketSddStage(epic.id, SddStage.exploring),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(
          () => repository.getTicketById(epic.id),
        ).thenAnswer((_) async => advancedEpic);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => commentRepository.addComment(any()),
        ).thenAnswer((_) async {});
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(epic),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => repository.updateTicketSddStage(epic.id, SddStage.exploring),
        ).called(1);
        verify(() => repository.createTicket(any())).called(1);
        verify(() => commentRepository.addComment(any())).called(1);
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>(
                (request) => request.model == _sonnet.modelId,
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'includes a "## Related tickets" section in the spawned stage '
      'chat\'s prompt when TicketContextEnricher has content to '
      'contribute',
      setUp: () {
        final relatedStory = Ticket(
          id: 'stage-related',
          ticketId: 'AIO-98',
          type: TicketType.story,
          title: 'A related story',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => repository.updateTicketSddStage(epic.id, SddStage.exploring),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(
          () => repository.getTicketById(epic.id),
        ).thenAnswer((_) async => epic);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => commentRepository.addComment(any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [epic, relatedStory]);
        when(() => linkRepository.getLinksForTicket(epic.id)).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'stage-link',
              sourceTicketId: epic.id,
              targetTicketId: relatedStory.id,
              linkType: TicketLinkType.relatesTo.name,
            ),
          ],
        );
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(epic),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>(
                (request) =>
                    request.prompt.contains('## Related tickets') &&
                    request.prompt.contains('A related story'),
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'omits the "## Related tickets" section entirely — preserving '
      "today's exact prompt — when TicketContextEnricher has nothing to "
      'contribute',
      setUp: () {
        when(
          () => repository.updateTicketSddStage(epic.id, SddStage.exploring),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(
          () => repository.getTicketById(epic.id),
        ).thenAnswer((_) async => epic);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => commentRepository.addComment(any()),
        ).thenAnswer((_) async {});
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(epic),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>(
                (request) =>
                    !request.prompt.contains('## Related tickets') &&
                    request.prompt.trim() == '# ${epic.title}',
              ),
            ),
          ),
        ).called(1);
      },
    );
  });

  group('advanceSddStage — design gate (designBrief/designSync)', () {
    late MockAgentModelClient agentClient;
    late MockProviderRegistry registry;
    late MockCommentRepository commentRepository;
    late MockTicketLinkRepository linkRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
      registry = buildProviderStack(agentClient).registry;
      commentRepository = MockCommentRepository();
      linkRepository = MockTicketLinkRepository();
      when(
        () => agentClient.run(any()),
      ).thenAnswer((_) async => Stream.fromIterable(const [AgentDoneEvent()]));
      when(() => commentRepository.addComment(any())).thenAnswer((_) async {});
      when(() => repository.createTicket(any())).thenAnswer((_) async {});
      when(
        () => linkRepository.createLink(
          sourceTicketId: any(named: 'sourceTicketId'),
          targetTicketId: any(named: 'targetTicketId'),
          linkType: any(named: 'linkType'),
        ),
      ).thenAnswer((_) async {});
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      linkRepository: linkRepository,
      providerRegistry: registry,
      commentRepository: commentRepository,
    );

    blocTest<TicketsCubit, TicketsState>(
      'proposed advances to designBrief (not verifying) when a done child '
      'Task title indicates UI work, and creates+links the design Page',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyProposed.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => [taskChildUi]);
        when(
          () => repository.updateTicketSddStage(
            storyProposed.id,
            SddStage.designBrief,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(() => repository.getTicketById(storyProposed.id)).thenAnswer(
          (_) async => Ticket(
            id: storyProposed.id,
            ticketId: storyProposed.ticketId,
            type: storyProposed.type,
            title: storyProposed.title,
            status: storyProposed.status,
            sddStage: SddStage.designBrief,
            createdAt: storyProposed.createdAt,
            updatedAt: storyProposed.updatedAt,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyProposed),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => repository.updateTicketSddStage(
            storyProposed.id,
            SddStage.designBrief,
          ),
        ).called(1);
        // Once for the design Page, once for the spawned chat.
        verify(() => repository.createTicket(any())).called(2);
        verify(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: storyProposed.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'proposed advances to designBrief even when the UI-indicating child '
      'Task is not done yet — T12 regression: designBrief/designSync must '
      'run before code, so "Tasks exist" (not "Tasks done") gates this '
      'transition',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyProposed.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer(
          (_) async => [taskChildUi.copyWith(status: TicketStatus.todo)],
        );
        when(
          () => repository.updateTicketSddStage(
            storyProposed.id,
            SddStage.designBrief,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(() => repository.getTicketById(storyProposed.id)).thenAnswer(
          (_) async => Ticket(
            id: storyProposed.id,
            ticketId: storyProposed.ticketId,
            type: storyProposed.type,
            title: storyProposed.title,
            status: storyProposed.status,
            sddStage: SddStage.designBrief,
            createdAt: storyProposed.createdAt,
            updatedAt: storyProposed.updatedAt,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyProposed),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => repository.updateTicketSddStage(
            storyProposed.id,
            SddStage.designBrief,
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'proposed advances straight to verifying (skips designBrief) when no '
      'done child Task title indicates UI work',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyProposed.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => [taskChildDone]);
        when(
          () => repository.updateTicketSddStage(
            storyProposed.id,
            SddStage.verifying,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(
          () => repository.getTicketById(storyProposed.id),
        ).thenAnswer((_) async => storyProposed);
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyProposed),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => repository.updateTicketSddStage(
            storyProposed.id,
            SddStage.verifying,
          ),
        ).called(1);
        // Only the spawned chat — no design Page for a skipped Story.
        verify(() => repository.createTicket(any())).called(1);
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'proposed advancing to designBrief skips creating an orphan design '
      'Page when no TicketLinkRepository was provided',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyProposed.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => [taskChildUi]);
        when(
          () => repository.updateTicketSddStage(
            storyProposed.id,
            SddStage.designBrief,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(() => repository.getTicketById(storyProposed.id)).thenAnswer(
          (_) async => Ticket(
            id: storyProposed.id,
            ticketId: storyProposed.ticketId,
            type: storyProposed.type,
            title: storyProposed.title,
            status: storyProposed.status,
            sddStage: SddStage.designBrief,
            createdAt: storyProposed.createdAt,
            updatedAt: storyProposed.updatedAt,
          ),
        );
      },
      // No linkRepository this time — only providerRegistry/commentRepository.
      build: () => TicketsCubit(
        repository,
        providerRegistry: registry,
        commentRepository: commentRepository,
      ),
      act: (cubit) => cubit.advanceSddStage(storyProposed),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        // Only the spawned chat — no orphan design Page without a way
        // to link it.
        verify(() => repository.createTicket(any())).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'designBrief rejects advancing when no linked design Page has '
      'content yet',
      setUp: () {
        when(
          () => linkRepository.getLinksForTicket(storyDesignBrief.id),
        ).thenAnswer((_) async => []);
        when(
          () => repository.getTicketById(storyDesignBrief.id),
        ).thenAnswer((_) async => storyDesignBrief);
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyDesignBrief),
      verify: (_) {
        verifyNever(() => repository.updateTicketSddStage(any(), any()));
      },
      expect: () => [
        const TicketsError(
          '',
          reason: TicketsErrorReason.sddStagePreconditionNotMet,
        ),
        TicketDetailLoaded(storyDesignBrief),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'designBrief rejects advancing when the linked design Page exists '
      'but is still empty',
      setUp: () {
        when(
          () => linkRepository.getLinksForTicket(storyDesignBrief.id),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-empty',
              sourceTicketId: designPageEmpty.id,
              targetTicketId: storyDesignBrief.id,
              linkType: 'relatesTo',
            ),
          ],
        );
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(
          () => repository.getTicketById(designPageEmpty.id),
        ).thenAnswer((_) async => designPageEmpty);
        when(
          () => repository.getTicketById(storyDesignBrief.id),
        ).thenAnswer((_) async => storyDesignBrief);
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyDesignBrief),
      verify: (_) {
        verifyNever(() => repository.updateTicketSddStage(any(), any()));
      },
      expect: () => [
        const TicketsError(
          '',
          reason: TicketsErrorReason.sddStagePreconditionNotMet,
        ),
        TicketDetailLoaded(storyDesignBrief),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'designBrief advances to designSync once the linked design Page has '
      'content',
      setUp: () {
        when(
          () => linkRepository.getLinksForTicket(storyDesignBrief.id),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: designPageFilled.id,
              targetTicketId: storyDesignBrief.id,
              linkType: 'relatesTo',
            ),
          ],
        );
        when(
          () => repository.updateTicketSddStage(
            storyDesignBrief.id,
            SddStage.designSync,
          ),
        ).thenAnswer((_) async {});
        // Registered least-specific first — mocktail resolves overlapping
        // stubs last-registered-wins, so the two id-specific overrides
        // below must come after this catch-all, not before.
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(
          () => repository.getTicketById(designPageFilled.id),
        ).thenAnswer((_) async => designPageFilled);
        when(() => repository.getTicketById(storyDesignBrief.id)).thenAnswer(
          (_) async => Ticket(
            id: storyDesignBrief.id,
            ticketId: storyDesignBrief.ticketId,
            type: storyDesignBrief.type,
            title: storyDesignBrief.title,
            status: storyDesignBrief.status,
            sddStage: SddStage.designSync,
            createdAt: storyDesignBrief.createdAt,
            updatedAt: storyDesignBrief.updatedAt,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyDesignBrief),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => repository.updateTicketSddStage(
            storyDesignBrief.id,
            SddStage.designSync,
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'designSync rejects advancing when the most recent reply says '
      'DESIGN GATE: PENDING',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyDesignSync.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => [designSyncChat]);
        when(
          () => commentRepository.getCommentsForTicket(designSyncChat.id),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c1',
              ticketId: designSyncChat.id,
              content: 'Found one issue.\n\nDESIGN GATE: PENDING',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(
          () => repository.getTicketById(storyDesignSync.id),
        ).thenAnswer((_) async => storyDesignSync);
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyDesignSync),
      verify: (_) {
        verifyNever(() => repository.updateTicketSddStage(any(), any()));
      },
      expect: () => [
        const TicketsError(
          '',
          reason: TicketsErrorReason.sddStagePreconditionNotMet,
        ),
        TicketDetailLoaded(storyDesignSync),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'designSync advances to verifying when the most recent reply says '
      'DESIGN GATE: APPROVED',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyDesignSync.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChat]);
        // T12's fix additionally requires every child Task to be done
        // before designSync -> verifying is allowed.
        when(
          () => repository.getTicketsByParent(
            storyDesignSync.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskChildDone]);
        when(
          () => commentRepository.getCommentsForTicket(designSyncChat.id),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c2',
              ticketId: designSyncChat.id,
              content: 'No issues found.\n\nDESIGN GATE: APPROVED',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(
          () => repository.updateTicketSddStage(
            storyDesignSync.id,
            SddStage.verifying,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(
          () => repository.getTicketById(storyDesignSync.id),
        ).thenAnswer((_) async => storyDesignSync);
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyDesignSync),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => repository.updateTicketSddStage(
            storyDesignSync.id,
            SddStage.verifying,
          ),
        ).called(1);
      },
    );
  });

  group('advanceSddStage — backgrounded stage-chat turn', () {
    late MockAgentModelClient agentClient;
    late MockProviderRegistry registry;
    late MockCommentRepository commentRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
      registry = buildProviderStack(agentClient).registry;
      commentRepository = MockCommentRepository();
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      providerRegistry: registry,
      commentRepository: commentRepository,
    );

    void stubHappyPath({required Completer<Stream<AgentEvent>> pauseOn}) {
      final advancedEpic = Ticket(
        id: epic.id,
        ticketId: epic.ticketId,
        type: epic.type,
        title: epic.title,
        status: epic.status,
        sddStage: SddStage.exploring,
        createdAt: epic.createdAt,
        updatedAt: epic.updatedAt,
      );
      when(
        () => repository.updateTicketSddStage(epic.id, SddStage.exploring),
      ).thenAnswer((_) async {});
      when(
        () => repository.getTicketById(any()),
      ).thenAnswer((_) async => dummyChatTicket);
      when(
        () => repository.getTicketById(epic.id),
      ).thenAnswer((_) async => advancedEpic);
      when(() => repository.createTicket(any())).thenAnswer((_) async {});
      when(() => commentRepository.addComment(any())).thenAnswer((_) async {});
      when(() => agentClient.run(any())).thenAnswer((_) => pauseOn.future);
    }

    test(
      'returns the spawned chat id before the stage-chat turn resolves',
      () async {
        final pauseOn = Completer<Stream<AgentEvent>>();
        stubHappyPath(pauseOn: pauseOn);
        final cubit = buildCubit();
        addTearDown(cubit.close);

        final chatId = await cubit.advanceSddStage(epic);

        expect(chatId, dummyChatTicket.id);
        // The stubbed agentClient.run call is still pending — proves
        // advanceSddStage didn't wait on it.
        expect(pauseOn.isCompleted, isFalse);
        pauseOn.complete(Stream.fromIterable(const [AgentDoneEvent()]));
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'a second call for a ticket already mid-advance no-ops without '
      'creating another chat ticket',
      setUp: () {
        stubHappyPath(pauseOn: Completer<Stream<AgentEvent>>());
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.advanceSddStage(epic);
        final secondResult = await cubit.advanceSddStage(epic);
        expect(secondResult, isNull);
      },
      verify: (_) {
        verify(() => repository.createTicket(any())).called(1);
      },
    );

    final hardFailurePostedComments = <TicketComment>[];
    blocTest<TicketsCubit, TicketsState>(
      "_runStageChatTurn's hard-failure path posts a "
      '"Stage advance failed: " comment and emits sddStageAdvanceFailed, '
      'clearing _inFlightStageAdvanceIds',
      setUp: () {
        hardFailurePostedComments.clear();
        final advancedEpic = Ticket(
          id: epic.id,
          ticketId: epic.ticketId,
          type: epic.type,
          title: epic.title,
          status: epic.status,
          sddStage: SddStage.exploring,
          createdAt: epic.createdAt,
          updatedAt: epic.updatedAt,
        );
        when(
          () => repository.updateTicketSddStage(epic.id, SddStage.exploring),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(
          () => repository.getTicketById(epic.id),
        ).thenAnswer((_) async => advancedEpic);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => repository.getTicketsByParent(
            epic.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [dummyChatTicket]);
        // The agent turn itself succeeds with text — ChatCubit.runChatTurn
        // already swallows an agentClient.run failure internally (posting
        // its own "Execution failed: ..." comment and returning `false`,
        // never rethrowing), so _runStageChatTurn's own catch can only
        // ever fire for a failure *outside* that scope — here, the
        // ai-reply comment write itself throwing (e.g. a DB failure).
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Reply text'),
            AgentDoneEvent(),
          ]),
        );
        var addCommentCallCount = 0;
        when(() => commentRepository.addComment(any())).thenAnswer((
          invocation,
        ) async {
          addCommentCallCount++;
          if (addCommentCallCount == 2) {
            throw Exception('boom');
          }
          hardFailurePostedComments.add(
            invocation.positionalArguments[0] as TicketComment,
          );
        });
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(epic),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<TicketDetailLoaded>().having(
          (s) => s.isAdvancingStage,
          'isAdvancingStage',
          true,
        ),
        const TicketsError(
          '',
          reason: TicketsErrorReason.sddStageAdvanceFailed,
        ),
      ],
      verify: (_) {
        verify(() => commentRepository.addComment(any())).called(3);
        expect(
          hardFailurePostedComments.last.content,
          startsWith('Stage advance failed: '),
        );
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      '_inFlightStageAdvanceIds is cleared on the success path too — a '
      'subsequent getTicketById reports isAdvancingStage false',
      setUp: () {
        stubHappyPath(
          pauseOn: Completer<Stream<AgentEvent>>()
            ..complete(Stream.fromIterable(const [AgentDoneEvent()])),
        );
        when(
          () => repository.getTicketsByParent(
            epic.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => <Ticket>[]);
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.advanceSddStage(epic);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await cubit.getTicketById(epic.id);
      },
      verify: (_) {},
      // No intervening TicketsLoading — the trailing getTicketById(epic.id)
      // re-enters for the ticket already shown, which getTicketById's
      // same-id Loading-skip now covers (added for
      // `aion-arch/changes/live-refresh-open-ticket-detail-screen`).
      expect: () => [
        isA<TicketDetailLoaded>().having(
          (s) => s.isAdvancingStage,
          'isAdvancingStage',
          true,
        ),
        isA<TicketDetailLoaded>().having(
          (s) => s.isAdvancingStage,
          'isAdvancingStage',
          false,
        ),
      ],
    );
  });

  group('retryDesignSync', () {
    late MockAgentModelClient agentClient;
    late MockProviderRegistry registry;
    late MockCommentRepository commentRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
      registry = buildProviderStack(agentClient).registry;
      commentRepository = MockCommentRepository();
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      providerRegistry: registry,
      commentRepository: commentRepository,
    );

    blocTest<TicketsCubit, TicketsState>(
      'no-ops for a non-chat ticket',
      build: buildCubit,
      act: (cubit) => cubit.retryDesignSync(storyDesignSync),
      verify: (_) {
        verifyNever(() => commentRepository.addComment(any()));
        verifyNever(() => agentClient.run(any()));
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      "no-ops when the chat's parent isn't at SddStage.designSync",
      setUp: () {
        when(
          () => repository.getTicketById(storyProposed.id),
        ).thenAnswer((_) async => storyProposed);
      },
      build: buildCubit,
      act: (cubit) => cubit.retryDesignSync(
        Ticket(
          id: designSyncChat.id,
          ticketId: designSyncChat.ticketId,
          type: TicketType.chat,
          title: designSyncChat.title,
          status: designSyncChat.status,
          parentId: storyProposed.id,
          createdAt: designSyncChat.createdAt,
          updatedAt: designSyncChat.updatedAt,
        ),
      ),
      verify: (_) {
        verifyNever(() => commentRepository.addComment(any()));
        verifyNever(() => agentClient.run(any()));
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'posts fresh context and calls the agent when the parent is at '
      'SddStage.designSync',
      setUp: () {
        when(
          () => repository.getTicketById(storyDesignSync.id),
        ).thenAnswer((_) async => storyDesignSync);
        // _toolsFor (mid-task-chat-branching) reads the chat itself first
        // to resolve its own parent's type.
        when(
          () => repository.getTicketById(designSyncChat.id),
        ).thenAnswer((_) async => designSyncChat);
        when(
          () => commentRepository.addComment(any()),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) => cubit.retryDesignSync(designSyncChat),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        // The context comment retryDesignSync itself posts, plus
        // runChatTurn's own failure comment — agentClient.run isn't
        // stubbed here, so it throws and the run fails, which (since
        // T4) now persists a trace instead of silently dropping it.
        verify(() => commentRepository.addComment(any())).called(2);
        verify(() => agentClient.run(any())).called(1);
      },
      expect: () => <TicketsState>[],
    );
  });

  group('chat branching (mid-task-chat-branching)', () {
    late MockCommentRepository commentRepository;
    late MockAutomationSettingsRepository automationSettingsRepository;
    Map<String, dynamic>? result;

    // rootChat: parented by `ticket` (a task) — not itself a branch, so
    // it can be branched. branchChat: parented by rootChat (a chat) — a
    // branch, so it can be closed but not branched further. parentlessChat:
    // no parent (mirrors an Inbox-spawned chat) — can neither be branched
    // nor closed.
    final rootChat = Ticket(
      id: 'branch-root-chat',
      ticketId: 'AIO-30',
      type: TicketType.chat,
      title: 'Root chat',
      status: TicketStatus.backlog,
      parentId: ticket.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final branchChat = Ticket(
      id: 'branch-child-chat',
      ticketId: 'AIO-31',
      type: TicketType.chat,
      title: 'Branch chat',
      status: TicketStatus.backlog,
      parentId: rootChat.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final parentlessChat = Ticket(
      id: 'branch-parentless-chat',
      ticketId: 'AIO-32',
      type: TicketType.chat,
      title: 'Parentless chat',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUp(() {
      commentRepository = MockCommentRepository();
      automationSettingsRepository = MockAutomationSettingsRepository();
      result = null;
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      commentRepository: commentRepository,
      automationSettingsRepository: automationSettingsRepository,
    );

    group('_canBranch depth cap (via branch_ticket)', () {
      blocTest<TicketsCubit, TicketsState>(
        'a root chat (parent is not a chat) can be branched',
        setUp: () {
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
          when(
            () => automationSettingsRepository.getConfidence(
              AutomationContext.chatBranching,
            ),
          ).thenAnswer((_) async => AutomationConfidence.auto);
          when(() => repository.createTicket(any())).thenAnswer((_) async {});
        },
        build: buildCubit,
        act: (cubit) async {
          result = await cubit.handleChatToolCall(
            rootChat,
            'call-1',
            'branch_ticket',
            {'title': 'Sub-issue'},
          );
        },
        verify: (_) {
          expect(result?['accepted'], true);
          verify(() => repository.createTicket(any())).called(1);
        },
        expect: () => <TicketsState>[],
      );

      blocTest<TicketsCubit, TicketsState>(
        'a branch chat (parent is itself a chat) cannot be branched '
        'further, without ever checking automation confidence',
        setUp: () {
          when(
            () => repository.getTicketById(rootChat.id),
          ).thenAnswer((_) async => rootChat);
        },
        build: buildCubit,
        act: (cubit) async {
          result = await cubit.handleChatToolCall(
            branchChat,
            'call-1',
            'branch_ticket',
            {'title': 'Sub-issue'},
          );
        },
        verify: (_) {
          expect(result, {
            'accepted': false,
            'reason': 'Already at branch depth cap.',
          });
          verifyNever(() => repository.createTicket(any()));
          verifyNever(
            () => automationSettingsRepository.getConfidence(
              AutomationContext.chatBranching,
            ),
          );
        },
        expect: () => <TicketsState>[],
      );

      blocTest<TicketsCubit, TicketsState>(
        'a parentless chat (e.g. Inbox-spawned) cannot be branched',
        build: buildCubit,
        act: (cubit) async {
          result = await cubit.handleChatToolCall(
            parentlessChat,
            'call-1',
            'branch_ticket',
            {'title': 'Sub-issue'},
          );
        },
        verify: (_) {
          expect(result, {
            'accepted': false,
            'reason': 'Already at branch depth cap.',
          });
          verifyNever(() => repository.createTicket(any()));
        },
        expect: () => <TicketsState>[],
      );
    });

    group(
      'AutomationContext.chatBranching confidence branches — branch_ticket',
      () {
        setUp(() {
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => ticket);
        });

        blocTest<TicketsCubit, TicketsState>(
          'manual declines outright',
          setUp: () {
            when(
              () => automationSettingsRepository.getConfidence(
                AutomationContext.chatBranching,
              ),
            ).thenAnswer((_) async => AutomationConfidence.manual);
          },
          build: buildCubit,
          act: (cubit) async {
            result = await cubit.handleChatToolCall(
              rootChat,
              'call-1',
              'branch_ticket',
              {'title': 'Sub-issue'},
            );
          },
          verify: (_) {
            expect(result, {
              'accepted': false,
              'reason': 'Automation set to manual.',
            });
            verifyNever(() => repository.createTicket(any()));
          },
          expect: () => <TicketsState>[],
        );

        blocTest<TicketsCubit, TicketsState>(
          'auto creates the branch chat immediately',
          setUp: () {
            when(
              () => automationSettingsRepository.getConfidence(
                AutomationContext.chatBranching,
              ),
            ).thenAnswer((_) async => AutomationConfidence.auto);
            when(() => repository.createTicket(any())).thenAnswer((_) async {});
          },
          build: buildCubit,
          act: (cubit) async {
            result = await cubit.handleChatToolCall(
              rootChat,
              'call-1',
              'branch_ticket',
              {'title': 'Sub-issue', 'description': 'Why'},
            );
          },
          verify: (_) {
            expect(result?['accepted'], true);
            expect(result?['childChatId'], isA<String>());
            final created = verify(
              () => repository.createTicket(captureAny()),
            ).captured;
            expect(created, hasLength(1));
            final createdTicket = created.single as Ticket;
            expect(createdTicket.type, TicketType.chat);
            expect(createdTicket.parentId, rootChat.id);
            expect(createdTicket.title, 'Sub-issue');
            expect(createdTicket.description, 'Why');
          },
          expect: () => <TicketsState>[],
        );

        blocTest<TicketsCubit, TicketsState>(
          'gated surfaces a BranchProposal and pauses until confirmed/rejected',
          setUp: () {
            when(
              () => automationSettingsRepository.getConfidence(
                AutomationContext.chatBranching,
              ),
            ).thenAnswer((_) async => AutomationConfidence.gated);
            when(() => repository.createTicket(any())).thenAnswer((_) async {});
          },
          build: buildCubit,
          act: (cubit) async {
            unawaited(
              cubit
                  .handleChatToolCall(rootChat, 'call-1', 'branch_ticket', {
                    'title': 'Sub-issue',
                  })
                  .then((value) => result = value),
            );
            await Future<void>.delayed(Duration.zero);
          },
          verify: (_) {
            verifyNever(() => repository.createTicket(any()));
            expect(result, isNull); // still pending — no confirm/reject yet
          },
          expect: () => [
            isA<TicketDetailLoaded>()
                .having((s) => s.ticket.id, 'ticket.id', rootChat.id)
                .having(
                  (s) => s.pendingToolProposal,
                  'pendingToolProposal',
                  const BranchProposal(title: 'Sub-issue'),
                ),
          ],
        );
      },
    );

    group(
      'AutomationContext.chatBranching confidence branches — close_branch',
      () {
        setUp(() {
          when(
            () => repository.getTicketById(rootChat.id),
          ).thenAnswer((_) async => rootChat);
        });

        blocTest<TicketsCubit, TicketsState>(
          'manual declines outright',
          setUp: () {
            when(
              () => automationSettingsRepository.getConfidence(
                AutomationContext.chatBranching,
              ),
            ).thenAnswer((_) async => AutomationConfidence.manual);
          },
          build: buildCubit,
          act: (cubit) async {
            result = await cubit.handleChatToolCall(
              branchChat,
              'call-1',
              'close_branch',
              {'summary': 'Fixed it'},
            );
          },
          verify: (_) {
            expect(result, {
              'accepted': false,
              'reason': 'Automation set to manual.',
            });
            verifyNever(() => repository.updateTicketStatus(any(), any()));
            verifyNever(() => commentRepository.addComment(any()));
          },
          expect: () => <TicketsState>[],
        );

        blocTest<TicketsCubit, TicketsState>(
          'auto folds the resolution into the parent and closes the '
          'branch immediately',
          setUp: () {
            when(
              () => automationSettingsRepository.getConfidence(
                AutomationContext.chatBranching,
              ),
            ).thenAnswer((_) async => AutomationConfidence.auto);
            when(
              () => repository.updateTicketStatus(
                branchChat.id,
                TicketStatus.done,
              ),
            ).thenAnswer((_) async {});
            when(
              () => commentRepository.addComment(any()),
            ).thenAnswer((_) async {});
          },
          build: buildCubit,
          act: (cubit) async {
            result = await cubit.handleChatToolCall(
              branchChat,
              'call-1',
              'close_branch',
              {'summary': 'Fixed it'},
            );
          },
          verify: (_) {
            expect(result, {'accepted': true});
            verify(
              () => repository.updateTicketStatus(
                branchChat.id,
                TicketStatus.done,
              ),
            ).called(1);
            final posted = verify(
              () => commentRepository.addComment(captureAny()),
            ).captured;
            expect(posted, hasLength(1));
            final postedComment = posted.single as TicketComment;
            expect(postedComment.ticketId, rootChat.id);
            expect(postedComment.content, 'Fixed it');
            expect(postedComment.authorType, CommentAuthorType.system);
          },
          expect: () => <TicketsState>[],
        );

        blocTest<TicketsCubit, TicketsState>(
          'gated surfaces a CloseBranchProposal and pauses until '
          'confirmed/rejected',
          setUp: () {
            when(
              () => automationSettingsRepository.getConfidence(
                AutomationContext.chatBranching,
              ),
            ).thenAnswer((_) async => AutomationConfidence.gated);
            when(
              () => repository.updateTicketStatus(
                branchChat.id,
                TicketStatus.done,
              ),
            ).thenAnswer((_) async {});
            when(
              () => commentRepository.addComment(any()),
            ).thenAnswer((_) async {});
          },
          build: buildCubit,
          act: (cubit) async {
            unawaited(
              cubit
                  .handleChatToolCall(branchChat, 'call-1', 'close_branch', {
                    'summary': 'Fixed it',
                  })
                  .then((value) => result = value),
            );
            await Future<void>.delayed(Duration.zero);
          },
          verify: (_) {
            verifyNever(() => repository.updateTicketStatus(any(), any()));
            expect(result, isNull); // still pending — no confirm/reject yet
          },
          expect: () => [
            isA<TicketDetailLoaded>()
                .having((s) => s.ticket.id, 'ticket.id', branchChat.id)
                .having(
                  (s) => s.pendingToolProposal,
                  'pendingToolProposal',
                  const CloseBranchProposal(summary: 'Fixed it'),
                ),
          ],
        );
      },
    );

    group('confirmPendingToolProposal / rejectPendingToolProposal', () {
      setUp(() {
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
        // confirmPendingToolProposal/rejectPendingToolProposal both
        // re-read the chat itself to re-emit TicketDetailLoaded once
        // resolved.
        when(
          () => repository.getTicketById(rootChat.id),
        ).thenAnswer((_) async => rootChat);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.chatBranching,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);
      });

      blocTest<TicketsCubit, TicketsState>(
        'confirmPendingToolProposal runs onConfirm, resolves the paused '
        'onToolCall future with its result, and re-emits without the '
        'proposal',
        setUp: () {
          when(() => repository.createTicket(any())).thenAnswer((_) async {});
        },
        build: buildCubit,
        act: (cubit) async {
          unawaited(
            cubit
                .handleChatToolCall(rootChat, 'call-1', 'branch_ticket', {
                  'title': 'Sub-issue',
                })
                .then((value) => result = value),
          );
          await Future<void>.delayed(Duration.zero);
          await cubit.confirmPendingToolProposal(rootChat.id);
        },
        verify: (_) {
          verify(() => repository.createTicket(any())).called(1);
          expect(result?['accepted'], true);
          expect(result?['childChatId'], isA<String>());
        },
        expect: () => [
          isA<TicketDetailLoaded>().having(
            (s) => s.pendingToolProposal,
            'pendingToolProposal',
            isNotNull,
          ),
          isA<TicketDetailLoaded>()
              .having((s) => s.ticket.id, 'ticket.id', rootChat.id)
              .having(
                (s) => s.pendingToolProposal,
                'pendingToolProposal',
                isNull,
              ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejectPendingToolProposal resolves the paused onToolCall future '
        'with a decline, without ever running onConfirm',
        build: buildCubit,
        act: (cubit) async {
          unawaited(
            cubit
                .handleChatToolCall(rootChat, 'call-1', 'branch_ticket', {
                  'title': 'Sub-issue',
                })
                .then((value) => result = value),
          );
          await Future<void>.delayed(Duration.zero);
          await cubit.rejectPendingToolProposal(rootChat.id);
        },
        verify: (_) {
          verifyNever(() => repository.createTicket(any()));
          expect(result, {'accepted': false, 'reason': 'Declined by user.'});
        },
        expect: () => [
          isA<TicketDetailLoaded>().having(
            (s) => s.pendingToolProposal,
            'pendingToolProposal',
            isNotNull,
          ),
          isA<TicketDetailLoaded>()
              .having((s) => s.ticket.id, 'ticket.id', rootChat.id)
              .having(
                (s) => s.pendingToolProposal,
                'pendingToolProposal',
                isNull,
              ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'confirmPendingToolProposal no-ops for a chat id with no pending '
        'proposal',
        build: buildCubit,
        act: (cubit) => cubit.confirmPendingToolProposal('no-such-chat'),
        expect: () => <TicketsState>[],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejectPendingToolProposal no-ops for a chat id with no pending '
        'proposal',
        build: buildCubit,
        act: (cubit) => cubit.rejectPendingToolProposal('no-such-chat'),
        expect: () => <TicketsState>[],
      );
    });
  });

  group('coding-execution trigger', () {
    late MockAgentModelClient agentClient;
    late MockProviderRegistry registry;
    late MockCommentRepository commentRepository;
    late MockAutomationSettingsRepository automationSettingsRepository;
    late MockGitRepositoryClient gitClient;
    late MockGitHubCliClient gitHubClient;
    late MockBaselineRepository baselineRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
      registry = buildProviderStack(agentClient).registry;
      commentRepository = MockCommentRepository();
      automationSettingsRepository = MockAutomationSettingsRepository();
      gitClient = MockGitRepositoryClient();
      gitHubClient = MockGitHubCliClient();
      baselineRepository = MockBaselineRepository();
      stubSuccessfulCodingExecutionInfra(gitClient, gitHubClient);
      stubEmptyBaseline(baselineRepository);
    });

    TicketsCubit buildFullCubit() => TicketsCubit(
      repository,
      providerRegistry: registry,
      commentRepository: commentRepository,
      automationSettingsRepository: automationSettingsRepository,
      projectRootPath: '/fake/project/root',
      gitClient: gitClient,
      gitHubClient: gitHubClient,
      baselineRepository: baselineRepository,
      projectId: 'project-1',
      baselineVersion: '0.1.0',
    );

    blocTest<TicketsCubit, TicketsState>(
      'blocks a Task under a Story needing design review that is not yet '
      'approved, without calling the repository or the agent',
      setUp: () {
        when(
          () => repository.getTicketById(storyForExecution.id),
        ).thenAnswer((_) async => storyForExecution);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskUnderStory]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c3',
              ticketId: designSyncChatForExecution.id,
              content: 'Found one issue.\n\nDESIGN GATE: PENDING',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
      },
      build: buildFullCubit,
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderStory, TicketStatus.inProgress),
      verify: (_) {
        verifyNever(() => repository.updateTicketStatus(any(), any()));
        verifyNever(() => repository.createTicket(any()));
        verifyNever(() => agentClient.run(any()));
      },
      expect: () => [
        const TicketsError(
          '',
          reason: TicketsErrorReason.codingExecutionBlocked,
        ),
        TicketDetailLoaded(taskUnderStory),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'allows a Task with no governing Story to start unconditionally',
      build: () => TicketsCubit(repository),
      setUp: () {
        when(
          () => repository.updateTicketStatus(
            taskNoStory.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
        when(() => repository.getTicketById(taskNoStory.id)).thenAnswer(
          (_) async => taskNoStory.copyWith(status: TicketStatus.inProgress),
        );
      },
      act: (cubit) =>
          cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress),
      verify: (_) {
        verify(
          () => repository.updateTicketStatus(
            taskNoStory.id,
            TicketStatus.inProgress,
          ),
        ).called(1);
      },
      expect: () => [
        TicketDetailLoaded(
          taskNoStory.copyWith(status: TicketStatus.inProgress),
        ),
        // Queued, then started, then cleared once _runCodingExecution's
        // no-providerRegistry early-return runs — _refreshTaskDetailIfShowing
        // keeps this already-open detail screen's isExecuting/
        // executionQueuePosition in sync with each step, matching
        // _refreshInFlightBoardState's own Board-side refresh. Added for
        // `aion-arch/changes/parallel-work` post-/verify.
        TicketDetailLoaded(
          taskNoStory.copyWith(status: TicketStatus.inProgress),
          executionQueuePosition: 1,
        ),
        TicketDetailLoaded(
          taskNoStory.copyWith(status: TicketStatus.inProgress),
          isExecuting: true,
        ),
        TicketDetailLoaded(
          taskNoStory.copyWith(status: TicketStatus.inProgress),
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'runs the coding-execution chat on an approved Task and flips it to '
      'inReview when confidence is auto and a PR was confirmed opened',
      build: buildFullCubit,
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskUnderStory]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c4',
              ticketId: designSyncChatForExecution.id,
              content: 'No issues found.\n\nDESIGN GATE: APPROVED',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        // No execution chat exists yet when _resolveExecutionChat first
        // looks (the create-new branch runs); once
        // repository.createTicket is called, it becomes findable — the
        // same sequencing production code produces, and what
        // _executionSucceededWithPr's post-run check relies on.
        var executionChatCreated = false;
        when(
          () => repository.getTicketsByParent(
            taskUnderStory.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer(
          (_) async => executionChatCreated ? [dummyExecutionChatTicket] : [],
        );
        stubStatefulComments(commentRepository, dummyExecutionChatTicket.id);
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == storyForExecution.id) return storyForExecution;
          if (id == taskUnderStory.id) {
            return taskUnderStory.copyWith(status: TicketStatus.inProgress);
          }
          return dummyExecutionChatTicket;
        });
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(() => repository.createTicket(any())).thenAnswer((_) async {
          executionChatCreated = true;
        });
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
            AgentDoneEvent(),
          ]),
        );
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecution,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
      },
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderStory, TicketStatus.inProgress),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => repository.updateTicketStatus(
            taskUnderStory.id,
            TicketStatus.inProgress,
          ),
        ).called(1);
        verify(() => repository.createTicket(any())).called(1);
        // 2 model turns: implement, then agentic verify.
        verify(() => agentClient.run(any())).called(2);
        verify(
          () => repository.updateTicketStatus(
            taskUnderStory.id,
            TicketStatus.inReview,
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'includes a "## Related tickets" section in the coding-execution '
      "implement turn's prompt when TicketContextEnricher has content to "
      'contribute (the Task\'s governing Story, surfaced as an ancestor)',
      build: buildFullCubit,
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskUnderStory]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c-related',
              ticketId: designSyncChatForExecution.id,
              content: 'No issues found.\n\nDESIGN GATE: APPROVED',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(
          () => repository.getTicketsByParent(
            taskUnderStory.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);
        stubStatefulComments(commentRepository, dummyExecutionChatTicket.id);
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == storyForExecution.id) return storyForExecution;
          if (id == taskUnderStory.id) {
            return taskUnderStory.copyWith(status: TicketStatus.inProgress);
          }
          return dummyExecutionChatTicket;
        });
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        // Both the Task and its governing Story, so the ancestor walk
        // surfaces the Story.
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [storyForExecution, taskUnderStory]);
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
            AgentDoneEvent(),
          ]),
        );
      },
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderStory, TicketStatus.inProgress),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>(
                (request) =>
                    request.prompt.contains('IMPLEMENTATION: DONE') &&
                    request.prompt.contains('## Related tickets') &&
                    request.prompt.contains(storyForExecution.title),
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'omits the "## Related tickets" section entirely — preserving '
      "today's exact prompt — when TicketContextEnricher has nothing to "
      'contribute',
      build: buildFullCubit,
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskUnderStory]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c-no-related',
              ticketId: designSyncChatForExecution.id,
              content: 'No issues found.\n\nDESIGN GATE: APPROVED',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(
          () => repository.getTicketsByParent(
            taskUnderStory.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);
        stubStatefulComments(commentRepository, dummyExecutionChatTicket.id);
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == storyForExecution.id) return storyForExecution;
          if (id == taskUnderStory.id) {
            return taskUnderStory.copyWith(status: TicketStatus.inProgress);
          }
          return dummyExecutionChatTicket;
        });
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        // Deliberately left as the default empty getAllTickets() stub —
        // no ancestor/link/similarity matches, so the section is omitted.
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
            AgentDoneEvent(),
          ]),
        );
      },
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderStory, TicketStatus.inProgress),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        // Distinguished from the verify turn's own prompt (also absent
        // "## Related tickets") by the implement turn's unique
        // "IMPLEMENTATION: DONE" instruction.
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>(
                (request) =>
                    request.prompt.contains('IMPLEMENTATION: DONE') &&
                    !request.prompt.contains('## Related tickets'),
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'does not flip the Task to inReview when confidence is gated, even '
      'with a confirmed PR',
      build: buildFullCubit,
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskUnderStory]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c6',
              ticketId: designSyncChatForExecution.id,
              content: 'No issues found.\n\nDESIGN GATE: APPROVED',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(
          () => repository.getTicketsByParent(
            taskUnderStory.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [dummyExecutionChatTicket]);
        stubStatefulComments(commentRepository, dummyExecutionChatTicket.id);
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == storyForExecution.id) return storyForExecution;
          if (id == taskUnderStory.id) {
            return taskUnderStory.copyWith(status: TicketStatus.inProgress);
          }
          return dummyExecutionChatTicket;
        });
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
            AgentDoneEvent(),
          ]),
        );
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecution,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);
      },
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderStory, TicketStatus.inProgress),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verifyNever(
          () => repository.updateTicketStatus(
            taskUnderStory.id,
            TicketStatus.inReview,
          ),
        );
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'queues a second Task FIFO while one coding-execution run is already '
      'in flight',
      build: () => TicketsCubit(
        repository,
        providerRegistry: registry,
        commentRepository: commentRepository,
        projectRootPath: '/fake/project/root',
        gitClient: gitClient,
        gitHubClient: gitHubClient,
        baselineRepository: baselineRepository,
        projectId: 'project-1',
        baselineVersion: '0.1.0',
      ),
      setUp: () {
        final runGate = Completer<void>();
        addTearDown(() {
          if (!runGate.isCompleted) runGate.complete();
        });
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == taskNoStory.id) {
            return taskNoStory.copyWith(status: TicketStatus.inProgress);
          }
          return otherTask.copyWith(status: TicketStatus.inProgress);
        });
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        // Neither Task has an execution chat yet — both trigger the
        // create-new branch of _resolveExecutionChat.
        when(
          () => repository.getTicketsByParent(
            any(),
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);
        when(
          () => commentRepository.addComment(any()),
        ).thenAnswer((_) async {});
        // The first run never resolves during this test, so the second
        // trigger must observe the slot as still occupied.
        when(() => agentClient.run(any())).thenAnswer((_) async {
          await runGate.future;
          return const Stream<AgentEvent>.empty();
        });
      },
      act: (cubit) async {
        await cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress);
        await cubit.changeTicketStatus(otherTask, TicketStatus.inProgress);
      },
      verify: (_) {
        // Only the first Task's chat has been spawned — the second is
        // still queued behind it, not yet running.
        verify(() => repository.createTicket(any())).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      "allows a Task under a Story whose Tasks don't indicate UI work to "
      'start unconditionally, without ever checking design approval',
      build: () => TicketsCubit(repository),
      setUp: () {
        when(
          () => repository.getTicketById(storyNoDesignNeeded.id),
        ).thenAnswer((_) async => storyNoDesignNeeded);
        when(
          () => repository.getTicketsByParent(
            storyNoDesignNeeded.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskUnderStoryNoDesign]);
        when(
          () => repository.updateTicketStatus(
            taskUnderStoryNoDesign.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(taskUnderStoryNoDesign.id),
        ).thenAnswer(
          (_) async =>
              taskUnderStoryNoDesign.copyWith(status: TicketStatus.inProgress),
        );
      },
      act: (cubit) => cubit.changeTicketStatus(
        taskUnderStoryNoDesign,
        TicketStatus.inProgress,
      ),
      verify: (_) {
        verify(
          () => repository.updateTicketStatus(
            taskUnderStoryNoDesign.id,
            TicketStatus.inProgress,
          ),
        ).called(1);
        // _designSyncApproved's own lookup (the Story's chat children) is
        // never consulted when the Story doesn't need design review.
        verifyNever(
          () => repository.getTicketsByParent(
            storyNoDesignNeeded.id,
            types: const [TicketType.chat],
          ),
        );
      },
      expect: () => [
        TicketDetailLoaded(
          taskUnderStoryNoDesign.copyWith(status: TicketStatus.inProgress),
        ),
        // See the "no governing Story" case above for why these two extra
        // emissions are expected — _refreshTaskDetailIfShowing, added for
        // `aion-arch/changes/parallel-work` post-/verify.
        TicketDetailLoaded(
          taskUnderStoryNoDesign.copyWith(status: TicketStatus.inProgress),
          executionQueuePosition: 1,
        ),
        TicketDetailLoaded(
          taskUnderStoryNoDesign.copyWith(status: TicketStatus.inProgress),
          isExecuting: true,
        ),
        TicketDetailLoaded(
          taskUnderStoryNoDesign.copyWith(status: TicketStatus.inProgress),
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'allows a Task parented directly under an Epic to start '
      'unconditionally — _governingStory stops walking at the Epic',
      build: () => TicketsCubit(repository),
      setUp: () {
        when(
          () => repository.getTicketById(epic.id),
        ).thenAnswer((_) async => epic);
        when(
          () => repository.updateTicketStatus(
            taskUnderEpic.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
        when(() => repository.getTicketById(taskUnderEpic.id)).thenAnswer(
          (_) async => taskUnderEpic.copyWith(status: TicketStatus.inProgress),
        );
      },
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderEpic, TicketStatus.inProgress),
      verify: (_) {
        verify(
          () => repository.updateTicketStatus(
            taskUnderEpic.id,
            TicketStatus.inProgress,
          ),
        ).called(1);
        // Never walks past the Epic looking for sibling Tasks/a Story.
        verifyNever(
          () => repository.getTicketsByParent(
            epic.id,
            types: any(named: 'types'),
          ),
        );
      },
      expect: () => [
        TicketDetailLoaded(
          taskUnderEpic.copyWith(status: TicketStatus.inProgress),
        ),
        // See the "no governing Story" case above for why these two extra
        // emissions are expected — _refreshTaskDetailIfShowing, added for
        // `aion-arch/changes/parallel-work` post-/verify.
        TicketDetailLoaded(
          taskUnderEpic.copyWith(status: TicketStatus.inProgress),
          executionQueuePosition: 1,
        ),
        TicketDetailLoaded(
          taskUnderEpic.copyWith(status: TicketStatus.inProgress),
          isExecuting: true,
        ),
        TicketDetailLoaded(
          taskUnderEpic.copyWith(status: TicketStatus.inProgress),
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'does not flip the Task to inReview when the run reports '
      'EXECUTION: NO_PR, even with confidence auto',
      build: buildFullCubit,
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskUnderStory]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c8',
              ticketId: designSyncChatForExecution.id,
              content: 'No issues found.\n\nDESIGN GATE: APPROVED',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(
          () => repository.getTicketsByParent(
            taskUnderStory.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [dummyExecutionChatTicket]);
        stubStatefulComments(commentRepository, dummyExecutionChatTicket.id);
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == storyForExecution.id) return storyForExecution;
          if (id == taskUnderStory.id) {
            return taskUnderStory.copyWith(status: TicketStatus.inProgress);
          }
          return dummyExecutionChatTicket;
        });
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        // The model's reply never claims VERIFICATION: PASSED — the
        // agentic verify turn fails closed, so no push/PR is ever
        // attempted and no EXECUTION: PR_OPENED comment is ever posted.
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent("Couldn't finish.\n\nEXECUTION: NO_PR"),
            AgentDoneEvent(),
          ]),
        );
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecution,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecutionRetry,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);
      },
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderStory, TicketStatus.inProgress),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verifyNever(
          () => repository.updateTicketStatus(
            taskUnderStory.id,
            TicketStatus.inReview,
          ),
        );
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'forces gated (no auto-flip to inReview) for the rest of the '
      'session once AgentOverageDetectedEvent has fired during a run',
      build: buildFullCubit,
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskUnderStory]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c10',
              ticketId: designSyncChatForExecution.id,
              content: 'No issues found.\n\nDESIGN GATE: APPROVED',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(
          () => repository.getTicketsByParent(
            taskUnderStory.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [dummyExecutionChatTicket]);
        stubStatefulComments(commentRepository, dummyExecutionChatTicket.id);
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == storyForExecution.id) return storyForExecution;
          if (id == taskUnderStory.id) {
            return taskUnderStory.copyWith(status: TicketStatus.inProgress);
          }
          return dummyExecutionChatTicket;
        });
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        // The run itself reports overage mid-stream, then still finishes
        // with a passing agentic verify turn (and thus a confirmed PR) —
        // the override must still force `gated`.
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentOverageDetectedEvent('Usage limit reached'),
            AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
            AgentDoneEvent(),
          ]),
        );
        // Configured confidence is auto — the override must beat it.
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecution,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
      },
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderStory, TicketStatus.inProgress),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verifyNever(
          () => repository.updateTicketStatus(
            taskUnderStory.id,
            TicketStatus.inReview,
          ),
        );
      },
      expect: () => [
        TicketDetailLoaded(
          taskUnderStory.copyWith(status: TicketStatus.inProgress),
        ),
        // See the "no governing Story" case above for why these two extra
        // emissions are expected — _refreshTaskDetailIfShowing, added for
        // `aion-arch/changes/parallel-work` post-/verify.
        TicketDetailLoaded(
          taskUnderStory.copyWith(status: TicketStatus.inProgress),
          executionQueuePosition: 1,
        ),
        TicketDetailLoaded(
          taskUnderStory.copyWith(status: TicketStatus.inProgress),
          isExecuting: true,
        ),
        const TicketsError(
          '',
          reason: TicketsErrorReason.executionBudgetOverageDetected,
        ),
        const TicketsLoading(),
        // The forced-`gated` override applies here too (not just to the
        // skipped auto-flip above) — the ready-for-review banner must
        // still surface even though the configured confidence is `auto`.
        // executionTokenTotal is 0, not null, since both turns completed
        // (each with a bare AgentDoneEvent() reporting no usage) — the
        // running total starts at 0 the moment any turn completes.
        TicketDetailLoaded(
          taskUnderStory.copyWith(status: TicketStatus.inProgress),
          executionAwaitingReview: true,
          executionTokenTotal: 0,
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'dequeues and runs the next Task once the in-flight run completes',
      build: () => TicketsCubit(
        repository,
        providerRegistry: registry,
        commentRepository: commentRepository,
        projectRootPath: '/fake/project/root',
        gitClient: gitClient,
        gitHubClient: gitHubClient,
        baselineRepository: baselineRepository,
        projectId: 'project-1',
        baselineVersion: '0.1.0',
      ),
      setUp: () {
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == taskNoStory.id) {
            return taskNoStory.copyWith(status: TicketStatus.inProgress);
          }
          if (id == otherTask.id) {
            return otherTask.copyWith(status: TicketStatus.inProgress);
          }
          return dummyExecutionChatTicket;
        });
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => commentRepository.addComment(any()),
        ).thenAnswer((_) async {});
        // No text in the stubbed stream below means runChatTurn never
        // posts a comment — the agentic verify turn's mid-run read
        // (_lastCommentContent) still needs a non-throwing stub.
        when(
          () => commentRepository.getCommentsForTicket(any()),
        ).thenAnswer((_) async => []);
        // _executionSucceededWithPr's chat lookup — no execution chats
        // found means no PR to confirm, exercised without needing an
        // AutomationSettingsRepository (neither Task has one wired here).
        when(
          () => repository.getTicketsByParent(
            any(),
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      act: (cubit) async {
        await cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress);
        await cubit.changeTicketStatus(otherTask, TicketStatus.inProgress);
        // Let the first run's fire-and-forget completion (which triggers
        // _dequeueNext) settle before asserting on the second run.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      verify: (_) {
        // Both Tasks' chats were eventually spawned and run, in order —
        // 2 model turns (implement + agentic verify) each.
        verify(() => repository.createTicket(any())).called(2);
        verify(() => agentClient.run(any())).called(4);
      },
    );
  });

  group(
    '_refreshInFlightBoardState (board-execution-indicators-and-notifications)',
    () {
      late MockAgentModelClient agentClient;
      late MockProviderRegistry registry;
      late MockCommentRepository commentRepository;
      late MockAutomationSettingsRepository automationSettingsRepository;
      late MockGitRepositoryClient gitClient;
      late MockGitHubCliClient gitHubClient;
      late MockBaselineRepository baselineRepository;

      setUp(() {
        agentClient = MockAgentModelClient();
        registry = buildProviderStack(agentClient).registry;
        commentRepository = MockCommentRepository();
        automationSettingsRepository = MockAutomationSettingsRepository();
        gitClient = MockGitRepositoryClient();
        gitHubClient = MockGitHubCliClient();
        baselineRepository = MockBaselineRepository();
        stubSuccessfulCodingExecutionInfra(gitClient, gitHubClient);
        stubEmptyBaseline(baselineRepository);
      });

      TicketsCubit buildFullCubit() => TicketsCubit(
        repository,
        providerRegistry: registry,
        commentRepository: commentRepository,
        automationSettingsRepository: automationSettingsRepository,
        projectRootPath: '/fake/project/root',
        gitClient: gitClient,
        gitHubClient: gitHubClient,
        baselineRepository: baselineRepository,
        projectId: 'project-1',
        baselineVersion: '0.1.0',
      );

      test('a queued Task appears in inFlightExecutionIds once the run it was '
          'waiting behind clears and it is dequeued, while TicketsLoaded is '
          'the current state', () async {
        var runCallCount = 0;
        final firstRunPause = Completer<Stream<AgentEvent>>();
        when(() => agentClient.run(any())).thenAnswer((_) {
          runCallCount++;
          return runCallCount == 1
              ? firstRunPause.future
              : Future.value(
                  Stream<AgentEvent>.fromIterable(const [
                    AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
                    AgentDoneEvent(),
                  ]),
                );
        });
        stubStatefulComments(commentRepository, 'exec-chat-task1');
        stubStatefulComments(commentRepository, 'exec-chat-task2');
        when(
          () => repository.updateTicketStatus(
            taskNoStory.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.updateTicketStatus(
            otherTask.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
        // Each Task's own execution chat is distinguishable by which
        // Task's children are being queried — getTicketsByParent's mock
        // is keyed off the *task* id, not the (never-real) chat id, so a
        // single execution-chat fixture per task is enough here.
        final execChatTask1 = Ticket(
          id: 'exec-chat-task1',
          ticketId: 'AIO-90',
          type: TicketType.chat,
          title: 'Coding Execution — ${taskNoStory.title}',
          status: TicketStatus.backlog,
          parentId: taskNoStory.id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final execChatTask2 = Ticket(
          id: 'exec-chat-task2',
          ticketId: 'AIO-91',
          type: TicketType.chat,
          title: 'Coding Execution — ${otherTask.title}',
          status: TicketStatus.backlog,
          parentId: otherTask.id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        var task1ChatCreated = false;
        var task2ChatCreated = false;
        when(
          () => repository.getTicketsByParent(
            taskNoStory.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => task1ChatCreated ? [execChatTask1] : []);
        when(
          () => repository.getTicketsByParent(
            otherTask.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => task2ChatCreated ? [execChatTask2] : []);
        when(() => repository.createTicket(any())).thenAnswer((
          invocation,
        ) async {
          final created = invocation.positionalArguments[0] as Ticket;
          if (created.parentId == taskNoStory.id) task1ChatCreated = true;
          if (created.parentId == otherTask.id) task2ChatCreated = true;
        });
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == taskNoStory.id) {
            return taskNoStory.copyWith(status: TicketStatus.inProgress);
          }
          if (id == otherTask.id) {
            return otherTask.copyWith(status: TicketStatus.inProgress);
          }
          if (task1ChatCreated && !task2ChatCreated) return execChatTask1;
          return execChatTask2;
        });
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => TicketSearchPage(
            tickets: [taskNoStory, otherTask],
            hasMore: false,
          ),
        );
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecution,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);

        final cubit = buildFullCubit();
        addTearDown(cubit.close);
        final states = <TicketsState>[];
        final sub = cubit.stream.listen(states.add);
        addTearDown(sub.cancel);

        // updateTicketStatus (the board-drag path), not changeTicketStatus
        // — it never re-emits TicketDetailLoaded, so _runCodingExecution's
        // own wasShowingTaskDetail re-check (which would otherwise clobber
        // the TicketsLoaded state established below) never fires here.
        await cubit.updateTicketStatus(taskNoStory.id, TicketStatus.inProgress);
        await cubit.updateTicketStatus(otherTask.id, TicketStatus.inProgress);
        await cubit.searchTickets();

        // Resolves taskNoStory's paused implement-turn call — the run
        // proceeds through its verify/push/PR steps and completes,
        // clearing itself and dequeuing otherTask, both while
        // TicketsLoaded is now current.
        firstRunPause.complete(
          Stream.fromIterable(const [
            AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
            AgentDoneEvent(),
          ]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // The queue/dequeue chain may run task2 to completion too within
        // this window (nothing here pauses its own turns) — assert that
        // it was reflected as running at some point, rather than pinning
        // down the exact final state.
        final loadedStates = states.whereType<TicketsLoaded>().toList();
        expect(loadedStates, isNotEmpty);
        expect(
          loadedStates.any(
            (s) => s.inFlightExecutionIds.contains(otherTask.id),
          ),
          isTrue,
        );
      });

      blocTest<TicketsCubit, TicketsState>(
        'still keeps an already-open TicketDetailLoaded screen in sync '
        '(via _refreshTaskDetailIfShowing) even though '
        '_refreshInFlightBoardState itself no-ops for it, not TicketsLoaded',
        // A cubit missing git/baseline deps — _runCodingExecution hits its
        // own missing-deps guard immediately, so this test only needs to
        // observe changeTicketStatus's own emissions, not a full run.
        // _refreshInFlightBoardState (Board-shaped state only) is still a
        // no-op the whole way through here — _refreshTaskDetailIfShowing
        // is what keeps this open detail screen's isExecuting/
        // executionQueuePosition accurate instead. Renamed/updated for
        // `aion-arch/changes/parallel-work` post-/verify, which added
        // that method to close this exact gap.
        build: () => TicketsCubit(
          repository,
          providerRegistry: registry,
          commentRepository: commentRepository,
        ),
        setUp: () {
          when(
            () => repository.updateTicketStatus(
              otherTask.id,
              TicketStatus.inProgress,
            ),
          ).thenAnswer((_) async {});
          when(() => repository.getTicketById(otherTask.id)).thenAnswer(
            (_) async => otherTask.copyWith(status: TicketStatus.inProgress),
          );
        },
        act: (cubit) =>
            cubit.changeTicketStatus(otherTask, TicketStatus.inProgress),
        wait: const Duration(milliseconds: 50),
        expect: () => [
          TicketDetailLoaded(
            otherTask.copyWith(status: TicketStatus.inProgress),
          ),
          TicketDetailLoaded(
            otherTask.copyWith(status: TicketStatus.inProgress),
            executionQueuePosition: 1,
          ),
          TicketDetailLoaded(
            otherTask.copyWith(status: TicketStatus.inProgress),
            isExecuting: true,
          ),
          TicketDetailLoaded(
            otherTask.copyWith(status: TicketStatus.inProgress),
          ),
        ],
      );
    },
  );

  group(
    '_computeStageAdvanceFailure (board-execution-indicators-and-notifications)',
    () {
      late MockCommentRepository commentRepository;

      final epicExploring = Ticket(
        id: epic.id,
        ticketId: epic.ticketId,
        type: epic.type,
        title: epic.title,
        status: epic.status,
        sddStage: SddStage.exploring,
        createdAt: epic.createdAt,
        updatedAt: epic.updatedAt,
      );

      setUp(() {
        commentRepository = MockCommentRepository();
      });

      TicketsCubit buildCubit() =>
          TicketsCubit(repository, commentRepository: commentRepository);

      blocTest<TicketsCubit, TicketsState>(
        'no stage chat yet — not failed',
        build: buildCubit,
        setUp: () {
          when(
            () => repository.getTicketById(epic.id),
          ).thenAnswer((_) async => epicExploring);
          when(
            () => repository.getTicketsByParent(
              epic.id,
              types: const [TicketType.chat],
            ),
          ).thenAnswer((_) async => <Ticket>[]);
        },
        act: (cubit) => cubit.getTicketById(epic.id),
        expect: () => [
          const TicketsLoading(),
          isA<TicketDetailLoaded>()
              .having(
                (s) => s.sddStageFailureReason,
                'sddStageFailureReason',
                isNull,
              )
              .having((s) => s.sddStageCanRetry, 'sddStageCanRetry', false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'most recent comment ai-authored — not failed',
        build: buildCubit,
        setUp: () {
          when(
            () => repository.getTicketById(epic.id),
          ).thenAnswer((_) async => epicExploring);
          when(
            () => repository.getTicketsByParent(
              epic.id,
              types: const [TicketType.chat],
            ),
          ).thenAnswer((_) async => [dummyChatTicket]);
          when(
            () => commentRepository.getCommentsForTicket(dummyChatTicket.id),
          ).thenAnswer(
            (_) async => [
              TicketComment(
                id: 'c-ai',
                ticketId: dummyChatTicket.id,
                content: 'All done.',
                authorType: CommentAuthorType.ai,
                createdAt: DateTime(2026),
              ),
            ],
          );
        },
        act: (cubit) => cubit.getTicketById(epic.id),
        expect: () => [
          const TicketsLoading(),
          isA<TicketDetailLoaded>()
              .having(
                (s) => s.sddStageFailureReason,
                'sddStageFailureReason',
                isNull,
              )
              .having((s) => s.sddStageCanRetry, 'sddStageCanRetry', false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'most recent comment "Stage advance failed: ..." — failed, retriable',
        build: buildCubit,
        setUp: () {
          when(
            () => repository.getTicketById(epic.id),
          ).thenAnswer((_) async => epicExploring);
          when(
            () => repository.getTicketsByParent(
              epic.id,
              types: const [TicketType.chat],
            ),
          ).thenAnswer((_) async => [dummyChatTicket]);
          when(
            () => commentRepository.getCommentsForTicket(dummyChatTicket.id),
          ).thenAnswer(
            (_) async => [
              TicketComment(
                id: 'c-fail',
                ticketId: dummyChatTicket.id,
                content: 'Stage advance failed: boom',
                authorType: CommentAuthorType.system,
                createdAt: DateTime(2026),
              ),
            ],
          );
        },
        act: (cubit) => cubit.getTicketById(epic.id),
        expect: () => [
          const TicketsLoading(),
          isA<TicketDetailLoaded>()
              .having(
                (s) => s.sddStageFailureReason,
                'sddStageFailureReason',
                'Stage advance failed: boom',
              )
              .having((s) => s.sddStageCanRetry, 'sddStageCanRetry', true),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'a non-ai most-recent comment while not in-flight (simulating a '
        'post-restart orphan) — fixed "ended without a clear result" '
        'message, retriable',
        build: buildCubit,
        setUp: () {
          when(
            () => repository.getTicketById(epic.id),
          ).thenAnswer((_) async => epicExploring);
          when(
            () => repository.getTicketsByParent(
              epic.id,
              types: const [TicketType.chat],
            ),
          ).thenAnswer((_) async => [dummyChatTicket]);
          when(
            () => commentRepository.getCommentsForTicket(dummyChatTicket.id),
          ).thenAnswer(
            (_) async => [
              TicketComment(
                id: 'c-context',
                ticketId: dummyChatTicket.id,
                content: 'Context for the stage.',
                authorType: CommentAuthorType.system,
                createdAt: DateTime(2026),
              ),
            ],
          );
        },
        act: (cubit) => cubit.getTicketById(epic.id),
        expect: () => [
          const TicketsLoading(),
          isA<TicketDetailLoaded>()
              .having(
                (s) => s.sddStageFailureReason,
                'sddStageFailureReason',
                'Stage advance ended without a clear result.',
              )
              .having((s) => s.sddStageCanRetry, 'sddStageCanRetry', true),
        ],
      );
    },
  );

  group('bug coding-execution parity', () {
    blocTest<TicketsCubit, TicketsState>(
      'allows a Bug with no governing Story to start unconditionally, '
      'exactly like a Task',
      build: () => TicketsCubit(repository),
      setUp: () {
        when(
          () => repository.updateTicketStatus(
            bugNoStory.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
        when(() => repository.getTicketById(bugNoStory.id)).thenAnswer(
          (_) async => bugNoStory.copyWith(status: TicketStatus.inProgress),
        );
      },
      act: (cubit) =>
          cubit.changeTicketStatus(bugNoStory, TicketStatus.inProgress),
      verify: (_) {
        verify(
          () => repository.updateTicketStatus(
            bugNoStory.id,
            TicketStatus.inProgress,
          ),
        ).called(1);
      },
      expect: () => [
        TicketDetailLoaded(
          bugNoStory.copyWith(status: TicketStatus.inProgress),
        ),
        // See the Task-parity case in the coding-execution trigger group
        // above for why these two extra emissions are expected —
        // _refreshTaskDetailIfShowing, added for
        // `aion-arch/changes/parallel-work` post-/verify.
        TicketDetailLoaded(
          bugNoStory.copyWith(status: TicketStatus.inProgress),
          executionQueuePosition: 1,
        ),
        TicketDetailLoaded(
          bugNoStory.copyWith(status: TicketStatus.inProgress),
          isExecuting: true,
        ),
        TicketDetailLoaded(
          bugNoStory.copyWith(status: TicketStatus.inProgress),
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'blocks a Bug under a Story needing design review that is not yet '
      'approved, without calling the repository — same gate a Task '
      'sibling would hit',
      build: () {
        final commentRepository = MockCommentRepository();
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'bug-gate-c1',
              ticketId: designSyncChatForExecution.id,
              content: 'Found one issue.\n\nDESIGN GATE: PENDING',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        return TicketsCubit(repository, commentRepository: commentRepository);
      },
      setUp: () {
        when(
          () => repository.getTicketById(storyForExecution.id),
        ).thenAnswer((_) async => storyForExecution);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [bugUnderStory]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
      },
      act: (cubit) =>
          cubit.changeTicketStatus(bugUnderStory, TicketStatus.inProgress),
      verify: (_) {
        verifyNever(() => repository.updateTicketStatus(any(), any()));
      },
      expect: () => [
        const TicketsError(
          '',
          reason: TicketsErrorReason.codingExecutionBlocked,
        ),
        TicketDetailLoaded(bugUnderStory),
      ],
    );
  });

  group(
    'coding-execution reliability (worktree isolation, verify gate, retry)',
    () {
      late MockAgentModelClient agentClient;
      late MockProviderRegistry registry;
      late MockCommentRepository commentRepository;
      late MockAutomationSettingsRepository automationSettingsRepository;
      late MockGitRepositoryClient gitClient;
      late MockGitHubCliClient gitHubClient;
      late MockBaselineRepository baselineRepository;
      late MockTicketLinkRepository linkRepository;

      setUp(() {
        agentClient = MockAgentModelClient();
        registry = buildProviderStack(agentClient).registry;
        commentRepository = MockCommentRepository();
        automationSettingsRepository = MockAutomationSettingsRepository();
        gitClient = MockGitRepositoryClient();
        gitHubClient = MockGitHubCliClient();
        baselineRepository = MockBaselineRepository();
        linkRepository = MockTicketLinkRepository();
        stubSuccessfulCodingExecutionInfra(gitClient, gitHubClient);
        stubEmptyBaseline(baselineRepository);
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        // Any freshly-created "Coding Execution — ..." chat ticket's id
        // (a fresh uuid, not knowable up front) also needs to resolve —
        // falls back to returning it as the persisted chat ticket.
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == taskNoStory.id) {
            return taskNoStory.copyWith(status: TicketStatus.inProgress);
          }
          return dummyExecutionChatTicket;
        });
        // Default fixture: an existing, under-cap execution chat already
        // exists for taskNoStory — the common case every test but the
        // dedicated "first-ever trigger" one below exercises.
        // `_resolveExecutionChat` reuses it rather than creating a new
        // one; `stubStatefulComments` below starts it at zero accumulated
        // usage, well under the (default, unconfigured) 200,000-token cap.
        when(
          () => repository.getTicketsByParent(
            taskNoStory.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [dummyExecutionChatTicket]);
        // Reflects comments as production code actually posts them —
        // both the agentic verify turn's mid-run read and
        // `_executionSucceededWithPr`'s end-of-run read see this same,
        // genuinely-growing list. Individual tests only need to control
        // what `agentClient.run` streams back, not hand-craft a "final
        // state" comment list.
        stubStatefulComments(commentRepository, dummyExecutionChatTicket.id);
        // getTicketById's post-run refresh always consults the
        // completion-flip confidence too, regardless of what this test
        // is actually exercising.
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecution,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);
        // A handoff's link-back — literal linkType (not `any()`) so no
        // `registerFallbackValue(TicketLinkType...)` is needed here.
        when(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
        // Unrelated to this group's own coverage — stubbed so
        // `_interceptBlockedDependencyTrigger`'s `_isTicketBlocked` check
        // (added for `aion-arch/changes/blocked-ticket-transition-gate`)
        // resolves to "not blocked" rather than an unstubbed-call error.
        when(
          () => linkRepository.getLinksForTicket(any()),
        ).thenAnswer((_) async => []);
      });

      TicketsCubit buildCubit() => TicketsCubit(
        repository,
        providerRegistry: registry,
        commentRepository: commentRepository,
        automationSettingsRepository: automationSettingsRepository,
        projectRootPath: '/fake/project/root',
        gitClient: gitClient,
        gitHubClient: gitHubClient,
        baselineRepository: baselineRepository,
        projectId: 'project-1',
        baselineVersion: '0.1.0',
        linkRepository: linkRepository,
      );

      blocTest<TicketsCubit, TicketsState>(
        'creates a worktree before the run, verifies, pushes, opens a PR, '
        'then removes the worktree, on a clean pass',
        build: buildCubit,
        setUp: () {
          when(() => agentClient.run(any())).thenAnswer(
            (_) async => Stream.fromIterable(const [
              AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
              AgentDoneEvent(),
            ]),
          );
        },
        act: (cubit) =>
            cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress),
        wait: const Duration(milliseconds: 50),
        verify: (_) {
          verify(() => gitClient.createWorktree(any(), any(), any())).called(1);
          // 2 model turns: implement, then agentic verify.
          verify(() => agentClient.run(any())).called(2);
          verify(() => gitClient.push(any(), any())).called(1);
          verify(
            () => gitHubClient.openPullRequest(
              rootPath: any(named: 'rootPath'),
              branch: any(named: 'branch'),
              title: any(named: 'title'),
              body: any(named: 'body'),
            ),
          ).called(1);
          verify(() => gitClient.removeWorktree(any(), any())).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'accumulates executionTokenTotal across the implement and verify '
        'turns (token-cost-prediction)',
        build: buildCubit,
        setUp: () {
          var call = 0;
          when(() => agentClient.run(any())).thenAnswer((_) async {
            call++;
            // Turn 1 (implement) reports 1000+500; turn 2 (agentic
            // verify, which passes) reports 2000+800 — the running total
            // should reflect both turns summed together.
            return call == 1
                ? Stream.fromIterable(const [
                    AgentTextEvent('Implemented.'),
                    AgentDoneEvent(inputTokens: 1000, outputTokens: 500),
                  ])
                : Stream.fromIterable(const [
                    AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
                    AgentDoneEvent(inputTokens: 2000, outputTokens: 800),
                  ]);
          });
        },
        act: (cubit) =>
            cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress),
        wait: const Duration(milliseconds: 50),
        verify: (bloc) {
          final state = bloc.state;
          expect(state, isA<TicketDetailLoaded>());
          expect(
            (state as TicketDetailLoaded).executionTokenTotal,
            1000 + 500 + 2000 + 800,
          );
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'removes the worktree even when the implementation turn hard-fails, '
        'and never reaches the verify/push/PR steps',
        build: buildCubit,
        setUp: () {
          when(() => agentClient.run(any())).thenThrow(Exception('boom'));
        },
        act: (cubit) =>
            cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress),
        wait: const Duration(milliseconds: 50),
        verify: (_) {
          verify(() => gitClient.createWorktree(any(), any(), any())).called(1);
          verify(() => gitClient.removeWorktree(any(), any())).called(1);
          // Only the implement turn ran — no agentic verify turn follows
          // a hard implement failure.
          verify(() => agentClient.run(any())).called(1);
          verifyNever(() => gitClient.push(any(), any()));
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'auto confidence retries a failing verify gate up to the cap, then '
        'escalates to a failure comment + toast, without ever pushing',
        build: buildCubit,
        setUp: () {
          // Every model reply — implement or verify — reports the same
          // failure; only the verify-turn replies are ever inspected for
          // pass/fail, so this uniformly drives the retry loop through
          // every attempt.
          when(() => agentClient.run(any())).thenAnswer(
            (_) async => Stream.fromIterable(const [
              AgentTextEvent('VERIFICATION: FAILED — error X'),
              AgentDoneEvent(),
            ]),
          );
          when(
            () => automationSettingsRepository.getConfidence(
              AutomationContext.codingExecutionRetry,
            ),
          ).thenAnswer((_) async => AutomationConfidence.auto);
        },
        act: (cubit) =>
            cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress),
        wait: const Duration(milliseconds: 50),
        verify: (_) {
          // 1 initial attempt + 2 automatic retries (the cap) = 3
          // implement-then-verify pairs = 6 model turns.
          verify(() => agentClient.run(any())).called(6);
          verifyNever(() => gitClient.push(any(), any()));
          verify(
            () => commentRepository.addComment(
              any(
                that: predicate<TicketComment>(
                  (c) => c.content.startsWith('Execution failed verification:'),
                ),
              ),
            ),
          ).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'gated confidence stops after the first verify failure — no retry, '
        'immediate failure comment + toast',
        build: buildCubit,
        setUp: () {
          when(() => agentClient.run(any())).thenAnswer(
            (_) async => Stream.fromIterable(const [
              AgentTextEvent('VERIFICATION: FAILED — error Y'),
              AgentDoneEvent(),
            ]),
          );
          when(
            () => automationSettingsRepository.getConfidence(
              AutomationContext.codingExecutionRetry,
            ),
          ).thenAnswer((_) async => AutomationConfidence.gated);
        },
        act: (cubit) =>
            cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress),
        wait: const Duration(milliseconds: 50),
        verify: (_) {
          // 2 model turns: implement, then agentic verify (which fails,
          // and gated confidence means no retry).
          verify(() => agentClient.run(any())).called(2);
          verifyNever(() => gitClient.push(any(), any()));
          verify(
            () => commentRepository.addComment(
              any(
                that: predicate<TicketComment>(
                  (c) => c.content.startsWith('Execution failed verification:'),
                ),
              ),
            ),
          ).called(1);
        },
        expect: () => [
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
          ),
          // See the "no governing Story" trigger case above for why these
          // two extra emissions are expected — _refreshTaskDetailIfShowing,
          // added for `aion-arch/changes/parallel-work` post-/verify.
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionQueuePosition: 1,
          ),
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            isExecuting: true,
          ),
          // The `gated` toast.
          const TicketsError(
            '',
            reason: TicketsErrorReason.executionVerificationFailed,
          ),
          const TicketsLoading(),
          // The post-run refresh — `getCommentsForTicket` now genuinely
          // reflects the failure comment `_runCodingExecution` posted
          // (see `stubStatefulComments`), so it's echoed verbatim here.
          // executionTokenTotal is 0, not null — both the implement and
          // verify turns completed (each with a bare AgentDoneEvent()
          // reporting no usage) before the verify reply was found to
          // fail.
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionFailureReason: 'Execution failed verification:\n\nerror Y',
            executionCanRetry: true,
            executionTokenTotal: 0,
          ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'manual confidence stops after the first verify failure without a '
        'toast (the failure banner is the only surface)',
        build: buildCubit,
        setUp: () {
          when(() => agentClient.run(any())).thenAnswer(
            (_) async => Stream.fromIterable(const [
              AgentTextEvent('VERIFICATION: FAILED — error Z'),
              AgentDoneEvent(),
            ]),
          );
          when(
            () => automationSettingsRepository.getConfidence(
              AutomationContext.codingExecutionRetry,
            ),
          ).thenAnswer((_) async => AutomationConfidence.manual);
        },
        act: (cubit) =>
            cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress),
        wait: const Duration(milliseconds: 50),
        verify: (_) {
          // 2 model turns: implement, then agentic verify.
          verify(() => agentClient.run(any())).called(2);
          verifyNever(() => gitClient.push(any(), any()));
          verify(
            () => commentRepository.addComment(
              any(
                that: predicate<TicketComment>(
                  (c) => c.content.startsWith('Execution failed verification:'),
                ),
              ),
            ),
          ).called(1);
        },
        expect: () => [
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
          ),
          // See the "no governing Story" trigger case above for why these
          // two extra emissions are expected — _refreshTaskDetailIfShowing,
          // added for `aion-arch/changes/parallel-work` post-/verify.
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionQueuePosition: 1,
          ),
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            isExecuting: true,
          ),
          // Unlike the `gated` case above, nothing here interrupts state
          // with a TicketsError toast — so _runCodingExecution's own
          // completion cleanup (which clears isExecuting) still finds
          // this same TicketDetailLoaded showing, and
          // _refreshTaskDetailIfShowing emits once more for it before the
          // post-run refresh below.
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
          ),
          // No toast for `manual` — straight to the post-run refresh. No
          // intervening TicketsLoading — getTicketById's same-id
          // Loading-skip now covers this re-fetch too (added for
          // `aion-arch/changes/live-refresh-open-ticket-detail-screen`).
          // executionTokenTotal is 0, not null — both the implement and
          // verify turns completed (each with a bare AgentDoneEvent()
          // reporting no usage) before the verify reply was found to
          // fail.
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionFailureReason: 'Execution failed verification:\n\nerror Z',
            executionCanRetry: true,
            executionTokenTotal: 0,
          ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'getTicketById surfaces a system-authored verify-failure comment as '
        'executionFailureReason with executionCanRetry true',
        build: () =>
            TicketsCubit(repository, commentRepository: commentRepository),
        setUp: () {
          when(
            () => commentRepository.getCommentsForTicket(
              dummyExecutionChatTicket.id,
            ),
          ).thenAnswer(
            (_) async => [
              TicketComment(
                id: 'c-verify-fail',
                ticketId: dummyExecutionChatTicket.id,
                content: 'Execution failed verification:\n\nerror output',
                authorType: CommentAuthorType.system,
                createdAt: DateTime(2026),
              ),
            ],
          );
        },
        act: (cubit) => cubit.getTicketById(taskNoStory.id),
        expect: () => [
          const TicketsLoading(),
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionFailureReason:
                'Execution failed verification:\n\nerror output',
            executionCanRetry: true,
          ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'getTicketById treats a chat with no comments at all as an '
        'orphaned/stalled run, still offering a retry',
        build: () =>
            TicketsCubit(repository, commentRepository: commentRepository),
        setUp: () {
          when(
            () => commentRepository.getCommentsForTicket(
              dummyExecutionChatTicket.id,
            ),
          ).thenAnswer((_) async => []);
        },
        act: (cubit) => cubit.getTicketById(taskNoStory.id),
        expect: () => [
          const TicketsLoading(),
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionFailureReason:
                'Execution ended without a clear result — retry to try again.',
            executionCanRetry: true,
          ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        '_executionSucceededWithPr (via getTicketById\'s executionAwaitingReview) '
        'accepts a system-authored EXECUTION: PR_OPENED comment, not just ai',
        build: () => TicketsCubit(
          repository,
          commentRepository: commentRepository,
          automationSettingsRepository: automationSettingsRepository,
        ),
        setUp: () {
          when(
            () => commentRepository.getCommentsForTicket(
              dummyExecutionChatTicket.id,
            ),
          ).thenAnswer(
            (_) async => [
              TicketComment(
                id: 'c-pr-system',
                ticketId: dummyExecutionChatTicket.id,
                content: 'EXECUTION: PR_OPENED https://example/pr/system',
                authorType: CommentAuthorType.system,
                createdAt: DateTime(2026),
              ),
            ],
          );
          when(
            () => automationSettingsRepository.getConfidence(
              AutomationContext.codingExecution,
            ),
          ).thenAnswer((_) async => AutomationConfidence.gated);
        },
        act: (cubit) => cubit.getTicketById(taskNoStory.id),
        expect: () => [
          const TicketsLoading(),
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionAwaitingReview: true,
          ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'retryCodingExecution reuses the Task\'s existing, under-cap '
        'execution chat — no new chat ticket is created, and the run '
        'posts to the existing chat\'s id',
        build: buildCubit,
        setUp: () {
          when(() => agentClient.run(any())).thenAnswer(
            (_) async => Stream.fromIterable(const [
              AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
              AgentDoneEvent(),
            ]),
          );
        },
        act: (cubit) => cubit.retryCodingExecution(taskNoStory),
        wait: const Duration(milliseconds: 50),
        verify: (_) {
          verifyNever(() => repository.createTicket(any()));
          // 2 model turns: implement, then agentic verify.
          verify(() => agentClient.run(any())).called(2);
          verify(() => gitClient.createWorktree(any(), any(), any())).called(1);
          verify(
            () => commentRepository.addComment(
              any(
                that: predicate<TicketComment>(
                  (c) => c.ticketId == dummyExecutionChatTicket.id,
                ),
              ),
            ),
          ).called(greaterThan(0));
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'a first-ever trigger (no existing execution chat) still creates '
        'exactly one chat',
        build: buildCubit,
        setUp: () {
          when(
            () => repository.getTicketsByParent(
              taskNoStory.id,
              types: const [TicketType.chat],
            ),
          ).thenAnswer((_) async => []);
          when(() => agentClient.run(any())).thenAnswer(
            (_) async => Stream.fromIterable(const [
              AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
              AgentDoneEvent(),
            ]),
          );
        },
        act: (cubit) =>
            cubit.changeTicketStatus(taskNoStory, TicketStatus.inProgress),
        wait: const Duration(milliseconds: 50),
        verify: (_) {
          verify(() => repository.createTicket(any())).called(1);
          verify(() => agentClient.run(any())).called(2);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'a chat at/over the handoff threshold hands off to a new linked '
        'chat instead of reusing the over-cap one',
        build: buildCubit,
        setUp: () {
          // No ModelRoutingRepository is supplied to this group's
          // buildCubit, so the execution model resolves to the fallback
          // provider's first model's real 200,000-token
          // contextWindowTokens (see TicketsCubit._resolveModel), and with no
          // ExecutionContextCapRepository either, the effective cap is
          // that same 200,000 with no override available. 190,000 >=
          // 90% of that, so the existing chat is already over the
          // handoff threshold before this run's own turns add anything.
          when(
            () => commentRepository.getCommentsForTicket(
              dummyExecutionChatTicket.id,
            ),
          ).thenAnswer(
            (_) async => [
              TicketComment(
                id: 'c-heavy',
                ticketId: dummyExecutionChatTicket.id,
                content: 'prior turn',
                authorType: CommentAuthorType.ai,
                inputTokens: 150000,
                outputTokens: 40000,
                createdAt: DateTime(2026),
              ),
            ],
          );
          when(() => agentClient.run(any())).thenAnswer(
            (_) async => Stream.fromIterable(const [
              AgentTextEvent('Done.\n\nVERIFICATION: PASSED'),
              AgentDoneEvent(),
            ]),
          );
        },
        act: (cubit) => cubit.retryCodingExecution(taskNoStory),
        wait: const Duration(milliseconds: 50),
        verify: (_) {
          // Summary turn (handoff), then implement, then agentic verify.
          verify(() => agentClient.run(any())).called(3);
          verify(() => repository.createTicket(any())).called(1);
          verify(
            () => linkRepository.createLink(
              sourceTicketId: any(named: 'sourceTicketId'),
              targetTicketId: any(named: 'targetTicketId'),
              linkType: TicketLinkType.relatesTo,
            ),
          ).called(1);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        'a hard-failed handoff summary turn falls back to reusing the '
        'old, over-cap chat rather than blocking the run — no new chat '
        'is created',
        build: buildCubit,
        setUp: () {
          when(
            () => commentRepository.getCommentsForTicket(
              dummyExecutionChatTicket.id,
            ),
          ).thenAnswer(
            (_) async => [
              TicketComment(
                id: 'c-heavy',
                ticketId: dummyExecutionChatTicket.id,
                content: 'prior turn',
                authorType: CommentAuthorType.ai,
                inputTokens: 150000,
                outputTokens: 40000,
                createdAt: DateTime(2026),
              ),
            ],
          );
          when(() => agentClient.run(any())).thenThrow(Exception('boom'));
        },
        act: (cubit) => cubit.retryCodingExecution(taskNoStory),
        wait: const Duration(milliseconds: 50),
        verify: (_) {
          verifyNever(() => repository.createTicket(any()));
          verifyNever(
            () => linkRepository.createLink(
              sourceTicketId: any(named: 'sourceTicketId'),
              targetTicketId: any(named: 'targetTicketId'),
              linkType: TicketLinkType.relatesTo,
            ),
          );
          // The failed summary turn, then the failed implement turn — no
          // verify turn follows a hard implement failure.
          verify(() => agentClient.run(any())).called(2);
        },
      );

      blocTest<TicketsCubit, TicketsState>(
        '_executionSucceededWithPr/_computeExecutionFailure (via '
        'getTicketById) resolve against a "(continued)" handoff chat, not '
        'the original',
        build: () => TicketsCubit(
          repository,
          commentRepository: commentRepository,
          automationSettingsRepository: automationSettingsRepository,
        ),
        setUp: () {
          final continuedChat = Ticket(
            id: 'dummy-exec-chat-continued',
            ticketId: 'AIO-98',
            type: TicketType.chat,
            title: 'Coding Execution — ${taskUnderStory.title} (continued)',
            status: TicketStatus.backlog,
            parentId: taskUnderStory.id,
            createdAt: DateTime(2026, 1, 2),
            updatedAt: DateTime(2026, 1, 2),
          );
          when(
            () => repository.getTicketsByParent(
              taskNoStory.id,
              types: const [TicketType.chat],
            ),
          ).thenAnswer((_) async => [dummyExecutionChatTicket, continuedChat]);
          when(
            () => commentRepository.getCommentsForTicket(continuedChat.id),
          ).thenAnswer(
            (_) async => [
              TicketComment(
                id: 'c-pr-continued',
                ticketId: continuedChat.id,
                content: 'EXECUTION: PR_OPENED https://example/pr/continued',
                authorType: CommentAuthorType.system,
                createdAt: DateTime(2026, 1, 2),
              ),
            ],
          );
        },
        act: (cubit) => cubit.getTicketById(taskNoStory.id),
        expect: () => [
          const TicketsLoading(),
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionAwaitingReview: true,
          ),
        ],
      );
    },
  );

  group('promoteIdea', () {
    late MockTicketLinkRepository linkRepository;

    setUp(() {
      linkRepository = MockTicketLinkRepository();
    });

    TicketsCubit buildCubit() =>
        TicketsCubit(repository, linkRepository: linkRepository);

    blocTest<TicketsCubit, TicketsState>(
      'rejects a non-idea ticket without calling the repository',
      setUp: () {
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
      },
      build: buildCubit,
      act: (cubit) => cubit.promoteIdea(ticket, targetType: TicketType.epic),
      verify: (_) {
        verifyNever(() => repository.createTicket(any()));
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
      },
      expect: () => [isA<TicketsError>(), TicketDetailLoaded(ticket)],
    );

    blocTest<TicketsCubit, TicketsState>(
      'rejects an invalid targetType without calling the repository',
      setUp: () {
        when(
          () => repository.getTicketById(ideaTicket.id),
        ).thenAnswer((_) async => ideaTicket);
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.promoteIdea(ideaTicket, targetType: TicketType.task),
      verify: (_) {
        verifyNever(() => repository.createTicket(any()));
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
      },
      expect: () => [isA<TicketsError>(), TicketDetailLoaded(ideaTicket)],
    );

    blocTest<TicketsCubit, TicketsState>(
      'creates a new epic and links it when existingTicketId is omitted '
      'and targetType is epic',
      setUp: () {
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => linkRepository.createLink(
            sourceTicketId: ideaTicket.id,
            targetTicketId: any(named: 'targetTicketId'),
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ideaTicket.id),
        ).thenAnswer((_) async => ideaTicket);
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.promoteIdea(ideaTicket, targetType: TicketType.epic),
      verify: (_) {
        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured;
        expect(created, hasLength(1));
        expect((created.first as Ticket).type, TicketType.epic);
        verify(
          () => linkRepository.createLink(
            sourceTicketId: ideaTicket.id,
            targetTicketId: any(named: 'targetTicketId'),
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
      expect: () => [TicketDetailLoaded(ideaTicket)],
    );

    blocTest<TicketsCubit, TicketsState>(
      'creates a new bug and links it when existingTicketId is omitted '
      'and targetType is bug',
      setUp: () {
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => linkRepository.createLink(
            sourceTicketId: ideaTicket.id,
            targetTicketId: any(named: 'targetTicketId'),
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ideaTicket.id),
        ).thenAnswer((_) async => ideaTicket);
      },
      build: buildCubit,
      act: (cubit) => cubit.promoteIdea(ideaTicket, targetType: TicketType.bug),
      verify: (_) {
        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured;
        expect(created, hasLength(1));
        expect((created.first as Ticket).type, TicketType.bug);
        verify(
          () => linkRepository.createLink(
            sourceTicketId: ideaTicket.id,
            targetTicketId: any(named: 'targetTicketId'),
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
      expect: () => [TicketDetailLoaded(ideaTicket)],
    );

    blocTest<TicketsCubit, TicketsState>(
      'links to an existing epic without creating a new one when '
      'existingTicketId is given',
      setUp: () {
        when(
          () => linkRepository.createLink(
            sourceTicketId: ideaTicket.id,
            targetTicketId: epic.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(ideaTicket.id),
        ).thenAnswer((_) async => ideaTicket);
      },
      build: buildCubit,
      act: (cubit) => cubit.promoteIdea(
        ideaTicket,
        targetType: TicketType.epic,
        existingTicketId: epic.id,
      ),
      verify: (_) {
        verifyNever(() => repository.createTicket(any()));
        verify(
          () => linkRepository.createLink(
            sourceTicketId: ideaTicket.id,
            targetTicketId: epic.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
      expect: () => [TicketDetailLoaded(ideaTicket)],
    );
  });

  group('createGapOrQuestion', () {
    late MockTicketLinkRepository linkRepository;

    final targetTicket = Ticket(
      id: 'gq-target',
      ticketId: 'AIO-40',
      type: TicketType.story,
      title: 'Target story',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUp(() {
      linkRepository = MockTicketLinkRepository();
      // Default (empty) stubs for `loadDocumentRelations`'s own refresh
      // call at the end of a successful `createGapOrQuestion`, and for
      // `_restoreDocumentTicketDetail`'s recovery call on a rejected one.
      when(() => repository.getAllTickets()).thenAnswer((_) async => []);
      when(
        () => repository.getTicketById(targetTicket.id),
      ).thenAnswer((_) async => targetTicket);
      when(
        () => linkRepository.getLinksByTypes(any()),
      ).thenAnswer((_) async => []);
      when(
        () => linkRepository.getLinksForTicket(any()),
      ).thenAnswer((_) async => []);
    });

    TicketsCubit buildCubit() =>
        TicketsCubit(repository, linkRepository: linkRepository);

    blocTest<TicketsCubit, TicketsState>(
      'rejects a type other than knownGap/openQuestion without touching '
      'the repository, then recovers the target ticket\'s detail state',
      build: buildCubit,
      act: (cubit) => cubit.createGapOrQuestion(
        TicketType.idea,
        title: 'Not allowed',
        targetTicketId: targetTicket.id,
      ),
      verify: (_) {
        verifyNever(() => repository.createTicket(any()));
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
      },
      expect: () => [isA<TicketsError>(), TicketDetailLoaded(targetTicket)],
    );

    blocTest<TicketsCubit, TicketsState>(
      'no-ops without emitting when constructed without a '
      'TicketLinkRepository',
      build: () => TicketsCubit(repository), // no linkRepository
      act: (cubit) => cubit.createGapOrQuestion(
        TicketType.knownGap,
        title: 'A gap',
        targetTicketId: targetTicket.id,
      ),
      verify: (_) {
        verifyNever(() => repository.createTicket(any()));
      },
      expect: () => [],
    );

    blocTest<TicketsCubit, TicketsState>(
      'rejects a target that does not exist, without creating anything',
      setUp: () {
        when(
          () => repository.getTicketById('missing'),
        ).thenAnswer((_) async => null);
      },
      build: buildCubit,
      act: (cubit) => cubit.createGapOrQuestion(
        TicketType.knownGap,
        title: 'A gap',
        targetTicketId: 'missing',
      ),
      verify: (_) {
        verifyNever(() => repository.createTicket(any()));
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
      },
      expect: () => [isA<TicketsError>()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'creates the ticket and its relatesTo link atomically on the happy '
      'path',
      setUp: () {
        when(
          () => repository.getTicketById(targetTicket.id),
        ).thenAnswer((_) async => targetTicket);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: targetTicket.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) => cubit.createGapOrQuestion(
        TicketType.openQuestion,
        title: 'Should this support offline mode?',
        description: 'Raised while reviewing the sync design.',
        targetTicketId: targetTicket.id,
      ),
      verify: (_) {
        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>();
        expect(created, hasLength(1));
        expect(created.single.type, TicketType.openQuestion);
        expect(created.single.title, 'Should this support offline mode?');
        verify(
          () => linkRepository.createLink(
            sourceTicketId: created.single.id,
            targetTicketId: targetTicket.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
    );
  });

  group('reclassifyIdea', () {
    late MockTicketLinkRepository linkRepository;

    final targetTicket = Ticket(
      id: 'ri-target',
      ticketId: 'AIO-41',
      type: TicketType.epic,
      title: 'Target epic',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUp(() {
      linkRepository = MockTicketLinkRepository();
    });

    TicketsCubit buildCubit() =>
        TicketsCubit(repository, linkRepository: linkRepository);

    blocTest<TicketsCubit, TicketsState>(
      'rejects reclassifying a ticket whose current type is not idea, '
      'then recovers the ticket\'s own detail state',
      setUp: () {
        when(
          () => repository.getTicketById(epic.id),
        ).thenAnswer((_) async => epic);
      },
      build: buildCubit,
      act: (cubit) => cubit.reclassifyIdea(
        epic,
        targetType: TicketType.knownGap,
        targetTicketId: targetTicket.id,
      ),
      verify: (_) {
        verifyNever(() => repository.updateTicket(any()));
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
      },
      expect: () => [isA<TicketsError>(), TicketDetailLoaded(epic)],
    );

    blocTest<TicketsCubit, TicketsState>(
      'rejects a targetType other than knownGap/openQuestion, then '
      'recovers the idea\'s own detail state',
      setUp: () {
        when(
          () => repository.getTicketById(ideaTicket.id),
        ).thenAnswer((_) async => ideaTicket);
      },
      build: buildCubit,
      act: (cubit) => cubit.reclassifyIdea(
        ideaTicket,
        targetType: TicketType.epic,
        targetTicketId: targetTicket.id,
      ),
      verify: (_) {
        verifyNever(() => repository.updateTicket(any()));
      },
      expect: () => [isA<TicketsError>(), TicketDetailLoaded(ideaTicket)],
    );

    blocTest<TicketsCubit, TicketsState>(
      'rejects a target that does not exist, without mutating the '
      'ticket, then recovers the idea\'s own detail state',
      setUp: () {
        when(
          () => repository.getTicketById('missing'),
        ).thenAnswer((_) async => null);
        when(
          () => repository.getTicketById(ideaTicket.id),
        ).thenAnswer((_) async => ideaTicket);
      },
      build: buildCubit,
      act: (cubit) => cubit.reclassifyIdea(
        ideaTicket,
        targetType: TicketType.knownGap,
        targetTicketId: 'missing',
      ),
      verify: (_) {
        verifyNever(() => repository.updateTicket(any()));
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
      },
      expect: () => [isA<TicketsError>(), TicketDetailLoaded(ideaTicket)],
    );

    blocTest<TicketsCubit, TicketsState>(
      'mutates the type in place, creates the relatesTo link, and '
      'preserves id/createdAt on the happy path',
      setUp: () {
        when(
          () => repository.getTicketById(targetTicket.id),
        ).thenAnswer((_) async => targetTicket);
        when(() => repository.updateTicket(any())).thenAnswer((_) async {});
        when(
          () => linkRepository.createLink(
            sourceTicketId: ideaTicket.id,
            targetTicketId: targetTicket.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
        when(() => repository.getTicketById(ideaTicket.id)).thenAnswer(
          (_) async => ideaTicket.copyWith(type: TicketType.knownGap),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.reclassifyIdea(
        ideaTicket,
        targetType: TicketType.knownGap,
        targetTicketId: targetTicket.id,
      ),
      verify: (_) {
        final updated = verify(
          () => repository.updateTicket(captureAny()),
        ).captured.cast<Ticket>();
        expect(updated, hasLength(1));
        expect(updated.single.type, TicketType.knownGap);
        expect(updated.single.id, ideaTicket.id);
        expect(updated.single.createdAt, ideaTicket.createdAt);
        verify(
          () => linkRepository.createLink(
            sourceTicketId: ideaTicket.id,
            targetTicketId: targetTicket.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
      expect: () => [
        TicketDetailLoaded(ideaTicket.copyWith(type: TicketType.knownGap)),
      ],
    );
  });

  group('getTicketById computes canAdvanceSddStage', () {
    blocTest<TicketsCubit, TicketsState>(
      'computes needsDesignReview true for a story whose child Task '
      'title indicates UI work',
      setUp: () {
        when(
          () => repository.getTicketById(storyProposed.id),
        ).thenAnswer((_) async => storyProposed);
        when(
          () => repository.getTicketsByParent(
            storyProposed.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => [taskChildUi]);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.getTicketById(storyProposed.id),
      expect: () => [
        const TicketsLoading(),
        TicketDetailLoaded(
          storyProposed,
          canAdvanceSddStage: true,
          needsDesignReview: true,
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'computes needsDesignReview false for a story whose child Tasks '
      'have no UI-indicating title',
      setUp: () {
        when(
          () => repository.getTicketById(storyProposed.id),
        ).thenAnswer((_) async => storyProposed);
        when(
          () => repository.getTicketsByParent(
            storyProposed.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => [taskChildDone]);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.getTicketById(storyProposed.id),
      expect: () => [
        const TicketsLoading(),
        TicketDetailLoaded(
          storyProposed,
          canAdvanceSddStage: true,
          needsDesignReview: false,
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'true for an epic with no stage yet (no precondition)',
      setUp: () {
        when(
          () => repository.getTicketById(epic.id),
        ).thenAnswer((_) async => epic);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.getTicketById(epic.id),
      expect: () => [
        const TicketsLoading(),
        TicketDetailLoaded(epic, canAdvanceSddStage: true),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'false for a story whose proposed stage has no done child tasks yet',
      setUp: () {
        when(
          () => repository.getTicketById(storyProposed.id),
        ).thenAnswer((_) async => storyProposed);
        when(
          () => repository.getTicketsByParent(
            storyProposed.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => []);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.getTicketById(storyProposed.id),
      expect: () => [
        const TicketsLoading(),
        TicketDetailLoaded(
          storyProposed,
          sddStageBlockReason: SddStageBlockReason.awaitingChildren,
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'false for a non-epic/story ticket type regardless of stage',
      setUp: () {
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
      },
      build: () => TicketsCubit(repository),
      act: (cubit) => cubit.getTicketById(ticket.id),
      expect: () => [const TicketsLoading(), TicketDetailLoaded(ticket)],
    );
  });

  group(
    'live-refresh an open ticket detail screen '
    '(live-refresh-open-ticket-detail-screen)',
    () {
      Future<TicketSearchPage> searchAnyArgs() => repository.searchTickets(
        query: any(named: 'query'),
        statuses: any(named: 'statuses'),
        types: any(named: 'types'),
        priorities: any(named: 'priorities'),
        sort: any(named: 'sort'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicketStatus live-refreshes an open Story detail screen '
        'when a direct Task child\'s status changes, flipping '
        'canAdvanceSddStage — via a transient TicketsLoading, since the '
        'write\'s own TicketStatusUpdated emission already overwrote '
        '`state` by the time the refresh check runs',
        setUp: () {
          final taskChildNowDone = taskChildNotDone.copyWith(
            status: TicketStatus.done,
          );
          when(
            () => repository.updateTicketStatus(
              taskChildNotDone.id,
              TicketStatus.done,
            ),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(taskChildNotDone.id),
          ).thenAnswer((_) async => taskChildNowDone);
          when(
            () => repository.getTicketById(storyProposed.id),
          ).thenAnswer((_) async => storyProposed);
          when(searchAnyArgs).thenAnswer(
            (_) async => TicketSearchPage(tickets: const [], hasMore: false),
          );
          when(
            () => repository.getTicketsByParent(
              storyProposed.id,
              types: any(named: 'types'),
            ),
          ).thenAnswer((_) async => [taskChildDone, taskChildNowDone]);
        },
        build: () => TicketsCubit(repository),
        seed: () => TicketDetailLoaded(storyProposed),
        act: (cubit) =>
            cubit.updateTicketStatus(taskChildNotDone.id, TicketStatus.done),
        wait: const Duration(milliseconds: 10),
        expect: () => [
          const TicketStatusUpdating([]),
          const TicketStatusUpdated([], hasMore: false),
          const TicketsLoading(),
          TicketDetailLoaded(
            storyProposed,
            canAdvanceSddStage: true,
            needsDesignReview: false,
          ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicketStatus live-refreshes the same ticket\'s own '
        'already-open detail screen',
        setUp: () {
          final done = ticket.copyWith(status: TicketStatus.done);
          when(
            () => repository.updateTicketStatus(ticket.id, TicketStatus.done),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(ticket.id),
          ).thenAnswer((_) async => done);
          when(searchAnyArgs).thenAnswer(
            (_) async => TicketSearchPage(tickets: const [], hasMore: false),
          );
        },
        build: () => TicketsCubit(repository),
        seed: () => TicketDetailLoaded(ticket),
        act: (cubit) => cubit.updateTicketStatus(ticket.id, TicketStatus.done),
        wait: const Duration(milliseconds: 10),
        expect: () => [
          const TicketStatusUpdating([]),
          const TicketStatusUpdated([], hasMore: false),
          const TicketsLoading(),
          TicketDetailLoaded(ticket.copyWith(status: TicketStatus.done)),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicketStatus attempts no refresh when no detail screen is '
        'open',
        setUp: () {
          when(
            () =>
                repository.updateTicketStatus(otherTask.id, TicketStatus.done),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(otherTask.id),
          ).thenAnswer((_) async => otherTask.copyWith(status: TicketStatus.done));
          when(searchAnyArgs).thenAnswer(
            (_) async => TicketSearchPage(tickets: const [], hasMore: false),
          );
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketStatus(otherTask.id, TicketStatus.done),
        wait: const Duration(milliseconds: 10),
        verify: (_) {
          verifyNever(
            () => repository.getTicketsByParent(
              any(),
              types: any(named: 'types'),
            ),
          );
        },
        expect: () => [
          const TicketStatusUpdating([]),
          const TicketStatusUpdated([], hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicketStatus checks but does not refresh an open Story '
        'detail screen when the written ticket is not one of its '
        'children',
        setUp: () {
          when(
            () =>
                repository.updateTicketStatus(otherTask.id, TicketStatus.done),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(otherTask.id),
          ).thenAnswer((_) async => otherTask.copyWith(status: TicketStatus.done));
          when(searchAnyArgs).thenAnswer(
            (_) async => TicketSearchPage(tickets: const [], hasMore: false),
          );
          when(
            () => repository.getTicketsByParent(
              storyProposed.id,
              types: any(named: 'types'),
            ),
          ).thenAnswer((_) async => [taskChildDone, taskChildNotDone]);
        },
        build: () => TicketsCubit(repository),
        seed: () => TicketDetailLoaded(storyProposed),
        act: (cubit) => cubit.updateTicketStatus(otherTask.id, TicketStatus.done),
        wait: const Duration(milliseconds: 10),
        expect: () => [
          const TicketStatusUpdating([]),
          const TicketStatusUpdated([], hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'updateTicketStatus skips the children query entirely when the '
        'open detail screen isn\'t a story',
        setUp: () {
          when(
            () =>
                repository.updateTicketStatus(otherTask.id, TicketStatus.done),
          ).thenAnswer((_) async {});
          when(
            () => repository.getTicketById(otherTask.id),
          ).thenAnswer((_) async => otherTask.copyWith(status: TicketStatus.done));
          when(searchAnyArgs).thenAnswer(
            (_) async => TicketSearchPage(tickets: const [], hasMore: false),
          );
        },
        build: () => TicketsCubit(repository),
        seed: () => TicketDetailLoaded(ticket), // ticket.type == task
        act: (cubit) => cubit.updateTicketStatus(otherTask.id, TicketStatus.done),
        wait: const Duration(milliseconds: 10),
        verify: (_) {
          verifyNever(
            () => repository.getTicketsByParent(
              any(),
              types: any(named: 'types'),
            ),
          );
        },
        expect: () => [
          const TicketStatusUpdating([]),
          const TicketStatusUpdated([], hasMore: false),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'getTicketById skips TicketsLoading when re-entering for the '
        'ticket already shown, but still emits it when navigating to a '
        'different ticket',
        setUp: () {
          // Returns a genuinely refreshed value (not identical to the
          // seed) — Cubit.emit is a no-op for a value equal to the
          // current state, which would otherwise make the first
          // re-entry's emission invisible to this test for the wrong
          // reason (deduped, not because Loading was skipped).
          when(() => repository.getTicketById(ticket.id)).thenAnswer(
            (_) async => ticket.copyWith(title: 'Refreshed'),
          );
          when(
            () => repository.getTicketById(otherTask.id),
          ).thenAnswer((_) async => otherTask);
        },
        build: () => TicketsCubit(repository),
        seed: () => TicketDetailLoaded(ticket),
        act: (cubit) async {
          await cubit.getTicketById(ticket.id);
          await cubit.getTicketById(otherTask.id);
        },
        expect: () => [
          TicketDetailLoaded(ticket.copyWith(title: 'Refreshed')),
          const TicketsLoading(),
          TicketDetailLoaded(otherTask),
        ],
      );
    },
  );

  group('per-phase model routing (per-phase-tier-based-model-routing)', () {
    late MockAgentModelClient agentClient;
    late MockProviderRegistry registry;
    late MockCommentRepository commentRepository;
    late MockTicketLinkRepository linkRepository;
    late MockAutomationSettingsRepository automationSettingsRepository;
    late MockModelRoutingRepository modelRoutingRepository;
    late MockGitRepositoryClient gitClient;
    late MockGitHubCliClient gitHubClient;
    late MockBaselineRepository baselineRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
      registry = buildProviderStack(agentClient).registry;
      commentRepository = MockCommentRepository();
      linkRepository = MockTicketLinkRepository();
      automationSettingsRepository = MockAutomationSettingsRepository();
      modelRoutingRepository = MockModelRoutingRepository();
      gitClient = MockGitRepositoryClient();
      gitHubClient = MockGitHubCliClient();
      baselineRepository = MockBaselineRepository();
      stubSuccessfulCodingExecutionInfra(gitClient, gitHubClient);
      stubEmptyBaseline(baselineRepository);
      when(
        () => agentClient.run(any()),
      ).thenAnswer((_) async => Stream.fromIterable(const [AgentDoneEvent()]));
      when(() => commentRepository.addComment(any())).thenAnswer((_) async {});
      when(() => repository.createTicket(any())).thenAnswer((_) async {});
      when(
        () => linkRepository.createLink(
          sourceTicketId: any(named: 'sourceTicketId'),
          targetTicketId: any(named: 'targetTicketId'),
          linkType: any(named: 'linkType'),
        ),
      ).thenAnswer((_) async {});
      // retryDesignSync's _assembleStageContext calls _linkedDesignPage,
      // which looks up links whenever a TicketLinkRepository is
      // configured (unlike the dedicated retryDesignSync test group
      // above, which omits linkRepository entirely).
      when(
        () => linkRepository.getLinksForTicket(any()),
      ).thenAnswer((_) async => []);
      when(
        () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
      ).thenAnswer((_) async => _opus);
      when(
        () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
      ).thenAnswer((_) async => _haiku);
      when(
        () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
      ).thenAnswer((_) async => _sonnet);
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      linkRepository: linkRepository,
      providerRegistry: registry,
      commentRepository: commentRepository,
      automationSettingsRepository: automationSettingsRepository,
      modelRoutingRepository: modelRoutingRepository,
      projectRootPath: '/fake/project/root',
      gitClient: gitClient,
      gitHubClient: gitHubClient,
      baselineRepository: baselineRepository,
      projectId: 'project-1',
      baselineVersion: '0.1.0',
    );

    blocTest<TicketsCubit, TicketsState>(
      '_spawnStageChat resolves ModelPhase.frontier for an exploring-stage '
      'transition',
      setUp: () {
        final advancedEpic = Ticket(
          id: epic.id,
          ticketId: epic.ticketId,
          type: epic.type,
          title: epic.title,
          status: epic.status,
          sddStage: SddStage.exploring,
          createdAt: epic.createdAt,
          updatedAt: epic.updatedAt,
        );
        when(
          () => repository.updateTicketSddStage(epic.id, SddStage.exploring),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(
          () => repository.getTicketById(epic.id),
        ).thenAnswer((_) async => advancedEpic);
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(epic),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
        ).called(1);
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>(
                (request) => request.model == _opus.modelId,
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      '_spawnStageChat resolves ModelPhase.capable for a designBrief-stage '
      'transition',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyProposed.id,
            types: any(named: 'types'),
          ),
        ).thenAnswer((_) async => [taskChildUi]);
        when(
          () => repository.updateTicketSddStage(
            storyProposed.id,
            SddStage.designBrief,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(any()),
        ).thenAnswer((_) async => dummyChatTicket);
        when(() => repository.getTicketById(storyProposed.id)).thenAnswer(
          (_) async => Ticket(
            id: storyProposed.id,
            ticketId: storyProposed.ticketId,
            type: storyProposed.type,
            title: storyProposed.title,
            status: storyProposed.status,
            sddStage: SddStage.designBrief,
            createdAt: storyProposed.createdAt,
            updatedAt: storyProposed.updatedAt,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.advanceSddStage(storyProposed),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).called(1);
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>(
                (request) => request.model == _haiku.modelId,
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'retryDesignSync resolves ModelPhase.capable',
      setUp: () {
        when(
          () => repository.getTicketById(storyDesignSync.id),
        ).thenAnswer((_) async => storyDesignSync);
        // _toolsFor (mid-task-chat-branching) reads the chat itself first
        // to resolve its own parent's type.
        when(
          () => repository.getTicketById(designSyncChat.id),
        ).thenAnswer((_) async => designSyncChat);
      },
      build: buildCubit,
      act: (cubit) => cubit.retryDesignSync(designSyncChat),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).called(1);
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>(
                (request) => request.model == _haiku.modelId,
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      '_runCodingExecution resolves ModelPhase.execution',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: TicketTypeHierarchy.executableTypes,
          ),
        ).thenAnswer((_) async => [taskUnderStory]);
        when(
          () => repository.getTicketsByParent(
            storyForExecution.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [designSyncChatForExecution]);
        when(
          () => commentRepository.getCommentsForTicket(
            designSyncChatForExecution.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c-model-routing',
              ticketId: designSyncChatForExecution.id,
              content: 'No issues found.\n\nDESIGN GATE: APPROVED',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(
          () => repository.getTicketsByParent(
            taskUnderStory.id,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [dummyExecutionChatTicket]);
        when(
          () => commentRepository.getCommentsForTicket(
            dummyExecutionChatTicket.id,
          ),
        ).thenAnswer((_) async => []);
        when(() => repository.getTicketById(any())).thenAnswer((
          invocation,
        ) async {
          final id = invocation.positionalArguments[0] as String;
          if (id == storyForExecution.id) return storyForExecution;
          if (id == taskUnderStory.id) {
            return taskUnderStory.copyWith(status: TicketStatus.inProgress);
          }
          return dummyExecutionChatTicket;
        });
        when(
          () => repository.updateTicketStatus(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecution,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecutionRetry,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderStory, TicketStatus.inProgress),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        // Resolved three times: once by _resolveExecutionChat's cap check
        // against the existing dummyExecutionChatTicket
        // (_effectiveExecutionContextCap needs the model to know its real
        // contextWindowTokens), then once each for the implement turn and
        // the agentic verify turn that follows it.
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).called(3);
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>(
                (request) =>
                    request.model == _sonnet.modelId &&
                    request.toolsEnabled == true,
              ),
            ),
          ),
        ).called(2);
      },
    );
  });

  group('blockedTicketIds (board-task-ordering-indication)', () {
    late MockTicketLinkRepository linkRepository;

    final blockerTicket = Ticket(
      id: 'blocker-1',
      ticketId: 'AIO-30',
      type: TicketType.task,
      title: 'Blocker task',
      status: TicketStatus.todo,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final blockedTicket = Ticket(
      id: 'blocked-1',
      ticketId: 'AIO-31',
      type: TicketType.task,
      title: 'Blocked task',
      status: TicketStatus.todo,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUp(() {
      linkRepository = MockTicketLinkRepository();
    });

    TicketsCubit buildCubit() =>
        TicketsCubit(repository, linkRepository: linkRepository);

    void stubSearch(List<Ticket> tickets) {
      when(
        () => repository.searchTickets(
          query: any(named: 'query'),
          statuses: any(named: 'statuses'),
          types: any(named: 'types'),
          priorities: any(named: 'priorities'),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer(
        (_) async => TicketSearchPage(tickets: tickets, hasMore: false),
      );
    }

    blocTest<TicketsCubit, TicketsState>(
      'a ticket with a blockedBy link to a non-done ticket appears in '
      'blockedTicketIds',
      setUp: () {
        stubSearch([blockerTicket, blockedTicket]);
        when(
          () => linkRepository.getLinksByTypes([
            TicketLinkType.blocks,
            TicketLinkType.blockedBy,
          ]),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: blockedTicket.id,
              targetTicketId: blockerTicket.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.searchTickets(),
      expect: () => [
        const TicketsLoading(),
        isA<TicketsLoaded>().having(
          (s) => s.blockedTicketIds,
          'blockedTicketIds',
          {blockedTicket.id},
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'the same link with the blocker done does not appear in '
      'blockedTicketIds',
      setUp: () {
        stubSearch([
          blockerTicket.copyWith(status: TicketStatus.done),
          blockedTicket,
        ]);
        when(
          () => linkRepository.getLinksByTypes([
            TicketLinkType.blocks,
            TicketLinkType.blockedBy,
          ]),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: blockedTicket.id,
              targetTicketId: blockerTicket.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.searchTickets(),
      expect: () => [
        const TicketsLoading(),
        isA<TicketsLoaded>().having(
          (s) => s.blockedTicketIds,
          'blockedTicketIds',
          isEmpty,
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'a blocks link (reversed direction) resolves the target as blocked',
      setUp: () {
        stubSearch([blockerTicket, blockedTicket]);
        when(
          () => linkRepository.getLinksByTypes([
            TicketLinkType.blocks,
            TicketLinkType.blockedBy,
          ]),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: blockerTicket.id,
              targetTicketId: blockedTicket.id,
              linkType: TicketLinkType.blocks.name,
            ),
          ],
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.searchTickets(),
      expect: () => [
        const TicketsLoading(),
        isA<TicketsLoaded>().having(
          (s) => s.blockedTicketIds,
          'blockedTicketIds',
          {blockedTicket.id},
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicketStatus moving a blocker to done removes the blockee '
      'from blockedTicketIds on the next TicketsLoaded emission',
      setUp: () {
        // updateTicketStatus's own success emission is TicketStatusUpdated
        // (list-shaped, not TicketsLoaded) — _refreshBlockedBoardState's
        // no-op-unless-TicketsLoaded guard means blockedTicketIds isn't
        // recomputed again until the next TicketsLoaded-producing call.
        // This mutable flag lets the searchTickets stub reflect the
        // persisted status change on that next call.
        var blockerStatus = TicketStatus.todo;
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            statuses: any(named: 'statuses'),
            types: any(named: 'types'),
            priorities: any(named: 'priorities'),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer(
          (_) async => TicketSearchPage(
            tickets: [
              blockerTicket.copyWith(status: blockerStatus),
              blockedTicket,
            ],
            hasMore: false,
          ),
        );
        when(
          () => linkRepository.getLinksByTypes([
            TicketLinkType.blocks,
            TicketLinkType.blockedBy,
          ]),
        ).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: blockedTicket.id,
              targetTicketId: blockerTicket.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(
          () => repository.updateTicketStatus(
            blockerTicket.id,
            TicketStatus.done,
          ),
        ).thenAnswer((_) async {
          blockerStatus = TicketStatus.done;
        });
        when(() => repository.getTicketById(blockerTicket.id)).thenAnswer(
          (_) async => blockerTicket.copyWith(status: blockerStatus),
        );
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.searchTickets();
        await cubit.updateTicketStatus(blockerTicket.id, TicketStatus.done);
        await cubit.searchTickets();
      },
      expect: () => [
        const TicketsLoading(),
        isA<TicketsLoaded>().having(
          (s) => s.blockedTicketIds,
          'blockedTicketIds',
          {blockedTicket.id},
        ),
        isA<TicketStatusUpdating>(),
        isA<TicketStatusUpdated>(),
        isA<TicketsLoaded>().having(
          (s) => s.blockedTicketIds,
          'blockedTicketIds',
          isEmpty,
        ),
      ],
    );
  });

  group('blockedByOpenDependency status-transition gate '
      '(blocked-ticket-transition-gate)', () {
    late MockTicketLinkRepository linkRepository;

    // An Epic — deliberately not a Task or Story — proving the gate
    // applies uniformly across every ticket type, not just the two the
    // source known gap named.
    final blockedEpic = Ticket(
      id: 'gate-epic-1',
      ticketId: 'AIO-50',
      type: TicketType.epic,
      title: 'Blocked epic',
      status: TicketStatus.todo,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final gateBlocker = Ticket(
      id: 'gate-blocker-1',
      ticketId: 'AIO-51',
      type: TicketType.task,
      title: 'Gate blocker',
      status: TicketStatus.todo,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUp(() {
      linkRepository = MockTicketLinkRepository();
    });

    TicketsCubit buildCubit() =>
        TicketsCubit(repository, linkRepository: linkRepository);

    void stubEmptySearch() {
      when(
        () => repository.searchTickets(
          query: any(named: 'query'),
          statuses: any(named: 'statuses'),
          types: any(named: 'types'),
          priorities: any(named: 'priorities'),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => const TicketSearchPage(tickets: [], hasMore: false),
      );
    }

    blocTest<TicketsCubit, TicketsState>(
      'updateTicketStatus rejects a blocked Epic moving to inProgress, '
      'without calling the repository',
      setUp: () {
        when(
          () => repository.getTicketById(blockedEpic.id),
        ).thenAnswer((_) async => blockedEpic);
        when(() => linkRepository.getLinksForTicket(blockedEpic.id)).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'gate-link-1',
              sourceTicketId: blockedEpic.id,
              targetTicketId: gateBlocker.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(
          () => repository.getTicketById(gateBlocker.id),
        ).thenAnswer((_) async => gateBlocker);
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.updateTicketStatus(blockedEpic.id, TicketStatus.inProgress),
      verify: (_) {
        verifyNever(() => repository.updateTicketStatus(any(), any()));
      },
      expect: () => [
        const TicketsError(
          '',
          reason: TicketsErrorReason.blockedByOpenDependency,
        ),
        TicketDetailLoaded(blockedEpic),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicketStatus proceeds when the blocking ticket is done',
      setUp: () {
        stubEmptySearch();
        when(
          () => repository.getTicketById(blockedEpic.id),
        ).thenAnswer((_) async => blockedEpic);
        when(() => linkRepository.getLinksForTicket(blockedEpic.id)).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'gate-link-2',
              sourceTicketId: blockedEpic.id,
              targetTicketId: gateBlocker.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(() => repository.getTicketById(gateBlocker.id)).thenAnswer(
          (_) async => gateBlocker.copyWith(status: TicketStatus.done),
        );
        when(
          () => repository.updateTicketStatus(
            blockedEpic.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.updateTicketStatus(blockedEpic.id, TicketStatus.inProgress),
      verify: (_) {
        verify(
          () => repository.updateTicketStatus(
            blockedEpic.id,
            TicketStatus.inProgress,
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicketStatus proceeds when the ticket has no blocks/blockedBy '
      'links at all',
      setUp: () {
        stubEmptySearch();
        when(
          () => repository.getTicketById(blockedEpic.id),
        ).thenAnswer((_) async => blockedEpic);
        when(
          () => linkRepository.getLinksForTicket(blockedEpic.id),
        ).thenAnswer((_) async => []);
        when(
          () => repository.updateTicketStatus(
            blockedEpic.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.updateTicketStatus(blockedEpic.id, TicketStatus.inProgress),
      verify: (_) {
        verify(
          () => repository.updateTicketStatus(
            blockedEpic.id,
            TicketStatus.inProgress,
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'updateTicketStatus never queries link data for a non-inProgress '
      'target status',
      setUp: () {
        stubEmptySearch();
        when(
          () =>
              repository.updateTicketStatus(blockedEpic.id, TicketStatus.todo),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(blockedEpic.id),
        ).thenAnswer((_) async => blockedEpic);
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.updateTicketStatus(blockedEpic.id, TicketStatus.todo),
      verify: (_) {
        verifyNever(() => linkRepository.getLinksForTicket(any()));
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'changeTicketStatus rejects a blocked Epic moving to inProgress, '
      'without calling the repository',
      setUp: () {
        when(() => linkRepository.getLinksForTicket(blockedEpic.id)).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'gate-link-3',
              sourceTicketId: blockedEpic.id,
              targetTicketId: gateBlocker.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(
          () => repository.getTicketById(gateBlocker.id),
        ).thenAnswer((_) async => gateBlocker);
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.changeTicketStatus(blockedEpic, TicketStatus.inProgress),
      verify: (_) {
        verifyNever(() => repository.updateTicketStatus(any(), any()));
      },
      expect: () => [
        const TicketsError(
          '',
          reason: TicketsErrorReason.blockedByOpenDependency,
        ),
        TicketDetailLoaded(blockedEpic),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'changeTicketStatus proceeds when the blocking ticket is done',
      setUp: () {
        when(() => linkRepository.getLinksForTicket(blockedEpic.id)).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'gate-link-4',
              sourceTicketId: blockedEpic.id,
              targetTicketId: gateBlocker.id,
              linkType: TicketLinkType.blockedBy.name,
            ),
          ],
        );
        when(() => repository.getTicketById(gateBlocker.id)).thenAnswer(
          (_) async => gateBlocker.copyWith(status: TicketStatus.done),
        );
        when(
          () => repository.updateTicketStatus(
            blockedEpic.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
        when(() => repository.getTicketById(blockedEpic.id)).thenAnswer(
          (_) async => blockedEpic.copyWith(status: TicketStatus.inProgress),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.changeTicketStatus(blockedEpic, TicketStatus.inProgress),
      verify: (_) {
        verify(
          () => repository.updateTicketStatus(
            blockedEpic.id,
            TicketStatus.inProgress,
          ),
        ).called(1);
      },
      expect: () => [
        TicketDetailLoaded(
          blockedEpic.copyWith(status: TicketStatus.inProgress),
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'changeTicketStatus proceeds when the ticket has no blocks/blockedBy '
      'links at all',
      setUp: () {
        when(
          () => linkRepository.getLinksForTicket(blockedEpic.id),
        ).thenAnswer((_) async => []);
        when(
          () => repository.updateTicketStatus(
            blockedEpic.id,
            TicketStatus.inProgress,
          ),
        ).thenAnswer((_) async {});
        when(() => repository.getTicketById(blockedEpic.id)).thenAnswer(
          (_) async => blockedEpic.copyWith(status: TicketStatus.inProgress),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.changeTicketStatus(blockedEpic, TicketStatus.inProgress),
      verify: (_) {
        verify(
          () => repository.updateTicketStatus(
            blockedEpic.id,
            TicketStatus.inProgress,
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'changeTicketStatus never queries link data for a non-inProgress '
      'target status',
      setUp: () {
        when(
          () =>
              repository.updateTicketStatus(blockedEpic.id, TicketStatus.todo),
        ).thenAnswer((_) async {});
        when(() => repository.getTicketById(blockedEpic.id)).thenAnswer(
          (_) async => blockedEpic.copyWith(status: TicketStatus.todo),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.changeTicketStatus(blockedEpic, TicketStatus.todo),
      verify: (_) {
        verifyNever(() => linkRepository.getLinksForTicket(any()));
      },
    );

    testWidgets(
      'ticketsErrorMessage resolves blockedByOpenDependency to the new '
      'localization string',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0xFF000000),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, _) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        );
        await tester.pump();

        expect(
          ticketsErrorMessage(
            capturedContext,
            TicketsErrorReason.blockedByOpenDependency,
          ),
          AppLocalizations.of(
            capturedContext,
          ).ticketBlockedByOpenDependencyError,
        );
      },
    );
  });

  group('decomposition materialization (board-task-ordering-indication)', () {
    late MockAgentModelClient agentClient;
    late MockProviderRegistry registry;
    late MockCommentRepository commentRepository;
    late MockTicketLinkRepository linkRepository;

    final decompEpic = Ticket(
      id: 'decomp-epic',
      ticketId: 'AIO-40',
      type: TicketType.epic,
      title: 'Epic to decompose',
      status: TicketStatus.backlog,
      sddStage: SddStage.exploring,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final existingChat = Ticket(
      id: 'decomp-existing-chat',
      ticketId: 'AIO-41',
      type: TicketType.chat,
      title: 'Exploring — Epic to decompose',
      status: TicketStatus.backlog,
      parentId: decompEpic.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final newStageChat = Ticket(
      id: 'decomp-new-chat',
      ticketId: 'AIO-42',
      type: TicketType.chat,
      title: 'Proposed — Epic to decompose',
      status: TicketStatus.backlog,
      parentId: decompEpic.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUp(() {
      agentClient = MockAgentModelClient();
      registry = buildProviderStack(agentClient).registry;
      commentRepository = MockCommentRepository();
      linkRepository = MockTicketLinkRepository();
      // TicketContextEnricher's structured-links pass (see
      // _assembleStageContext) queries this for every ticket it walks —
      // stub a default of no links so it doesn't need per-test wiring.
      when(
        () => linkRepository.getLinksForTicket(any()),
      ).thenAnswer((_) async => []);
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      providerRegistry: registry,
      commentRepository: commentRepository,
      linkRepository: linkRepository,
    );

    /// Wires the precondition (exploring → proposed needs the most
    /// recently created chat child to have an AI reply already), the
    /// stage transition's own persistence round trip, and the new stage
    /// chat's creation — everything short of the AI turn itself, which
    /// each test stubs with its own reply text via [agentClient.run].
    void stubAdvanceToProposed() {
      when(
        () => repository.updateTicketSddStage(decompEpic.id, SddStage.proposed),
      ).thenAnswer((_) async {});
      when(
        () => repository.getTicketById(any()),
      ).thenAnswer((_) async => newStageChat);
      when(() => repository.getTicketById(decompEpic.id)).thenAnswer(
        (_) async => Ticket(
          id: decompEpic.id,
          ticketId: decompEpic.ticketId,
          type: decompEpic.type,
          title: decompEpic.title,
          status: decompEpic.status,
          sddStage: SddStage.proposed,
          createdAt: decompEpic.createdAt,
          updatedAt: decompEpic.updatedAt,
        ),
      );
      when(
        () => repository.getTicketsByParent(
          decompEpic.id,
          types: const [TicketType.chat],
        ),
      ).thenAnswer((_) async => [existingChat]);
      when(
        () => commentRepository.getCommentsForTicket(existingChat.id),
      ).thenAnswer(
        (_) async => [
          TicketComment(
            id: 'existing-reply',
            ticketId: existingChat.id,
            content: 'An earlier AI reply.',
            authorType: CommentAuthorType.ai,
            createdAt: DateTime(2026),
          ),
        ],
      );
      when(() => repository.createTicket(any())).thenAnswer((_) async {});
    }

    test(
      'a successful proposed-stage turn materializes one child ticket per '
      'parsed line, and a blockedBy link for the resolvable sibling title',
      () async {
        stubAdvanceToProposed();
        stubStatefulComments(commentRepository, newStageChat.id);
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent(
              'Here is the plan.\n\n'
              '## Decomposition\n'
              '- Story: Build backend\n'
              '- Story: Build UI (blockedBy: Build backend)\n',
            ),
            AgentDoneEvent(),
          ]),
        );
        final createdTickets = <Ticket>[];
        when(() => repository.createTicket(any())).thenAnswer((
          invocation,
        ) async {
          final t = invocation.positionalArguments[0] as Ticket;
          createdTickets.add(t);
        });

        final cubit = buildCubit();
        addTearDown(cubit.close);
        await cubit.advanceSddStage(decompEpic);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 1 for the stage chat itself (_createStageChat) + 2 decomposition
        // children.
        final children = createdTickets
            .where(
              (t) => t.parentId == decompEpic.id && t.type == TicketType.story,
            )
            .toList();
        expect(children, hasLength(2));
        final backend = children.firstWhere((t) => t.title == 'Build backend');
        final ui = children.firstWhere((t) => t.title == 'Build UI');

        verify(
          () => linkRepository.createLink(
            sourceTicketId: ui.id,
            targetTicketId: backend.id,
            linkType: TicketLinkType.blockedBy,
          ),
        ).called(1);
      },
    );

    test('an unresolved blockedByTitle still creates the child ticket, just '
        'no link', () async {
      stubAdvanceToProposed();
      stubStatefulComments(commentRepository, newStageChat.id);
      when(() => agentClient.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [
          AgentTextEvent(
            '## Decomposition\n'
            '- Story: Build UI (blockedBy: Nonexistent sibling)\n',
          ),
          AgentDoneEvent(),
        ]),
      );
      final createdTickets = <Ticket>[];
      when(() => repository.createTicket(any())).thenAnswer((invocation) async {
        final t = invocation.positionalArguments[0] as Ticket;
        createdTickets.add(t);
      });

      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.advanceSddStage(decompEpic);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final children = createdTickets
          .where(
            (t) => t.parentId == decompEpic.id && t.type == TicketType.story,
          )
          .toList();
      expect(children, hasLength(1));
      expect(children.single.title, 'Build UI');
      verifyNever(
        () => linkRepository.createLink(
          sourceTicketId: any(named: 'sourceTicketId'),
          targetTicketId: any(named: 'targetTicketId'),
          linkType: any(named: 'linkType'),
        ),
      );
    });

    test('a reply with no Decomposition block creates no child tickets '
        '(silent no-op, not an error)', () async {
      stubAdvanceToProposed();
      stubStatefulComments(commentRepository, newStageChat.id);
      when(() => agentClient.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [
          AgentTextEvent('Just some plain-text thoughts, no block at all.'),
          AgentDoneEvent(),
        ]),
      );
      final createdTickets = <Ticket>[];
      when(() => repository.createTicket(any())).thenAnswer((invocation) async {
        final t = invocation.positionalArguments[0] as Ticket;
        createdTickets.add(t);
      });

      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.advanceSddStage(decompEpic);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        createdTickets.where(
          (t) => t.parentId == decompEpic.id && t.type == TicketType.story,
        ),
        isEmpty,
      );
    });

    test('a stage advance other than proposed never materializes, even if the '
        'reply happens to contain a Decomposition-shaped block', () async {
      // null -> exploring: no precondition, mirrors the existing
      // 'advanceSddStage — backgrounded stage-chat turn' happy path.
      final freshEpic = Ticket(
        id: 'fresh-epic',
        ticketId: 'AIO-43',
        type: TicketType.epic,
        title: 'Fresh epic',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      when(
        () => repository.updateTicketSddStage(freshEpic.id, SddStage.exploring),
      ).thenAnswer((_) async {});
      when(
        () => repository.getTicketById(any()),
      ).thenAnswer((_) async => newStageChat);
      when(() => repository.getTicketById(freshEpic.id)).thenAnswer(
        (_) async => Ticket(
          id: freshEpic.id,
          ticketId: freshEpic.ticketId,
          type: freshEpic.type,
          title: freshEpic.title,
          status: freshEpic.status,
          sddStage: SddStage.exploring,
          createdAt: freshEpic.createdAt,
          updatedAt: freshEpic.updatedAt,
        ),
      );
      when(() => repository.createTicket(any())).thenAnswer((_) async {});
      stubStatefulComments(commentRepository, newStageChat.id);
      when(() => agentClient.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [
          AgentTextEvent('## Decomposition\n- Story: Should not be created\n'),
          AgentDoneEvent(),
        ]),
      );
      final createdTickets = <Ticket>[];
      when(() => repository.createTicket(any())).thenAnswer((invocation) async {
        final t = invocation.positionalArguments[0] as Ticket;
        createdTickets.add(t);
      });

      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.advanceSddStage(freshEpic);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        createdTickets.where(
          (t) => t.parentId == freshEpic.id && t.type == TicketType.story,
        ),
        isEmpty,
      );
    });
  });

  group('parallel-work scheduling/cancellation/restore', () {
    late MockAgentModelClient agentClient;
    late MockProviderRegistry registry;
    late MockCommentRepository commentRepository;
    late MockGitRepositoryClient gitClient;
    late MockGitHubCliClient gitHubClient;
    late MockBaselineRepository baselineRepository;
    late MockExecutionSchedulingRepository schedulingRepository;
    late MockAutomationSettingsRepository automationSettingsRepository;
    late MockExecutionQueueRepository executionQueueRepository;

    // Tracks each task fixture's *live* status, mutable per-test (e.g. the
    // restoreExecutionQueue tests below simulate a Task interrupted mid-
    // execution by pre-setting its live status to inProgress before
    // restoring) — see the outer setUp's `repository.getTicketById`/
    // `repository.updateTicketStatus` stubs, which both read/write it.
    late Map<String, TicketStatus> liveStatus;

    final parentEpic = Ticket(
      id: 'sched-parent-epic',
      ticketId: 'AIO-SCHED-EPIC',
      type: TicketType.epic,
      title: 'Parent epic',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final siblingA = Ticket(
      id: 'sched-sibling-a',
      ticketId: 'AIO-SCHED-A',
      type: TicketType.task,
      title: 'Sibling A',
      status: TicketStatus.backlog,
      parentId: parentEpic.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final siblingB = Ticket(
      id: 'sched-sibling-b',
      ticketId: 'AIO-SCHED-B',
      type: TicketType.task,
      title: 'Sibling B',
      status: TicketStatus.backlog,
      parentId: parentEpic.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final unrelatedTaskC = Ticket(
      id: 'sched-task-c',
      ticketId: 'AIO-SCHED-C',
      type: TicketType.task,
      title: 'Unrelated task C',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUp(() {
      agentClient = MockAgentModelClient();
      registry = buildProviderStack(agentClient).registry;
      commentRepository = MockCommentRepository();
      gitClient = MockGitRepositoryClient();
      gitHubClient = MockGitHubCliClient();
      baselineRepository = MockBaselineRepository();
      schedulingRepository = MockExecutionSchedulingRepository();
      automationSettingsRepository = MockAutomationSettingsRepository();
      executionQueueRepository = MockExecutionQueueRepository();
      stubSuccessfulCodingExecutionInfra(gitClient, gitHubClient);
      stubEmptyBaseline(baselineRepository);

      final byId = {
        parentEpic.id: parentEpic,
        siblingA.id: siblingA,
        siblingB.id: siblingB,
        unrelatedTaskC.id: unrelatedTaskC,
      };
      // So a pre-transition read (the one `_interceptTaskExecutionTrigger`
      // captures into `_preExecutionStatus`) sees the real prior status,
      // not `inProgress` from the very first lookup.
      liveStatus = <String, TicketStatus>{
        for (final entry in byId.entries) entry.key: entry.value.status,
      };
      when(() => repository.getTicketById(any())).thenAnswer((
        invocation,
      ) async {
        final id = invocation.positionalArguments[0] as String;
        final base = byId[id];
        if (base != null) return base.copyWith(status: liveStatus[id]);
        // Anything else is a freshly created execution chat's own id.
        return Ticket(
          id: id,
          ticketId: '',
          type: TicketType.chat,
          title: 'Coding Execution — synthetic',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
      });
      when(
        () => repository.updateTicketStatus(any(), any()),
      ).thenAnswer((invocation) async {
        final id = invocation.positionalArguments[0] as String;
        final status = invocation.positionalArguments[1] as TicketStatus;
        if (liveStatus.containsKey(id)) liveStatus[id] = status;
      });
      when(
        () => repository.getTicketsByParent(any(), types: const [TicketType.chat]),
      ).thenAnswer((_) async => []);
      when(() => repository.createTicket(any())).thenAnswer((_) async {});
      when(
        () => repository.searchTickets(
          query: any(named: 'query'),
          statuses: any(named: 'statuses'),
          types: any(named: 'types'),
          priorities: any(named: 'priorities'),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => const TicketSearchPage(tickets: [], hasMore: false));
      when(() => commentRepository.addComment(any())).thenAnswer((_) async {});
      when(() => commentRepository.getCommentsForTicket(any())).thenAnswer(
        (_) async => [],
      );
      // Every run just hangs forever — never emits, never closes — so a
      // triggered run's implement turn stays "in flight" for the whole
      // test, letting these tests assert on TicketsCubit's scheduling
      // decisions without needing any run to actually complete.
      when(() => agentClient.run(any())).thenAnswer(
        (_) async =>
            Stream<AgentEvent>.fromFuture(Completer<AgentEvent>().future),
      );
    });

    TicketsCubit buildSchedulingCubit({
      ExecutionSchedulingRepository? executionSchedulingRepository,
      ExecutionQueueRepository? executionQueueRepository,
      AutomationSettingsRepository? automationSettingsRepository,
    }) => TicketsCubit(
      repository,
      providerRegistry: registry,
      commentRepository: commentRepository,
      automationSettingsRepository: automationSettingsRepository,
      projectRootPath: '/fake/project/root',
      gitClient: gitClient,
      gitHubClient: gitHubClient,
      baselineRepository: baselineRepository,
      projectId: 'project-1',
      baselineVersion: '0.1.0',
      executionSchedulingRepository: executionSchedulingRepository,
      executionQueueRepository: executionQueueRepository,
    );

    test(
      'ExecutionSchedulingMode.strictFifo: a second Task stays queued '
      "behind the first, even though nothing links them (today's default, "
      'unchanged)',
      () async {
        when(
          () => schedulingRepository.getMode(),
        ).thenAnswer((_) async => ExecutionSchedulingMode.strictFifo);
        when(
          () => schedulingRepository.getConcurrencyCeiling(),
        ).thenAnswer((_) async => 2); // Ignored under strictFifo.

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
        );
        addTearDown(cubit.close);

        await cubit.updateTicketStatus(siblingA.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.updateTicketStatus(unrelatedTaskC.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await cubit.getTicketById(siblingA.id);
        expect((cubit.state as TicketDetailLoaded).isExecuting, isTrue);

        await cubit.getTicketById(unrelatedTaskC.id);
        final taskCState = cubit.state as TicketDetailLoaded;
        expect(taskCState.isExecuting, isFalse);
        expect(taskCState.executionQueuePosition, 1);

        verify(() => agentClient.run(any())).called(1);
      },
    );

    test(
      'ExecutionSchedulingMode.parallel: two unrelated Tasks both run '
      'concurrently',
      () async {
        when(
          () => schedulingRepository.getMode(),
        ).thenAnswer((_) async => ExecutionSchedulingMode.parallel);
        when(
          () => schedulingRepository.getConcurrencyCeiling(),
        ).thenAnswer((_) async => 2);

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
        );
        addTearDown(cubit.close);

        await cubit.updateTicketStatus(siblingA.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.updateTicketStatus(unrelatedTaskC.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await cubit.getTicketById(siblingA.id);
        expect((cubit.state as TicketDetailLoaded).isExecuting, isTrue);

        await cubit.getTicketById(unrelatedTaskC.id);
        expect((cubit.state as TicketDetailLoaded).isExecuting, isTrue);

        verify(() => agentClient.run(any())).called(2);
      },
    );

    test(
      'ExecutionSchedulingMode.hybrid: a same-parent sibling serializes '
      'behind its in-flight counterpart, while an unrelated queued Task '
      'starts immediately (skip-ahead)',
      () async {
        when(
          () => schedulingRepository.getMode(),
        ).thenAnswer((_) async => ExecutionSchedulingMode.hybrid);
        when(
          () => schedulingRepository.getConcurrencyCeiling(),
        ).thenAnswer((_) async => 2);

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
        );
        addTearDown(cubit.close);

        await cubit.updateTicketStatus(siblingA.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.updateTicketStatus(siblingB.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.updateTicketStatus(unrelatedTaskC.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await cubit.getTicketById(siblingA.id);
        expect((cubit.state as TicketDetailLoaded).isExecuting, isTrue);

        await cubit.getTicketById(siblingB.id);
        final siblingBState = cubit.state as TicketDetailLoaded;
        expect(siblingBState.isExecuting, isFalse);
        expect(siblingBState.executionQueuePosition, 1);

        await cubit.getTicketById(unrelatedTaskC.id);
        expect((cubit.state as TicketDetailLoaded).isExecuting, isTrue);

        verify(() => agentClient.run(any())).called(2);
      },
    );

    test(
      'searchTickets seeds TicketsLoaded.inFlightExecutionIds/'
      'executionQueuePositions from already-in-flight/queued state — a '
      'fresh Board load reflects runs that started before it, not just '
      'runs that start while it is already showing',
      () async {
        // Regression coverage for a /verify finding: _refreshInFlightBoardState
        // can only ever *update* an already-emitted TicketsLoaded — it's a
        // no-op otherwise — so searchTickets (the sole method that emits a
        // *fresh* TicketsLoaded) is the only place that can seed these
        // fields for a just-opened/just-filtered Board. Before this fix,
        // searchTickets always emitted them at their `const {}` defaults,
        // so a Task already running/queued at the moment the Board loads
        // showed no Running/Queued badge and no cancel affordance. Added
        // for `aion-arch/changes/parallel-work` post-/verify.
        when(
          () => schedulingRepository.getMode(),
        ).thenAnswer((_) async => ExecutionSchedulingMode.strictFifo);
        when(
          () => schedulingRepository.getConcurrencyCeiling(),
        ).thenAnswer((_) async => 1);

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
        );
        addTearDown(cubit.close);

        await cubit.updateTicketStatus(siblingA.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.updateTicketStatus(unrelatedTaskC.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Simulates navigating to (or back to) the Board — a fresh
        // TicketsLoaded, not a refresh of one already on screen.
        await cubit.searchTickets();

        final loaded = cubit.state as TicketsLoaded;
        expect(loaded.inFlightExecutionIds, contains(siblingA.id));
        expect(loaded.executionQueuePositions[unrelatedTaskC.id], 1);
      },
    );

    test(
      'cancelCodingExecution reverts a still-queued Task to its '
      'pre-trigger status and drops it from the queue',
      () async {
        when(
          () => schedulingRepository.getMode(),
        ).thenAnswer((_) async => ExecutionSchedulingMode.strictFifo);
        when(
          () => schedulingRepository.getConcurrencyCeiling(),
        ).thenAnswer((_) async => 1);

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
        );
        addTearDown(cubit.close);

        await cubit.updateTicketStatus(siblingA.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.updateTicketStatus(unrelatedTaskC.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.getTicketById(unrelatedTaskC.id);
        expect(
          (cubit.state as TicketDetailLoaded).executionQueuePosition,
          1,
        );

        await cubit.cancelCodingExecution(
          unrelatedTaskC.copyWith(status: TicketStatus.inProgress),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        verify(
          () => repository.updateTicketStatus(
            unrelatedTaskC.id,
            TicketStatus.backlog,
          ),
        ).called(1);
        // Regression coverage for a /verify finding: this comment was
        // missing entirely from the queued-cancel path despite design.md
        // §5.4 documenting it. Added for
        // `aion-arch/changes/parallel-work` post-/verify.
        verify(
          () => commentRepository.addComment(
            any(
              that: predicate<TicketComment>(
                (c) =>
                    c.content == 'Execution cancelled before it started.' &&
                    c.authorType == CommentAuthorType.system,
              ),
            ),
          ),
        ).called(1);
        await cubit.getTicketById(unrelatedTaskC.id);
        final afterCancel = cubit.state as TicketDetailLoaded;
        expect(afterCancel.isExecuting, isFalse);
        expect(afterCancel.executionQueuePosition, isNull);
      },
    );

    test(
      'cancelCodingExecution signals AgentModelClient.cancel with the '
      "in-flight run's current runId",
      () async {
        when(
          () => schedulingRepository.getMode(),
        ).thenAnswer((_) async => ExecutionSchedulingMode.strictFifo);
        when(
          () => schedulingRepository.getConcurrencyCeiling(),
        ).thenAnswer((_) async => 1);

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
        );
        addTearDown(cubit.close);

        await cubit.updateTicketStatus(siblingA.id, TicketStatus.inProgress);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.getTicketById(siblingA.id);
        expect((cubit.state as TicketDetailLoaded).isExecuting, isTrue);

        await cubit.cancelCodingExecution(
          siblingA.copyWith(status: TicketStatus.inProgress),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final capturedRunId =
            verify(() => agentClient.cancel(captureAny())).captured.single
                as String;
        expect(capturedRunId, isNotEmpty);
      },
    );

    test(
      'restoreExecutionQueue (auto): resumes a surviving interrupted run '
      'immediately, with no resume prompt',
      () async {
        // Simulates a Task the app left `inProgress` mid-execution before
        // an interrupting restart.
        liveStatus[siblingA.id] = TicketStatus.inProgress;
        when(
          () => executionQueueRepository.getSnapshot(),
        ).thenAnswer(
          (_) async => [
            const ExecutionQueueEntry(taskId: 'sched-sibling-a', inFlight: true),
          ],
        );
        when(
          () => executionQueueRepository.replaceSnapshot(any()),
        ).thenAnswer((_) async {});
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecutionResume,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(
          () => schedulingRepository.getMode(),
        ).thenAnswer((_) async => ExecutionSchedulingMode.strictFifo);
        when(
          () => schedulingRepository.getConcurrencyCeiling(),
        ).thenAnswer((_) async => 1);

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
          executionQueueRepository: executionQueueRepository,
          automationSettingsRepository: automationSettingsRepository,
        );
        addTearDown(cubit.close);

        await cubit.restoreExecutionQueue();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await cubit.getTicketById(siblingA.id);

        expect((cubit.state as TicketDetailLoaded).isExecuting, isTrue);
        await cubit.searchTickets();
        expect((cubit.state as TicketsLoaded).pendingResumePrompt, isEmpty);
      },
    );

    test(
      'restoreExecutionQueue (gated): surfaces the surviving run via '
      'pendingResumePrompt without starting it',
      () async {
        // Simulates a Task the app left `inProgress` mid-execution before
        // an interrupting restart.
        liveStatus[siblingA.id] = TicketStatus.inProgress;
        when(
          () => executionQueueRepository.getSnapshot(),
        ).thenAnswer(
          (_) async => [
            const ExecutionQueueEntry(taskId: 'sched-sibling-a', inFlight: true),
          ],
        );
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecutionResume,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
          executionQueueRepository: executionQueueRepository,
          automationSettingsRepository: automationSettingsRepository,
        );
        addTearDown(cubit.close);

        await cubit.restoreExecutionQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.searchTickets();

        final loaded = cubit.state as TicketsLoaded;
        expect(loaded.pendingResumePrompt.map((t) => t.id), [siblingA.id]);
        verifyNever(() => agentClient.run(any()));
      },
    );

    test(
      'restoreExecutionQueue (manual): clears the persisted snapshot and '
      'starts nothing, no resume prompt',
      () async {
        // Simulates a Task the app left `inProgress` mid-execution before
        // an interrupting restart.
        liveStatus[siblingA.id] = TicketStatus.inProgress;
        when(
          () => executionQueueRepository.getSnapshot(),
        ).thenAnswer(
          (_) async => [
            const ExecutionQueueEntry(taskId: 'sched-sibling-a', inFlight: true),
          ],
        );
        when(
          () => executionQueueRepository.replaceSnapshot(any()),
        ).thenAnswer((_) async {});
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecutionResume,
          ),
        ).thenAnswer((_) async => AutomationConfidence.manual);

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
          executionQueueRepository: executionQueueRepository,
          automationSettingsRepository: automationSettingsRepository,
        );
        addTearDown(cubit.close);

        await cubit.restoreExecutionQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.searchTickets();

        expect((cubit.state as TicketsLoaded).pendingResumePrompt, isEmpty);
        verifyNever(() => agentClient.run(any()));
        verify(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecutionResume,
          ),
        ).called(1);
        verify(() => executionQueueRepository.replaceSnapshot([])).called(1);
      },
    );

    test(
      'restoreExecutionQueue drops a stale entry whose ticket is no '
      'longer inProgress, clearing the snapshot without surfacing '
      'anything',
      () async {
        when(
          () => executionQueueRepository.getSnapshot(),
        ).thenAnswer(
          (_) async => [
            const ExecutionQueueEntry(taskId: 'no-longer-running', inFlight: true),
          ],
        );
        when(
          () => executionQueueRepository.replaceSnapshot(any()),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById('no-longer-running'),
        ).thenAnswer(
          (_) async => Ticket(
            id: 'no-longer-running',
            ticketId: 'AIO-SCHED-STALE',
            type: TicketType.task,
            title: 'No longer running',
            status: TicketStatus.done,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );

        final cubit = buildSchedulingCubit(
          executionSchedulingRepository: schedulingRepository,
          executionQueueRepository: executionQueueRepository,
          automationSettingsRepository: automationSettingsRepository,
        );
        addTearDown(cubit.close);

        await cubit.restoreExecutionQueue();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cubit.searchTickets();

        expect((cubit.state as TicketsLoaded).pendingResumePrompt, isEmpty);
        verifyNever(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.codingExecutionResume,
          ),
        );
        verify(() => executionQueueRepository.replaceSnapshot([])).called(1);
      },
    );
  });
}
