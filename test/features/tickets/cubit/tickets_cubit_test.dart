import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/database/app_database.dart';
import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/core/git/github_cli_client.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

class MockTicketGitProjector extends Mock implements TicketGitProjector {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockCommentRepository extends Mock implements CommentRepository {}

class MockAutomationSettingsRepository extends Mock
    implements AutomationSettingsRepository {}

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

class MockGitRepositoryClient extends Mock implements GitRepositoryClient {}

class MockGitHubCliClient extends Mock implements GitHubCliClient {}

class MockBaselineRepository extends Mock implements BaselineRepository {}

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
  final signalTicket = Ticket(
    id: '10',
    ticketId: 'AIO-10',
    type: TicketType.signal,
    title: 'Signal ticket',
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
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const AgentRequest(prompt: '', model: ''));
    registerFallbackValue(SddStage.exploring);
    registerFallbackValue(<TicketType>[]);
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
  });

  group('TicketsCubit', () {
    blocTest<TicketsCubit, TicketsState>(
      'searchTickets from TicketsInitial emits [TicketsLoading, TicketsLoaded] on success',
      setUp: () {
        when(
          () => repository.searchTickets(
            query: any(named: 'query'),
            status: any(named: 'status'),
            type: any(named: 'type'),
            priority: any(named: 'priority'),
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
            status: any(named: 'status'),
            type: any(named: 'type'),
            priority: any(named: 'priority'),
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
            status: any(named: 'status'),
            type: any(named: 'type'),
            priority: any(named: 'priority'),
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
            status: any(named: 'status'),
            type: any(named: 'type'),
            priority: any(named: 'priority'),
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
            status: any(named: 'status'),
            type: any(named: 'type'),
            priority: any(named: 'priority'),
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
            status: any(named: 'status'),
            type: any(named: 'type'),
            priority: any(named: 'priority'),
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
            status: any(named: 'status'),
            type: any(named: 'type'),
            priority: any(named: 'priority'),
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

    group('loadMoreTickets', () {
      blocTest<TicketsCubit, TicketsState>(
        'appends the next page and emits TicketsLoaded with the combined list',
        setUp: () {
          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
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
              status: null,
              type: null,
              priority: null,
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
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
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
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
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
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
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
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
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
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).thenAnswer((_) => loadMoreCompleter.future);

          final loadMoreFuture = cubit.loadMoreTickets();
          expect(cubit.state, TicketsLoadingMore([ticket]));

          when(
            () => repository.searchTickets(
              query: any(named: 'query'),
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
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
        'rejects reparenting a signal ticket without calling the repository',
        setUp: () {
          when(
            () => repository.getTicketById(signalTicket.id),
          ).thenAnswer((_) async => signalTicket);
        },
        build: () => TicketsCubit(repository),
        act: (cubit) => cubit.updateTicketParent(signalTicket, unrelated.id),
        verify: (_) {
          verifyNever(() => repository.updateTicketParent(any(), any()));
        },
        expect: () => [
          const TicketsError('', reason: TicketsErrorReason.invalidParent),
          TicketDetailLoaded(signalTicket),
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
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
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
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
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
              status: any(named: 'status'),
              type: any(named: 'type'),
              priority: any(named: 'priority'),
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
  });

  group('loadDocumentRelations', () {
    late MockTicketLinkRepository linkRepository;

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
    });

    setUp(() {
      linkRepository = MockTicketLinkRepository();
    });

    TicketsCubit buildCubit() =>
        TicketsCubit(repository, linkRepository: linkRepository);

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
        TicketDetailLoaded(
          page,
          childDocs: [childPage],
          linkedTickets: [linkedTask],
          backlinks: [backlinkPage],
        ),
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
          (s) => s.linkedTickets.map((t) => t.id),
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
  });

  group('advanceSddStage', () {
    late MockAgentModelClient agentClient;
    late MockCommentRepository commentRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
      commentRepository = MockCommentRepository();
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      agentClient: agentClient,
      commentRepository: commentRepository,
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
      'precondition is met, falling back to AgentModel.sonnet when no '
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
                (request) => request.model == AgentModel.sonnet.id,
              ),
            ),
          ),
        ).called(1);
      },
    );
  });

  group('advanceSddStage — design gate (designBrief/designSync)', () {
    late MockAgentModelClient agentClient;
    late MockCommentRepository commentRepository;
    late MockTicketLinkRepository linkRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
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
      agentClient: agentClient,
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
      // No linkRepository this time — only agentClient/commentRepository.
      build: () => TicketsCubit(
        repository,
        agentClient: agentClient,
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
    late MockCommentRepository commentRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
      commentRepository = MockCommentRepository();
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      agentClient: agentClient,
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
      expect: () => [
        isA<TicketDetailLoaded>().having(
          (s) => s.isAdvancingStage,
          'isAdvancingStage',
          true,
        ),
        const TicketsLoading(),
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
    late MockCommentRepository commentRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
      commentRepository = MockCommentRepository();
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      agentClient: agentClient,
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

  group('coding-execution trigger', () {
    late MockAgentModelClient agentClient;
    late MockCommentRepository commentRepository;
    late MockAutomationSettingsRepository automationSettingsRepository;
    late MockGitRepositoryClient gitClient;
    late MockGitHubCliClient gitHubClient;
    late MockBaselineRepository baselineRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
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
      agentClient: agentClient,
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
        agentClient: agentClient,
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
        const TicketsError(
          '',
          reason: TicketsErrorReason.executionBudgetOverageDetected,
        ),
        const TicketsLoading(),
        // The forced-`gated` override applies here too (not just to the
        // skipped auto-flip above) — the ready-for-review banner must
        // still surface even though the configured confidence is `auto`.
        TicketDetailLoaded(
          taskUnderStory.copyWith(status: TicketStatus.inProgress),
          executionAwaitingReview: true,
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'dequeues and runs the next Task once the in-flight run completes',
      build: () => TicketsCubit(
        repository,
        agentClient: agentClient,
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
      late MockCommentRepository commentRepository;
      late MockAutomationSettingsRepository automationSettingsRepository;
      late MockGitRepositoryClient gitClient;
      late MockGitHubCliClient gitHubClient;
      late MockBaselineRepository baselineRepository;

      setUp(() {
        agentClient = MockAgentModelClient();
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
        agentClient: agentClient,
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
            status: any(named: 'status'),
            type: any(named: 'type'),
            priority: any(named: 'priority'),
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
        'is a no-op (no new emission) when the cubit\'s last state was '
        'TicketDetailLoaded, not TicketsLoaded',
        // A cubit missing git/baseline deps — _runCodingExecution hits its
        // own missing-deps guard immediately, so this test only needs to
        // observe changeTicketStatus's own single emission, not a full run.
        build: () => TicketsCubit(
          repository,
          agentClient: agentClient,
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
      late MockCommentRepository commentRepository;
      late MockAutomationSettingsRepository automationSettingsRepository;
      late MockGitRepositoryClient gitClient;
      late MockGitHubCliClient gitHubClient;
      late MockBaselineRepository baselineRepository;
      late MockTicketLinkRepository linkRepository;

      setUp(() {
        agentClient = MockAgentModelClient();
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
      });

      TicketsCubit buildCubit() => TicketsCubit(
        repository,
        agentClient: agentClient,
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
          // The `gated` toast.
          const TicketsError(
            '',
            reason: TicketsErrorReason.executionVerificationFailed,
          ),
          const TicketsLoading(),
          // The post-run refresh — `getCommentsForTicket` now genuinely
          // reflects the failure comment `_runCodingExecution` posted
          // (see `stubStatefulComments`), so it's echoed verbatim here.
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionFailureReason: 'Execution failed verification:\n\nerror Y',
            executionCanRetry: true,
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
          // No toast for `manual` — straight to the post-run refresh.
          const TicketsLoading(),
          TicketDetailLoaded(
            taskNoStory.copyWith(status: TicketStatus.inProgress),
            executionFailureReason: 'Execution failed verification:\n\nerror Z',
            executionCanRetry: true,
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
          // buildCubit, so the execution model resolves to
          // AgentModel.sonnet's real 200,000-token contextWindowTokens
          // (see TicketsCubit._resolveModel), and with no
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

  group('promoteSignalToEpic', () {
    late MockTicketLinkRepository linkRepository;

    setUp(() {
      linkRepository = MockTicketLinkRepository();
    });

    TicketsCubit buildCubit() =>
        TicketsCubit(repository, linkRepository: linkRepository);

    blocTest<TicketsCubit, TicketsState>(
      'rejects a non-signal ticket without calling the repository',
      setUp: () {
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
      },
      build: buildCubit,
      act: (cubit) => cubit.promoteSignalToEpic(ticket),
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
      'creates a new epic and links it when existingEpicId is omitted',
      setUp: () {
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => linkRepository.createLink(
            sourceTicketId: signalTicket.id,
            targetTicketId: any(named: 'targetTicketId'),
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(signalTicket.id),
        ).thenAnswer((_) async => signalTicket);
      },
      build: buildCubit,
      act: (cubit) => cubit.promoteSignalToEpic(signalTicket),
      verify: (_) {
        verify(() => repository.createTicket(any())).called(1);
        verify(
          () => linkRepository.createLink(
            sourceTicketId: signalTicket.id,
            targetTicketId: any(named: 'targetTicketId'),
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
      expect: () => [TicketDetailLoaded(signalTicket)],
    );

    blocTest<TicketsCubit, TicketsState>(
      'links to an existing epic without creating a new one when '
      'existingEpicId is given',
      setUp: () {
        when(
          () => linkRepository.createLink(
            sourceTicketId: signalTicket.id,
            targetTicketId: epic.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(signalTicket.id),
        ).thenAnswer((_) async => signalTicket);
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.promoteSignalToEpic(signalTicket, existingEpicId: epic.id),
      verify: (_) {
        verifyNever(() => repository.createTicket(any()));
        verify(
          () => linkRepository.createLink(
            sourceTicketId: signalTicket.id,
            targetTicketId: epic.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
      expect: () => [TicketDetailLoaded(signalTicket)],
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

  group('per-phase model routing (per-phase-tier-based-model-routing)', () {
    late MockAgentModelClient agentClient;
    late MockCommentRepository commentRepository;
    late MockTicketLinkRepository linkRepository;
    late MockAutomationSettingsRepository automationSettingsRepository;
    late MockModelRoutingRepository modelRoutingRepository;
    late MockGitRepositoryClient gitClient;
    late MockGitHubCliClient gitHubClient;
    late MockBaselineRepository baselineRepository;

    setUp(() {
      agentClient = MockAgentModelClient();
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
      ).thenAnswer((_) async => AgentModel.opus);
      when(
        () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
      ).thenAnswer((_) async => AgentModel.haiku);
      when(
        () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
      ).thenAnswer((_) async => AgentModel.sonnet);
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      linkRepository: linkRepository,
      agentClient: agentClient,
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
                (request) => request.model == AgentModel.opus.id,
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
                (request) => request.model == AgentModel.haiku.id,
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
                (request) => request.model == AgentModel.haiku.id,
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
                    request.model == AgentModel.sonnet.id &&
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
          status: any(named: 'status'),
          type: any(named: 'type'),
          priority: any(named: 'priority'),
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
            status: any(named: 'status'),
            type: any(named: 'type'),
            priority: any(named: 'priority'),
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

  group('decomposition materialization (board-task-ordering-indication)', () {
    late MockAgentModelClient agentClient;
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
      commentRepository = MockCommentRepository();
      linkRepository = MockTicketLinkRepository();
    });

    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      agentClient: agentClient,
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
}
