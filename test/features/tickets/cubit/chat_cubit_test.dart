import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockCommentRepository extends Mock implements CommentRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

void main() {
  late MockCommentRepository repository;
  late MockAgentModelClient client;

  final humanComment = TicketComment(
    id: 'c1',
    ticketId: 'chat-1',
    content: 'Hello',
    authorType: CommentAuthorType.human,
    createdAt: DateTime(2026),
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
  });

  group('loadMessages', () {
    blocTest<ChatCubit, ChatState>(
      'emits [ChatLoaded] with the fetched comments on success',
      setUp: () {
        when(
          () => repository.getCommentsForTicket('chat-1'),
        ).thenAnswer((_) async => [humanComment]);
      },
      build: () => ChatCubit(repository, client),
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
      build: () => ChatCubit(repository, client),
      act: (cubit) => cubit.loadMessages('chat-1'),
      expect: () => [isA<ChatError>()],
    );
  });

  group('sendMessage', () {
    blocTest<ChatCubit, ChatState>(
      'posts the human comment immediately, then streams and persists '
      'the AI reply',
      setUp: () {
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
      build: () => ChatCubit(repository, client),
      act: (cubit) => cubit.sendMessage(
        chatTicketId: 'chat-1',
        content: 'Hello',
        model: AgentModel.sonnet,
      ),
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
      'emits ChatError and persists nothing extra on AgentErrorEvent',
      setUp: () {
        when(() => repository.addComment(any())).thenAnswer((_) async {});
        when(
          () => repository.getCommentsForTicket('chat-1'),
        ).thenAnswer((_) async => [humanComment]);
        when(() => client.run(any())).thenAnswer(
          (_) async =>
              Stream.fromIterable(const [AgentErrorEvent('model unavailable')]),
        );
      },
      build: () => ChatCubit(repository, client),
      act: (cubit) => cubit.sendMessage(
        chatTicketId: 'chat-1',
        content: 'Hello',
        model: AgentModel.sonnet,
      ),
      verify: (_) {
        // Only the human comment is persisted — never a broken AI reply.
        verify(() => repository.addComment(any())).called(1);
      },
      expect: () => [isA<ChatLoaded>(), isA<ChatError>(), isA<ChatLoaded>()],
    );
  });
}
