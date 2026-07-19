// test/features/tickets/data/page_ticket_provider_impl_test.dart — PageTicketProviderImpl tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/features/tickets/data/page_ticket_provider_impl.dart';

class MockTicketsCubit extends Mock implements TicketsCubit {}

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

void main() {
  late MockTicketsCubit ticketsCubit;
  late MockTicketRepository ticketRepository;
  late MockTicketLinkRepository ticketLinkRepository;
  late PageTicketProviderImpl provider;

  final now = DateTime(2026, 1, 1);

  Ticket buildTicket({
    required String id,
    required TicketType type,
    String? parentId,
  }) => Ticket(
    id: id,
    ticketId: 'AIO-$id',
    type: type,
    title: 'Title $id',
    status: TicketStatus.backlog,
    parentId: parentId,
    createdAt: now,
    updatedAt: now,
  );

  setUpAll(() {
    registerFallbackValue(
      buildTicket(id: 'fallback', type: TicketType.page),
    );
  });

  setUp(() {
    ticketsCubit = MockTicketsCubit();
    ticketRepository = MockTicketRepository();
    ticketLinkRepository = MockTicketLinkRepository();
    provider = PageTicketProviderImpl(
      ticketsCubit,
      ticketRepository,
      ticketLinkRepository,
    );
  });

  group('PageTicketProviderImpl reads', () {
    test('getPage returns the ticket when it is a page', () async {
      final page = buildTicket(id: 'p1', type: TicketType.page);
      when(
        () => ticketRepository.getTicketById('p1'),
      ).thenAnswer((_) async => page);

      final result = await provider.getPage('p1');

      expect(result, page);
    });

    test('getPage returns null when the ticket is not a page', () async {
      final task = buildTicket(id: 't1', type: TicketType.task);
      when(
        () => ticketRepository.getTicketById('t1'),
      ).thenAnswer((_) async => task);

      final result = await provider.getPage('t1');

      expect(result, isNull);
    });

    test('getPage returns null when the ticket does not exist', () async {
      when(
        () => ticketRepository.getTicketById('missing'),
      ).thenAnswer((_) async => null);

      final result = await provider.getPage('missing');

      expect(result, isNull);
    });

    test(
      'loadPageRelations splits links into linkedTickets vs backlinks',
      () async {
        final page = buildTicket(id: 'p1', type: TicketType.page);
        final childDoc = buildTicket(
          id: 'child',
          type: TicketType.page,
          parentId: 'p1',
        );
        final linkedTask = buildTicket(id: 'task1', type: TicketType.task);
        final backlinkPage = buildTicket(id: 'p2', type: TicketType.page);

        when(
          () => ticketRepository.getTicketsByParent(
            'p1',
            types: const [TicketType.page, TicketType.resource],
          ),
        ).thenAnswer((_) async => [childDoc]);
        when(() => ticketLinkRepository.getLinksForTicket('p1')).thenAnswer(
          (_) async => [
            TicketLinkData(
              id: 'link-1',
              sourceTicketId: 'p1',
              targetTicketId: 'task1',
              linkType: TicketLinkType.relatesTo.name,
            ),
            TicketLinkData(
              id: 'link-2',
              sourceTicketId: 'p2',
              targetTicketId: 'p1',
              linkType: TicketLinkType.relatesTo.name,
            ),
          ],
        );
        when(
          () => ticketRepository.getTicketById('task1'),
        ).thenAnswer((_) async => linkedTask);
        when(
          () => ticketRepository.getTicketById('p2'),
        ).thenAnswer((_) async => backlinkPage);

        final relations = await provider.loadPageRelations(page.id);

        expect(relations.childDocs, [childDoc]);
        expect(relations.linkedTickets, [linkedTask]);
        expect(relations.backlinks, [backlinkPage]);
      },
    );

    test(
      'getValidParentCandidatesForPage returns only page-type tickets',
      () async {
        final page1 = buildTicket(id: 'p1', type: TicketType.page);
        final page2 = buildTicket(id: 'p2', type: TicketType.page);
        final task = buildTicket(id: 't1', type: TicketType.task);
        when(
          () => ticketRepository.getAllTickets(),
        ).thenAnswer((_) async => [page1, page2, task]);

        final result = await provider.getValidParentCandidatesForPage();

        expect(result, containsAll([page1, page2]));
        expect(result, isNot(contains(task)));
      },
    );

    test(
      'getValidParentCandidatesForPage excludes the given id and its descendants',
      () async {
        final root = buildTicket(id: 'root', type: TicketType.page);
        final child = buildTicket(
          id: 'child',
          type: TicketType.page,
          parentId: 'root',
        );
        final unrelated = buildTicket(id: 'other', type: TicketType.page);
        when(
          () => ticketRepository.getAllTickets(),
        ).thenAnswer((_) async => [root, child, unrelated]);

        final result = await provider.getValidParentCandidatesForPage(
          excludeId: 'root',
        );

        expect(result, [unrelated]);
      },
    );
  });

  group('PageTicketProviderImpl writes delegate to TicketsCubit', () {
    test('createPage delegates to TicketsCubit.createTicket', () async {
      final created = buildTicket(id: 'new', type: TicketType.page);
      when(
        () => ticketsCubit.createTicket(
          type: TicketType.page,
          title: any(named: 'title'),
          description: any(named: 'description'),
          parentId: any(named: 'parentId'),
        ),
      ).thenAnswer((_) async => created);

      final result = await provider.createPage(
        title: 'New page',
        description: 'desc',
        parentId: 'parent-1',
      );

      expect(result, created);
      verify(
        () => ticketsCubit.createTicket(
          type: TicketType.page,
          title: 'New page',
          description: 'desc',
          parentId: 'parent-1',
        ),
      ).called(1);
    });

    test('updatePage delegates to TicketsCubit.updateTicket', () async {
      final page = buildTicket(id: 'p1', type: TicketType.page);
      when(
        () => ticketsCubit.updateTicket(page),
      ).thenAnswer((_) async => page);

      final result = await provider.updatePage(page);

      expect(result, page);
      verify(() => ticketsCubit.updateTicket(page)).called(1);
    });

    test('trashPage delegates to TicketsCubit.trashTicket', () async {
      when(
        () => ticketsCubit.trashTicket('p1'),
      ).thenAnswer((_) async {});

      await provider.trashPage('p1');

      verify(() => ticketsCubit.trashTicket('p1')).called(1);
    });
  });
}
