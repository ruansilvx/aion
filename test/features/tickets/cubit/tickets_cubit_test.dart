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
      when(() => agentClient.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
      );
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
        when(() => repository.getTicketById(any())).thenAnswer(
          (_) async => dummyChatTicket,
        );
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
        when(() => repository.getTicketById(any())).thenAnswer(
          (_) async => dummyChatTicket,
        );
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
        when(() => repository.getTicketById(any())).thenAnswer(
          (_) async => dummyChatTicket,
        );
        when(() => repository.getTicketById(storyProposed.id)).thenAnswer(
          (_) async => storyProposed,
        );
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
        when(() => repository.getTicketById(any())).thenAnswer(
          (_) async => dummyChatTicket,
        );
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
        when(() => repository.getTicketById(any())).thenAnswer(
          (_) async => dummyChatTicket,
        );
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
        when(() => repository.getTicketById(any())).thenAnswer(
          (_) async => dummyChatTicket,
        );
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
            types: const [TicketType.task],
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
        when(() => repository.getTicketById(any())).thenAnswer(
          (_) async => dummyChatTicket,
        );
        when(() => repository.getTicketById(storyDesignSync.id)).thenAnswer(
          (_) async => storyDesignSync,
        );
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
        when(() => commentRepository.addComment(any())).thenAnswer(
          (_) async {},
        );
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

    setUp(() {
      agentClient = MockAgentModelClient();
      commentRepository = MockCommentRepository();
      automationSettingsRepository = MockAutomationSettingsRepository();
    });

    TicketsCubit buildFullCubit() => TicketsCubit(
      repository,
      agentClient: agentClient,
      commentRepository: commentRepository,
      automationSettingsRepository: automationSettingsRepository,
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
            types: const [TicketType.task],
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
            types: const [TicketType.task],
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
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c5',
              ticketId: dummyExecutionChatTicket.id,
              content: 'Done.\n\nEXECUTION: PR_OPENED https://example/pr/1',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
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
        when(() => commentRepository.addComment(any())).thenAnswer(
          (_) async {},
        );
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Done.\n\nEXECUTION: PR_OPENED https://example/pr/1'),
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
        verify(() => agentClient.run(any())).called(1);
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
            types: const [TicketType.task],
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
        when(
          () => commentRepository.getCommentsForTicket(
            dummyExecutionChatTicket.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c7',
              ticketId: dummyExecutionChatTicket.id,
              content: 'Done.\n\nEXECUTION: PR_OPENED https://example/pr/2',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
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
        when(() => commentRepository.addComment(any())).thenAnswer(
          (_) async {},
        );
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Done.\n\nEXECUTION: PR_OPENED https://example/pr/2'),
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
      ),
      setUp: () {
        final runGate = Completer<void>();
        addTearDown(() {
          if (!runGate.isCompleted) runGate.complete();
        });
        when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
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
        when(() => commentRepository.addComment(any())).thenAnswer(
          (_) async {},
        );
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
            types: const [TicketType.task],
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
          (_) async => taskUnderStoryNoDesign.copyWith(
            status: TicketStatus.inProgress,
          ),
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
          (_) async =>
              taskUnderEpic.copyWith(status: TicketStatus.inProgress),
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
            types: const [TicketType.task],
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
        when(
          () => commentRepository.getCommentsForTicket(
            dummyExecutionChatTicket.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c9',
              ticketId: dummyExecutionChatTicket.id,
              content: "Couldn't finish.\n\nEXECUTION: NO_PR",
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
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
        when(() => commentRepository.addComment(any())).thenAnswer(
          (_) async {},
        );
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
            types: const [TicketType.task],
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
        when(
          () => commentRepository.getCommentsForTicket(
            dummyExecutionChatTicket.id,
          ),
        ).thenAnswer(
          (_) async => [
            TicketComment(
              id: 'c11',
              ticketId: dummyExecutionChatTicket.id,
              content: 'Done.\n\nEXECUTION: PR_OPENED https://example/pr/3',
              authorType: CommentAuthorType.ai,
              createdAt: DateTime(2026),
            ),
          ],
        );
        when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
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
        when(() => commentRepository.addComment(any())).thenAnswer(
          (_) async {},
        );
        // The run itself reports overage mid-stream, then still finishes
        // with a confirmed PR — the override must still force `gated`.
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentOverageDetectedEvent('Usage limit reached'),
            AgentTextEvent('Done.\n\nEXECUTION: PR_OPENED https://example/pr/3'),
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
      ),
      setUp: () {
        when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
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
        when(() => commentRepository.addComment(any())).thenAnswer(
          (_) async {},
        );
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
        // Both Tasks' chats were eventually spawned and run, in order.
        verify(() => repository.createTicket(any())).called(2);
        verify(() => agentClient.run(any())).called(2);
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

    setUp(() {
      agentClient = MockAgentModelClient();
      commentRepository = MockCommentRepository();
      linkRepository = MockTicketLinkRepository();
      automationSettingsRepository = MockAutomationSettingsRepository();
      modelRoutingRepository = MockModelRoutingRepository();
      when(() => agentClient.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
      );
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
        when(() => repository.getTicketById(any())).thenAnswer(
          (_) async => dummyChatTicket,
        );
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
            types: const [TicketType.task],
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
        when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
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
      },
      build: buildCubit,
      act: (cubit) =>
          cubit.changeTicketStatus(taskUnderStory, TicketStatus.inProgress),
      wait: const Duration(milliseconds: 50),
      verify: (_) {
        verify(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).called(1);
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
        ).called(1);
      },
    );
  });
}
