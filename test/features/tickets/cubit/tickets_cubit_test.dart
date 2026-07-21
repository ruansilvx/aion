import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

class MockTicketGitProjector extends Mock implements TicketGitProjector {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockCommentRepository extends Mock implements CommentRepository {}

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
      'no-ops for a non-page/resource ticket type',
      setUp: () {
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
      },
      build: buildCubit,
      seed: () => TicketDetailLoaded(ticket),
      act: (cubit) => cubit.loadDocumentRelations(ticket.id),
      expect: () => [],
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
      'precondition is met',
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
      },
    );
  });

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
}
