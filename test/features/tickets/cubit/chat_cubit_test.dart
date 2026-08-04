import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockCommentRepository extends Mock implements CommentRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockAgentProvider extends Mock implements AgentProvider {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

class MockTicketRepository extends Mock implements TicketRepository {}

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

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

void main() {
  late MockCommentRepository repository;
  late MockAgentModelClient client;
  late MockAgentProvider provider;
  late MockProviderRegistry registry;
  late MockTicketRepository ticketRepository;
  late MockModelRoutingRepository modelRoutingRepository;

  final humanComment = TicketComment(
    id: 'c1',
    ticketId: 'chat-1',
    content: 'Hello',
    authorType: CommentAuthorType.human,
    createdAt: DateTime(2026),
  );

  // Parentless — hits `_phaseForChat`'s defensive `ModelPhase.capable`
  // fallback (every chat ticket in real usage has a parent; the two
  // `sendMessage` tests below aren't testing phase inference itself, so
  // any resolvable phase works).
  final chatTicket = Ticket(
    id: 'chat-1',
    ticketId: 'AIO-chat-1',
    type: TicketType.chat,
    title: 'Chat',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(
      TicketComment(
        id: '',
        ticketId: '',
        content: '',
        authorType: CommentAuthorType.human,
        createdAt: DateTime(2026),
      ),
    );
    registerFallbackValue(const AgentRequest(prompt: '', model: ''));
  });

  setUp(() {
    repository = MockCommentRepository();
    client = MockAgentModelClient();
    provider = MockAgentProvider();
    registry = MockProviderRegistry();
    ticketRepository = MockTicketRepository();
    modelRoutingRepository = MockModelRoutingRepository();

    when(() => provider.client).thenReturn(client);
    when(
      () => provider.normalizeErrorMessage(any()),
    ).thenAnswer((invocation) => invocation.positionalArguments[0] as String);
    when(() => provider.describeOverage(any())).thenAnswer(
      (invocation) =>
          UsageWindowConsumption(invocation.positionalArguments[0] as String),
    );
    when(
      () => registry.providerById(ProviderId.claudeAgentSdk),
    ).thenReturn(provider);
  });

  ChatCubit buildCubit() =>
      ChatCubit(repository, registry, ticketRepository, modelRoutingRepository);

  group('loadMessages', () {
    blocTest<ChatCubit, ChatState>(
      'emits [ChatLoaded] with the fetched comments on success',
      setUp: () {
        when(
          () => repository.getCommentsForTicket('chat-1'),
        ).thenAnswer((_) async => [humanComment]);
      },
      build: buildCubit,
      act: (cubit) => cubit.loadMessages('chat-1'),
      expect: () => [
        ChatLoaded([humanComment]),
      ],
    );

    blocTest<ChatCubit, ChatState>(
      'emits [ChatError] if the repository call throws',
      setUp: () {
        when(
          () => repository.getCommentsForTicket('chat-1'),
        ).thenThrow(Exception('boom'));
      },
      build: buildCubit,
      act: (cubit) => cubit.loadMessages('chat-1'),
      expect: () => [isA<ChatError>()],
    );
  });

  group('sendMessage', () {
    blocTest<ChatCubit, ChatState>(
      'posts the human comment immediately, then streams and persists '
      'the AI reply, resolved via the phase-appropriate model',
      setUp: () {
        when(
          () => ticketRepository.getTicketById('chat-1'),
        ).thenAnswer((_) async => chatTicket);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).thenAnswer((_) async => _sonnet);

        var commentsAfterHuman = <TicketComment>[];
        var addCallCount = 0;
        when(() => repository.addComment(any())).thenAnswer((invocation) async {
          addCallCount++;
          final comment = invocation.positionalArguments.first as TicketComment;
          if (comment.authorType == CommentAuthorType.human) {
            commentsAfterHuman = [comment];
          }
        });
        when(() => repository.getCommentsForTicket('chat-1')).thenAnswer((
          _,
        ) async {
          // First call (right after the human comment) returns just the
          // human message; the second (after the AI reply persists)
          // returns both.
          return addCallCount >= 2
              ? [
                  commentsAfterHuman.first,
                  TicketComment(
                    id: 'ai-1',
                    ticketId: 'chat-1',
                    content: 'Hi there',
                    authorType: CommentAuthorType.ai,
                    aiModel: _sonnet.modelId,
                    createdAt: DateTime(2026),
                  ),
                ]
              : commentsAfterHuman;
        });
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Hi '),
            AgentTextEvent('there'),
            AgentDoneEvent(),
          ]),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.sendMessage(chatTicketId: 'chat-1', content: 'Hello'),
      verify: (_) {
        verify(() => repository.addComment(any())).called(2);
      },
      expect: () => [
        isA<ChatLoaded>(),
        isA<ChatLoaded>().having(
          (s) => s.streamingText,
          'streamingText',
          'Hi ',
        ),
        isA<ChatLoaded>().having(
          (s) => s.streamingText,
          'streamingText',
          'Hi there',
        ),
        isA<ChatLoaded>(),
      ],
    );

    blocTest<ChatCubit, ChatState>(
      'emits ChatError and persists a failure comment on AgentErrorEvent',
      setUp: () {
        when(
          () => ticketRepository.getTicketById('chat-1'),
        ).thenAnswer((_) async => chatTicket);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).thenAnswer((_) async => _sonnet);
        when(() => repository.addComment(any())).thenAnswer((_) async {});
        when(
          () => repository.getCommentsForTicket('chat-1'),
        ).thenAnswer((_) async => [humanComment]);
        when(() => client.run(any())).thenAnswer(
          (_) async =>
              Stream.fromIterable(const [AgentErrorEvent('model unavailable')]),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.sendMessage(chatTicketId: 'chat-1', content: 'Hello'),
      verify: (_) {
        // The human comment, plus a failure comment so the transcript
        // isn't silently missing a trace of the failed run.
        verify(() => repository.addComment(any())).called(2);
      },
      expect: () => [isA<ChatLoaded>(), isA<ChatError>(), isA<ChatLoaded>()],
    );
  });

  group('_phaseForChat (via sendMessage)', () {
    blocTest<ChatCubit, ChatState>(
      "resolves ModelPhase.frontier for a chat under a story parent "
      "currently at SddStage.verifying",
      setUp: () {
        final storyParent = Ticket(
          id: 'story-1',
          ticketId: 'AIO-story-1',
          type: TicketType.story,
          title: 'Story',
          status: TicketStatus.backlog,
          sddStage: SddStage.verifying,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final chatUnderStory = Ticket(
          id: 'chat-story',
          ticketId: 'AIO-chat-story',
          type: TicketType.chat,
          title: 'Verifying chat',
          status: TicketStatus.backlog,
          parentId: storyParent.id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => ticketRepository.getTicketById('chat-story'),
        ).thenAnswer((_) async => chatUnderStory);
        when(
          () => ticketRepository.getTicketById(storyParent.id),
        ).thenAnswer((_) async => storyParent);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => _opus);
        when(() => repository.addComment(any())).thenAnswer((_) async {});
        when(
          () => repository.getCommentsForTicket('chat-story'),
        ).thenAnswer((_) async => []);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.sendMessage(chatTicketId: 'chat-story', content: 'Hello'),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
        ).called(1);
        verify(
          () => client.run(
            any(
              that: predicate<AgentRequest>(
                (request) => request.model == _opus.modelId,
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<ChatCubit, ChatState>(
      'resolves ModelPhase.execution for a chat under a task parent',
      setUp: () {
        final taskParent = Ticket(
          id: 'task-1',
          ticketId: 'AIO-task-1',
          type: TicketType.task,
          title: 'Task',
          status: TicketStatus.inProgress,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final chatUnderTask = Ticket(
          id: 'chat-task',
          ticketId: 'AIO-chat-task',
          type: TicketType.chat,
          title: 'Execution chat',
          status: TicketStatus.backlog,
          parentId: taskParent.id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => ticketRepository.getTicketById('chat-task'),
        ).thenAnswer((_) async => chatUnderTask);
        when(
          () => ticketRepository.getTicketById(taskParent.id),
        ).thenAnswer((_) async => taskParent);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).thenAnswer((_) async => _haiku);
        when(() => repository.addComment(any())).thenAnswer((_) async {});
        when(
          () => repository.getCommentsForTicket('chat-task'),
        ).thenAnswer((_) async => []);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.sendMessage(chatTicketId: 'chat-task', content: 'Hello'),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).called(1);
        verify(
          () => client.run(
            any(
              that: predicate<AgentRequest>(
                (request) => request.model == _haiku.modelId,
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<ChatCubit, ChatState>(
      'resolves ModelPhase.execution for a chat under a bug parent',
      setUp: () {
        final bugParent = Ticket(
          id: 'bug-1',
          ticketId: 'AIO-bug-1',
          type: TicketType.bug,
          title: 'Bug',
          status: TicketStatus.inProgress,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final chatUnderBug = Ticket(
          id: 'chat-bug',
          ticketId: 'AIO-chat-bug',
          type: TicketType.chat,
          title: 'Execution chat',
          status: TicketStatus.backlog,
          parentId: bugParent.id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => ticketRepository.getTicketById('chat-bug'),
        ).thenAnswer((_) async => chatUnderBug);
        when(
          () => ticketRepository.getTicketById(bugParent.id),
        ).thenAnswer((_) async => bugParent);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).thenAnswer((_) async => _haiku);
        when(() => repository.addComment(any())).thenAnswer((_) async {});
        when(
          () => repository.getCommentsForTicket('chat-bug'),
        ).thenAnswer((_) async => []);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.sendMessage(chatTicketId: 'chat-bug', content: 'Hello'),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).called(1);
        verify(
          () => client.run(
            any(
              that: predicate<AgentRequest>(
                (request) => request.model == _haiku.modelId,
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<ChatCubit, ChatState>(
      "falls back to ModelPhase.capable when the chat's parent can't be "
      'resolved (defensive — never hit for a real, TicketsCubit-spawned '
      'chat)',
      setUp: () {
        final orphanChat = Ticket(
          id: 'chat-orphan',
          ticketId: 'AIO-chat-orphan',
          type: TicketType.chat,
          title: 'Orphan chat',
          status: TicketStatus.backlog,
          parentId: 'missing-parent',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        when(
          () => ticketRepository.getTicketById('chat-orphan'),
        ).thenAnswer((_) async => orphanChat);
        when(
          () => ticketRepository.getTicketById('missing-parent'),
        ).thenAnswer((_) async => null);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).thenAnswer((_) async => _sonnet);
        when(() => repository.addComment(any())).thenAnswer((_) async {});
        when(
          () => repository.getCommentsForTicket('chat-orphan'),
        ).thenAnswer((_) async => []);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.sendMessage(chatTicketId: 'chat-orphan', content: 'Hello'),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).called(1);
      },
    );
  });

  group('_phaseForChat — Inbox purpose (new-project-onboarding-inbox)', () {
    ChatCubit buildCubitForPurpose() => ChatCubit(
      repository,
      registry,
      ticketRepository,
      modelRoutingRepository,
    );

    Ticket inboxChat({
      required String id,
      required InboxPurpose purpose,
      String? parentId,
    }) => Ticket(
      id: id,
      ticketId: 'AIO-$id',
      type: TicketType.chat,
      title: 'Inbox chat',
      status: TicketStatus.backlog,
      inboxPurpose: purpose,
      parentId: parentId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    void stubTurn(String chatId, ModelPhase phase) {
      when(
        () => modelRoutingRepository.getModelForPhase(phase),
      ).thenAnswer((_) async => _sonnet);
      when(() => repository.addComment(any())).thenAnswer((_) async {});
      when(
        () => repository.getCommentsForTicket(chatId),
      ).thenAnswer((_) async => []);
      when(() => client.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
      );
    }

    for (final purpose in [
      InboxPurpose.brainDump,
      InboxPurpose.whatNextGuidance,
      InboxPurpose.releasePlanning,
    ]) {
      blocTest<ChatCubit, ChatState>(
        'resolves ModelPhase.frontier for a parentless ${purpose.name} chat',
        setUp: () {
          final chat = inboxChat(id: 'inbox-${purpose.name}', purpose: purpose);
          when(
            () => ticketRepository.getTicketById(chat.id),
          ).thenAnswer((_) async => chat);
          stubTurn(chat.id, ModelPhase.frontier);
        },
        build: buildCubitForPurpose,
        act: (cubit) => cubit.sendMessage(
          chatTicketId: 'inbox-${purpose.name}',
          content: 'Hello',
        ),
        verify: (_) {
          verify(
            () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
          ).called(1);
        },
      );
    }

    blocTest<ChatCubit, ChatState>(
      'resolves ModelPhase.capable for a parentless qa chat',
      setUp: () {
        final chat = inboxChat(id: 'inbox-qa', purpose: InboxPurpose.qa);
        when(
          () => ticketRepository.getTicketById(chat.id),
        ).thenAnswer((_) async => chat);
        stubTurn(chat.id, ModelPhase.capable);
      },
      build: buildCubitForPurpose,
      act: (cubit) =>
          cubit.sendMessage(chatTicketId: 'inbox-qa', content: 'Hello'),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).called(1);
      },
    );

    blocTest<ChatCubit, ChatState>(
      'resolves via inboxPurpose (frontier) even when parentId is set, '
      'never consulting the parent walk',
      setUp: () {
        final chat = inboxChat(
          id: 'inbox-with-parent',
          purpose: InboxPurpose.brainDump,
          parentId: 'should-never-be-looked-up',
        );
        when(
          () => ticketRepository.getTicketById(chat.id),
        ).thenAnswer((_) async => chat);
        stubTurn(chat.id, ModelPhase.frontier);
      },
      build: buildCubitForPurpose,
      act: (cubit) => cubit.sendMessage(
        chatTicketId: 'inbox-with-parent',
        content: 'Hello',
      ),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
        ).called(1);
        verifyNever(() => ticketRepository.getTicketById('should-never-be-looked-up'));
      },
    );
  });

  group('runChatTurn usage capture', () {
    test('persists inputTokens/outputTokens from a terminal AgentDoneEvent '
        'that carries them', () async {
      TicketComment? persisted;
      when(() => repository.addComment(any())).thenAnswer((invocation) async {
        persisted = invocation.positionalArguments.first as TicketComment;
      });
      when(() => client.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [
          AgentTextEvent('Hi there'),
          AgentDoneEvent(inputTokens: 123, outputTokens: 456),
        ]),
      );

      final succeeded = await ChatCubit.runChatTurn(
        client: client,
        provider: provider,
        commentRepo: repository,
        chatTicketId: 'chat-1',
        prompt: 'Hello',
        model: _sonnet,
      );

      expect(succeeded, isTrue);
      expect(persisted?.inputTokens, 123);
      expect(persisted?.outputTokens, 456);
    });

    test(
      'persists null/null usage when the terminal event is an '
      'AgentErrorEvent (no done event ever seen)',
      () async {
        TicketComment? persisted;
        when(() => repository.addComment(any())).thenAnswer((
          invocation,
        ) async {
          persisted = invocation.positionalArguments.first as TicketComment;
        });
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentErrorEvent('model unavailable'),
          ]),
        );

        final succeeded = await ChatCubit.runChatTurn(
          client: client,
          provider: provider,
          commentRepo: repository,
          chatTicketId: 'chat-1',
          prompt: 'Hello',
          model: _sonnet,
        );

        expect(succeeded, isFalse);
        expect(persisted?.inputTokens, isNull);
        expect(persisted?.outputTokens, isNull);
      },
    );

    test(
      'an AgentOverageDetectedEvent reaches onConsumptionSignal as a '
      'UsageWindowConsumption, via provider.describeOverage',
      () async {
        when(() => repository.addComment(any())).thenAnswer((_) async {});
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentOverageDetectedEvent("Over your plan's usage limit."),
            AgentDoneEvent(),
          ]),
        );

        ConsumptionSignal? received;
        await ChatCubit.runChatTurn(
          client: client,
          provider: provider,
          commentRepo: repository,
          chatTicketId: 'chat-1',
          prompt: 'Hello',
          model: _sonnet,
          onConsumptionSignal: (signal) => received = signal,
        );

        expect(received, isA<UsageWindowConsumption>());
        expect(received!.message, "Over your plan's usage limit.");
      },
    );
  });
}
