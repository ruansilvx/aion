import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/agent_tool_definition.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_branch_tool_definitions.dart';
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
          (s) => s.activeRunId,
          'activeRunId',
          isNotNull,
        ),
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
      expect: () => [
        isA<ChatLoaded>(),
        isA<ChatLoaded>().having(
          (s) => s.activeRunId,
          'activeRunId',
          isNotNull,
        ),
        isA<ChatError>(),
        isA<ChatLoaded>(),
      ],
    );

    blocTest<ChatCubit, ChatState>(
      'on AgentCancelledEvent, persists the accumulated text as one ai '
      'comment (no ChatError), reloads the thread, and clears '
      'activeRunId',
      setUp: () {
        when(
          () => ticketRepository.getTicketById('chat-1'),
        ).thenAnswer((_) async => chatTicket);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).thenAnswer((_) async => _sonnet);

        var addCallCount = 0;
        when(() => repository.addComment(any())).thenAnswer((_) async {
          addCallCount++;
        });
        when(() => repository.getCommentsForTicket('chat-1')).thenAnswer((
          _,
        ) async {
          return addCallCount >= 2
              ? [
                  humanComment,
                  TicketComment(
                    id: 'ai-1',
                    ticketId: 'chat-1',
                    content: 'Partial reply',
                    authorType: CommentAuthorType.ai,
                    aiModel: _sonnet.modelId,
                    createdAt: DateTime(2026),
                  ),
                ]
              : [humanComment];
        });
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Partial '),
            AgentTextEvent('reply'),
            AgentCancelledEvent(),
          ]),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.sendMessage(chatTicketId: 'chat-1', content: 'Hello'),
      verify: (_) {
        // The human comment, plus the accumulated-text comment persisted
        // by sendMessage itself (runChatTurn persists nothing for a
        // cancelled turn).
        final captured = verify(
          () => repository.addComment(captureAny()),
        ).captured;
        expect(captured, hasLength(2));
        final persistedAiComment = captured[1] as TicketComment;
        expect(persistedAiComment.content, 'Partial reply');
        expect(persistedAiComment.authorType, CommentAuthorType.ai);
      },
      expect: () => [
        isA<ChatLoaded>().having((s) => s.activeRunId, 'activeRunId', isNull),
        isA<ChatLoaded>().having(
          (s) => s.activeRunId,
          'activeRunId',
          isNotNull,
        ),
        isA<ChatLoaded>().having(
          (s) => s.streamingText,
          'streamingText',
          'Partial ',
        ),
        isA<ChatLoaded>().having(
          (s) => s.streamingText,
          'streamingText',
          'Partial reply',
        ),
        isA<ChatLoaded>().having((s) => s.activeRunId, 'activeRunId', isNull),
      ],
    );

    blocTest<ChatCubit, ChatState>(
      'on AgentCancelledEvent with no accumulated text, persists no ai '
      'comment',
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
              Stream.fromIterable(const [AgentCancelledEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.sendMessage(chatTicketId: 'chat-1', content: 'Hello'),
      verify: (_) {
        // Only the human comment — nothing accumulated to persist.
        verify(() => repository.addComment(any())).called(1);
      },
    );
  });

  group('cancelReply', () {
    blocTest<ChatCubit, ChatState>(
      "calls AgentModelClient.cancel with the in-flight run's runId",
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
      },
      build: buildCubit,
      act: (cubit) async {
        final eventsController = StreamController<AgentEvent>();
        when(
          () => client.run(any()),
        ).thenAnswer((_) async => eventsController.stream);

        final sendFuture = cubit.sendMessage(
          chatTicketId: 'chat-1',
          content: 'Hello',
        );
        // Let sendMessage run up through its pre-stream activeRunId emit.
        await Future<void>.delayed(Duration.zero);

        await cubit.cancelReply('chat-1');

        eventsController.add(const AgentCancelledEvent());
        await eventsController.close();
        await sendFuture;
      },
      verify: (_) {
        final capturedRunId =
            verify(() => client.cancel(captureAny())).captured.single
                as String;
        final capturedRequest =
            verify(() => client.run(captureAny())).captured.single
                as AgentRequest;
        expect(capturedRunId, capturedRequest.runId);
      },
    );

    blocTest<ChatCubit, ChatState>(
      'is a no-op when no reply is in flight (state is ChatInitial)',
      build: buildCubit,
      act: (cubit) => cubit.cancelReply('chat-1'),
      verify: (_) {
        verifyNever(() => client.cancel(any()));
      },
    );
  });

  group('_toolsFor / onToolCall (via sendMessage)', () {
    // taskParent: a non-chat parent — makes branchEligibleChat eligible for
    // branch_ticket. rootChatParent/branchChat: a chat-under-chat pair —
    // makes branchChat eligible for close_branch only. Added for
    // `aion-arch/changes/mid-task-chat-branching`.
    final taskParent = Ticket(
      id: 'tools-task-parent',
      ticketId: 'AIO-tools-1',
      type: TicketType.task,
      title: 'Task',
      status: TicketStatus.inProgress,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final branchEligibleChat = Ticket(
      id: 'tools-branch-eligible-chat',
      ticketId: 'AIO-tools-2',
      type: TicketType.chat,
      title: 'Root chat',
      status: TicketStatus.backlog,
      parentId: taskParent.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final rootChatParent = Ticket(
      id: 'tools-root-chat-parent',
      ticketId: 'AIO-tools-3',
      type: TicketType.chat,
      title: 'Root chat',
      status: TicketStatus.backlog,
      parentId: taskParent.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final branchChat = Ticket(
      id: 'tools-branch-chat',
      ticketId: 'AIO-tools-4',
      type: TicketType.chat,
      title: 'Branch chat',
      status: TicketStatus.backlog,
      parentId: rootChatParent.id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    Future<Map<String, dynamic>> noopOnToolCall(
      String toolCallId,
      String toolName,
      Map<String, dynamic> arguments,
    ) async => {'accepted': false};

    blocTest<ChatCubit, ChatState>(
      'offers branchTicketToolDefinition and threads the caller-supplied '
      "onToolCall through to the AgentRequest when the chat's own parent "
      'is not a chat',
      setUp: () {
        when(
          () => ticketRepository.getTicketById(branchEligibleChat.id),
        ).thenAnswer((_) async => branchEligibleChat);
        when(
          () => ticketRepository.getTicketById(taskParent.id),
        ).thenAnswer((_) async => taskParent);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).thenAnswer((_) async => _sonnet);
        when(() => repository.addComment(any())).thenAnswer((_) async {});
        when(
          () => repository.getCommentsForTicket(branchEligibleChat.id),
        ).thenAnswer((_) async => []);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.sendMessage(
        chatTicketId: branchEligibleChat.id,
        content: 'Hello',
        onToolCall: noopOnToolCall,
      ),
      verify: (_) {
        final captured =
            verify(() => client.run(captureAny())).captured.single
                as AgentRequest;
        expect(captured.tools, [branchTicketToolDefinition]);
        expect(captured.onToolCall, noopOnToolCall);
      },
    );

    blocTest<ChatCubit, ChatState>(
      "offers closeBranchToolDefinition when the chat's own parent is "
      'itself a chat (a branch chat)',
      setUp: () {
        when(
          () => ticketRepository.getTicketById(branchChat.id),
        ).thenAnswer((_) async => branchChat);
        when(
          () => ticketRepository.getTicketById(rootChatParent.id),
        ).thenAnswer((_) async => rootChatParent);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
        ).thenAnswer((_) async => _sonnet);
        when(() => repository.addComment(any())).thenAnswer((_) async {});
        when(
          () => repository.getCommentsForTicket(branchChat.id),
        ).thenAnswer((_) async => []);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.sendMessage(
        chatTicketId: branchChat.id,
        content: 'Hello',
        onToolCall: noopOnToolCall,
      ),
      verify: (_) {
        final captured =
            verify(() => client.run(captureAny())).captured.single
                as AgentRequest;
        expect(captured.tools, [closeBranchToolDefinition]);
        expect(captured.onToolCall, noopOnToolCall);
      },
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
      when(
        () => client.run(any()),
      ).thenAnswer((_) async => Stream.fromIterable(const [AgentDoneEvent()]));
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
        // _toolsFor (mid-task-chat-branching) does legitimately read this
        // id — an unrelated purpose from _phaseForChat's own parent walk,
        // which this test is really about (see below).
        when(
          () => ticketRepository.getTicketById('should-never-be-looked-up'),
        ).thenAnswer((_) async => null);
        stubTurn(chat.id, ModelPhase.frontier);
      },
      build: buildCubitForPurpose,
      act: (cubit) => cubit.sendMessage(
        chatTicketId: 'inbox-with-parent',
        content: 'Hello',
      ),
      verify: (_) {
        // The actual claim under test: _phaseForChat resolves the Inbox
        // purpose directly, without itself needing to walk to the parent
        // to compute a ModelPhase.
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.frontier),
        ).called(1);
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

      final result = await ChatCubit.runChatTurn(
        client: client,
        provider: provider,
        commentRepo: repository,
        chatTicketId: 'chat-1',
        prompt: 'Hello',
        model: _sonnet,
      );

      expect(result, isA<ChatTurnSuccess>());
      expect(persisted?.inputTokens, 123);
      expect(persisted?.outputTokens, 456);
    });

    test('persists null/null usage when the terminal event is an '
        'AgentErrorEvent (no done event ever seen)', () async {
      TicketComment? persisted;
      when(() => repository.addComment(any())).thenAnswer((invocation) async {
        persisted = invocation.positionalArguments.first as TicketComment;
      });
      when(() => client.run(any())).thenAnswer(
        (_) async =>
            Stream.fromIterable(const [AgentErrorEvent('model unavailable')]),
      );

      final result = await ChatCubit.runChatTurn(
        client: client,
        provider: provider,
        commentRepo: repository,
        chatTicketId: 'chat-1',
        prompt: 'Hello',
        model: _sonnet,
      );

      expect(result, isA<ChatTurnFailure>());
      expect(persisted?.inputTokens, isNull);
      expect(persisted?.outputTokens, isNull);
    });

    test('an AgentOverageDetectedEvent reaches onConsumptionSignal as a '
        'UsageWindowConsumption, via provider.describeOverage', () async {
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
    });

    test(
      'passes tools/onToolCall through to the AgentRequest unchanged, and '
      'reports an AgentToolCallEvent via onToolUse (not by invoking '
      'onToolCall itself — that is the client implementation\'s job)',
      () async {
        when(() => repository.addComment(any())).thenAnswer((_) async {});

        AgentRequest? capturedRequest;
        when(() => client.run(any())).thenAnswer((invocation) async {
          capturedRequest =
              invocation.positionalArguments.first as AgentRequest;
          return Stream.fromIterable(const [
            AgentToolCallEvent('call-1', 'branch_ticket', {'title': 'X'}),
            AgentDoneEvent(),
          ]);
        });

        const tool = AgentToolDefinition(
          name: 'branch_ticket',
          description: 'test tool',
          inputSchema: {'type': 'object', 'properties': {}},
        );
        var onToolCallInvoked = false;
        Future<Map<String, dynamic>> onToolCall(
          String toolCallId,
          String toolName,
          Map<String, dynamic> arguments,
        ) async {
          onToolCallInvoked = true;
          return {'accepted': true};
        }

        final toolUseCalls = <(String, String?)>[];
        await ChatCubit.runChatTurn(
          client: client,
          provider: provider,
          commentRepo: repository,
          chatTicketId: 'chat-1',
          prompt: 'Hello',
          model: _sonnet,
          tools: const [tool],
          onToolCall: onToolCall,
          onToolUse: (toolName, summary) =>
              toolUseCalls.add((toolName, summary)),
        );

        expect(capturedRequest?.tools, const [tool]);
        expect(capturedRequest?.onToolCall, onToolCall);
        expect(toolUseCalls, [('branch_ticket', null)]);
        expect(onToolCallInvoked, isFalse);
      },
    );
  });
}
