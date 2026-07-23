import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockCommentRepository extends Mock implements CommentRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockTicketRepository extends Mock implements TicketRepository {}

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

void main() {
  late MockCommentRepository repository;
  late MockAgentModelClient client;
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
    ticketRepository = MockTicketRepository();
    modelRoutingRepository = MockModelRoutingRepository();
  });

  ChatCubit buildCubit() =>
      ChatCubit(repository, client, ticketRepository, modelRoutingRepository);

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
        ).thenAnswer((_) async => AgentModel.sonnet);

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
                    aiModel: AgentModel.sonnet.id,
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
        ).thenAnswer((_) async => AgentModel.sonnet);
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
        ).thenAnswer((_) async => AgentModel.opus);
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
                (request) => request.model == AgentModel.opus.id,
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
        ).thenAnswer((_) async => AgentModel.haiku);
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
                (request) => request.model == AgentModel.haiku.id,
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
        ).thenAnswer((_) async => AgentModel.sonnet);
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
}
