// test/features/tickets/presentation/cubit/inbox_cubit_test.dart — InboxCubit tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockCommentRepository extends Mock implements CommentRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockAgentProvider extends Mock implements AgentProvider {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

class MockGitRepositoryClient extends Mock implements GitRepositoryClient {}

const _sonnet = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'claude-sonnet-5',
  label: 'Sonnet 5',
  contextWindowTokens: 200000,
);

/// Makes [repository]'s `createTicket`/`getTicketById` behave like a real
/// (in-memory) store, keyed on each [Ticket]'s own `id` — needed since
/// `InboxCubit` generates its own ticket ids internally (`Uuid().v4()`)
/// and then immediately reads them back via `getTicketById`. Mirrors
/// `tickets_cubit_codebase_analysis_test.dart`'s helper of the same name.
void stubStatefulTickets(MockTicketRepository repository) {
  final store = <String, Ticket>{};
  when(() => repository.createTicket(any())).thenAnswer((invocation) async {
    final ticket = invocation.positionalArguments[0] as Ticket;
    store[ticket.id] = ticket;
  });
  when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
    final id = invocation.positionalArguments[0] as String;
    return store[id];
  });
}

/// Makes [commentRepository]'s `addComment`/`getCommentsForTicket` behave
/// like a real (in-memory) per-ticket comment log.
void stubStatefulComments(MockCommentRepository commentRepository) {
  final comments = <TicketComment>[];
  when(
    () => commentRepository.getCommentsForTicket(any()),
  ).thenAnswer((invocation) async {
    final ticketId = invocation.positionalArguments[0] as String;
    return comments.where((c) => c.ticketId == ticketId).toList();
  });
  when(() => commentRepository.addComment(any())).thenAnswer((
    invocation,
  ) async {
    comments.add(invocation.positionalArguments[0] as TicketComment);
  });
}

void main() {
  late MockTicketRepository repository;
  late MockCommentRepository commentRepository;
  late MockTicketLinkRepository linkRepository;
  late MockAgentModelClient agentClient;
  late MockProviderRegistry registry;
  late MockModelRoutingRepository modelRoutingRepository;
  late MockGitRepositoryClient gitClient;

  setUpAll(() {
    registerFallbackValue(
      Ticket(
        id: 'fallback',
        ticketId: '',
        type: TicketType.signal,
        title: '',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    registerFallbackValue(const AgentRequest(prompt: '', model: ''));
    registerFallbackValue(
      TicketComment(
        id: '',
        ticketId: '',
        content: '',
        authorType: CommentAuthorType.system,
        createdAt: DateTime(2026),
      ),
    );
    registerFallbackValue(TicketLinkType.relatesTo);
    registerFallbackValue(ModelPhase.capable);
  });

  setUp(() {
    repository = MockTicketRepository();
    commentRepository = MockCommentRepository();
    linkRepository = MockTicketLinkRepository();
    agentClient = MockAgentModelClient();
    final provider = MockAgentProvider();
    registry = MockProviderRegistry();
    when(() => provider.client).thenReturn(agentClient);
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
    modelRoutingRepository = MockModelRoutingRepository();
    gitClient = MockGitRepositoryClient();

    stubStatefulTickets(repository);
    stubStatefulComments(commentRepository);
    when(
      () => linkRepository.createLink(
        sourceTicketId: any(named: 'sourceTicketId'),
        targetTicketId: any(named: 'targetTicketId'),
        linkType: any(named: 'linkType'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => modelRoutingRepository.getModelForPhase(any()),
    ).thenAnswer((_) async => _sonnet);
    when(
      () => gitClient.createWorktree(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => gitClient.removeWorktree(any(), any()),
    ).thenAnswer((_) async {});
  });

  InboxCubit buildCubit() => InboxCubit(
    repository,
    commentRepository,
    linkRepository,
    registry,
    modelRoutingRepository,
    gitClient: gitClient,
    projectRootPath: '/fake/project/root',
  );

  Ticket inboxChat({
    required String id,
    required InboxPurpose purpose,
    DateTime? createdAt,
  }) => Ticket(
    id: id,
    ticketId: 'AIO-$id',
    type: TicketType.chat,
    title: 'Inbox chat $id',
    status: TicketStatus.backlog,
    inboxPurpose: purpose,
    createdAt: createdAt ?? DateTime(2026),
    updatedAt: createdAt ?? DateTime(2026),
  );

  group('load', () {
    blocTest<InboxCubit, InboxState>(
      'returns only inboxPurpose != null chats, sorted by createdAt '
      'descending',
      setUp: () {
        final older = inboxChat(
          id: 'old',
          purpose: InboxPurpose.qa,
          createdAt: DateTime(2026, 1, 1),
        );
        final newer = inboxChat(
          id: 'new',
          purpose: InboxPurpose.brainDump,
          createdAt: DateTime(2026, 6, 1),
        );
        final nonInbox = Ticket(
          id: 'not-inbox',
          ticketId: 'AIO-not-inbox',
          type: TicketType.chat,
          title: 'Ordinary chat',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026, 3, 1),
          updatedAt: DateTime(2026, 3, 1),
        );
        when(
          () => repository.getTicketsByParent(
            null,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => [older, newer, nonInbox]);
      },
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [
        const InboxLoading(),
        isA<InboxLoaded>().having(
          (s) => s.history.map((t) => t.id).toList(),
          'history ids',
          ['new', 'old'],
        ),
      ],
    );

    blocTest<InboxCubit, InboxState>(
      'emits InboxError when the repository throws',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            null,
            types: const [TicketType.chat],
          ),
        ).thenThrow(Exception('boom'));
      },
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [const InboxLoading(), isA<InboxError>()],
    );
  });

  group('startBrainDump', () {
    test(
      'creates a parentless chat with inboxPurpose brainDump, resolves '
      'ModelPhase.frontier, and materializes one signal ticket per '
      'parsed block with the correct suggestedType',
      () async {
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent(
              'SIGNAL: Add dark mode toggle\n'
              'Users have asked for a way to switch themes manually.\n'
              'TYPE: epic\n'
              'SIGNAL: Crash on empty title\n'
              'Creating a ticket with no title crashes the app.\n'
              'TYPE: bug\n'
              'BRAINDUMP: DONE',
            ),
            AgentDoneEvent(),
          ]),
        );
        when(
          () => repository.getTicketsByParent(
            null,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);

        final cubit = buildCubit();
        final chatId = await cubit.startBrainDump('some raw notes');
        await cubit.close();

        expect(chatId, isNotNull);
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
        ).called(1);

        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>();
        final chat = created.singleWhere((t) => t.type == TicketType.chat);
        expect(chat.inboxPurpose, InboxPurpose.brainDump);

        final signals = created
            .where((t) => t.type == TicketType.signal)
            .toList();
        expect(signals, hasLength(2));
        expect(
          signals.singleWhere((s) => s.title == 'Add dark mode toggle').suggestedType,
          TicketType.epic,
        );
        expect(
          signals.singleWhere((s) => s.title == 'Crash on empty title').suggestedType,
          TicketType.bug,
        );
      },
    );

    test(
      'a block with a missing/malformed TYPE line still creates a signal '
      'ticket, with suggestedType null',
      () async {
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent(
              'SIGNAL: Unclear idea\n'
              'No TYPE line follows this one.\n'
              'BRAINDUMP: DONE',
            ),
            AgentDoneEvent(),
          ]),
        );
        when(
          () => repository.getTicketsByParent(
            null,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);

        final cubit = buildCubit();
        await cubit.startBrainDump('raw notes');
        await cubit.close();

        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>();
        final signal = created.singleWhere((t) => t.type == TicketType.signal);
        expect(signal.title, 'Unclear idea');
        expect(signal.suggestedType, isNull);
      },
    );
  });

  group('startWhatNextGuidance', () {
    test(
      'creates a parentless chat with inboxPurpose whatNextGuidance and '
      'resolves ModelPhase.frontier, creating no signal tickets',
      () async {
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Advisory prose only.'),
            AgentDoneEvent(),
          ]),
        );
        when(() => repository.getAllTickets()).thenAnswer((_) async => []);
        when(
          () => repository.getAllTicketsByType(any()),
        ).thenAnswer((_) async => []);
        when(
          () => repository.getTicketsByParent(
            null,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);

        final cubit = buildCubit();
        final chatId = await cubit.startWhatNextGuidance();
        await cubit.close();

        expect(chatId, isNotNull);
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
        ).called(1);
        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>();
        expect(created, hasLength(1));
        expect(created.single.inboxPurpose, InboxPurpose.whatNextGuidance);
      },
    );
  });

  group('startReleasePlanning', () {
    test(
      'creates a parentless chat with inboxPurpose releasePlanning and '
      'resolves ModelPhase.frontier',
      () async {
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('What would you like in this release?'),
            AgentDoneEvent(),
          ]),
        );
        when(
          () => repository.getAllTicketsByType(any()),
        ).thenAnswer((_) async => []);
        when(
          () => repository.getTicketsByParent(
            null,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);

        final cubit = buildCubit();
        final chatId = await cubit.startReleasePlanning();
        await cubit.close();

        expect(chatId, isNotNull);
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
        ).called(1);
        // A clarifying-question opening reply has no RELEASE PLAN: DONE
        // marker — no release ticket should materialize yet.
        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>();
        expect(created.where((t) => t.type == TicketType.release), isEmpty);
      },
    );
  });

  group('handleReleasePlanningReply', () {
    test(
      'a reply without RELEASE PLAN: DONE is a no-op — no release '
      'ticket, no links',
      () async {
        final cubit = buildCubit();
        await cubit.handleReleasePlanningReply(
          'chat-1',
          'Still discussing scope, nothing settled yet.',
        );
        await cubit.close();

        verifyNever(() => repository.createTicket(any()));
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
      },
    );

    test(
      'a reply with RELEASE PLAN: DONE creates a release ticket and '
      'links each resolvable LINK id, skipping an id that does not exist',
      () async {
        final epic = Ticket(
          id: 'epic-1',
          ticketId: 'AIO-epic-1',
          type: TicketType.epic,
          title: 'Epic one',
          status: TicketStatus.backlog,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => repository.getTicketById('epic-1'),
        ).thenAnswer((_) async => epic);
        when(
          () => repository.getTicketById('missing-id'),
        ).thenAnswer((_) async => null);

        final cubit = buildCubit();
        await cubit.handleReleasePlanningReply(
          'chat-1',
          'RELEASE: v1.2\n'
          'LINK: epic-1\n'
          'LINK: missing-id\n'
          'RELEASE PLAN: DONE',
        );
        await cubit.close();

        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>();
        expect(created, hasLength(1));
        final release = created.single;
        expect(release.type, TicketType.release);
        expect(release.title, 'v1.2');

        verify(
          () => linkRepository.createLink(
            sourceTicketId: release.id,
            targetTicketId: 'epic-1',
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: 'missing-id',
            linkType: any(named: 'linkType'),
          ),
        );
      },
    );
  });

  group('startQa', () {
    test(
      'creates and removes an isolated worktree, resolves '
      'ModelPhase.capable, and runs with toolsEnabled true',
      () async {
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Here is how that works...'),
            AgentDoneEvent(),
          ]),
        );
        when(
          () => repository.getTicketsByParent(
            null,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);

        final cubit = buildCubit();
        final chatId = await cubit.startQa('How does auth work?');
        await cubit.close();

        expect(chatId, isNotNull);
        verify(
          () => gitClient.createWorktree(any(), any(), any()),
        ).called(1);
        verify(() => gitClient.removeWorktree(any(), any())).called(1);
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).called(1);
        verify(
          () => agentClient.run(
            any(
              that: predicate<AgentRequest>((r) => r.toolsEnabled == true),
            ),
          ),
        ).called(1);
      },
    );

    test(
      'removes the worktree even when the model turn hard-fails',
      () async {
        when(() => agentClient.run(any())).thenThrow(Exception('boom'));
        when(
          () => repository.getTicketsByParent(
            null,
            types: const [TicketType.chat],
          ),
        ).thenAnswer((_) async => []);

        final cubit = buildCubit();
        await cubit.startQa('A question');
        await cubit.close();

        verify(() => gitClient.removeWorktree(any(), any())).called(1);
      },
    );

    test(
      'removes the worktree even when createWorktree itself throws',
      () async {
        when(
          () => gitClient.createWorktree(any(), any(), any()),
        ).thenThrow(Exception('worktree create failed'));

        final cubit = buildCubit();
        final result = await cubit.startQa('A question');
        await cubit.close();

        expect(result, isNull);
        verify(() => gitClient.removeWorktree(any(), any())).called(1);
      },
    );

    blocTest<InboxCubit, InboxState>(
      'emits InboxError immediately, creating no chat, when constructed '
      'without a git client/project root path (mobile/web)',
      build: () => InboxCubit(
        repository,
        commentRepository,
        linkRepository,
        registry,
        modelRoutingRepository,
      ),
      act: (cubit) => cubit.startQa('A question'),
      verify: (_) {
        verifyNever(() => repository.createTicket(any()));
        verifyNever(() => gitClient.createWorktree(any(), any(), any()));
      },
      expect: () => [const InboxLaunching(InboxPurpose.qa), isA<InboxError>()],
    );
  });
}
