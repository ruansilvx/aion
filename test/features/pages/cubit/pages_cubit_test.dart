// test/features/pages/cubit/pages_cubit_test.dart — PagesCubit tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/page_ticket_provider.dart';
import 'package:aion/features/pages/presentation/cubit/pages_cubit.dart';
import 'package:aion/features/pages/presentation/cubit/pages_state.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

class MockPageTicketProvider extends Mock implements PageTicketProvider {}

void main() {
  late MockPageTicketProvider provider;

  final now = DateTime(2026, 1, 1);
  final page = Ticket(
    id: 'p1',
    ticketId: 'AIO-1',
    type: TicketType.page,
    title: 'A page',
    status: 'backlog',
    createdAt: now,
    updatedAt: now,
  );
  const relations = PageRelations(
    childDocs: [],
    linkedTickets: [],
    backlinks: [],
  );
  final linkedTicket = Ticket(
    id: 'linked-1',
    ticketId: 'AIO-2',
    type: TicketType.task,
    title: 'A linked task',
    status: 'backlog',
    createdAt: now,
    updatedAt: now,
  );
  // Deliberately distinct from `relations` (rather than reusing it) for
  // `deleteLink`/`updateLinkType`'s tests: emitting an Equatable-equal
  // `PageDetailLoaded` back-to-back is silently skipped by Cubit.emit,
  // so those tests need a genuinely different post-refresh value to
  // observe the emission at all.
  final refreshedRelations = PageRelations(
    childDocs: const [],
    linkedTickets: [
      (
        ticket: linkedTicket,
        relativeType: TicketLinkType.relatesTo,
        linkId: 'link-2',
      ),
    ],
    backlinks: const [],
  );

  setUp(() {
    provider = MockPageTicketProvider();
  });

  group('PagesCubit.loadPage', () {
    blocTest<PagesCubit, PagesState>(
      'emits [PagesLoading, PageDetailLoaded] on success',
      setUp: () {
        when(() => provider.getPage('p1')).thenAnswer((_) async => page);
        when(
          () => provider.loadPageRelations('p1'),
        ).thenAnswer((_) async => relations);
      },
      build: () => PagesCubit(provider),
      act: (cubit) => cubit.loadPage('p1'),
      expect: () => [
        const PagesLoading(),
        PageDetailLoaded(page, relations),
      ],
    );

    blocTest<PagesCubit, PagesState>(
      'emits [PagesLoading, PagesError] when the page is not found',
      setUp: () {
        when(() => provider.getPage('missing')).thenAnswer((_) async => null);
      },
      build: () => PagesCubit(provider),
      act: (cubit) => cubit.loadPage('missing'),
      expect: () => [const PagesLoading(), isA<PagesError>()],
    );

    blocTest<PagesCubit, PagesState>(
      'emits [PagesLoading, PagesError] when the provider throws',
      setUp: () {
        when(
          () => provider.getPage('p1'),
        ).thenThrow(Exception('boom'));
      },
      build: () => PagesCubit(provider),
      act: (cubit) => cubit.loadPage('p1'),
      expect: () => [const PagesLoading(), isA<PagesError>()],
    );
  });

  group('PagesCubit.createPage', () {
    blocTest<PagesCubit, PagesState>(
      'emits [PagesLoading, PageCreated] on success',
      setUp: () {
        when(
          () => provider.createPage(
            title: 'New page',
            description: null,
            parentId: null,
          ),
        ).thenAnswer((_) async => page);
      },
      build: () => PagesCubit(provider),
      act: (cubit) => cubit.createPage(title: 'New page'),
      expect: () => [const PagesLoading(), PageCreated(page)],
    );

    blocTest<PagesCubit, PagesState>(
      'emits [PagesLoading, PagesError] when the provider throws',
      setUp: () {
        when(
          () => provider.createPage(
            title: any(named: 'title'),
            description: any(named: 'description'),
            parentId: any(named: 'parentId'),
          ),
        ).thenThrow(Exception('boom'));
      },
      build: () => PagesCubit(provider),
      act: (cubit) => cubit.createPage(title: 'New page'),
      expect: () => [const PagesLoading(), isA<PagesError>()],
    );
  });

  group('PagesCubit.updatePage', () {
    blocTest<PagesCubit, PagesState>(
      'emits [PageDetailLoaded] with the refreshed page on success',
      setUp: () {
        when(
          () => provider.updatePage(page),
        ).thenAnswer((_) async => page);
        when(
          () => provider.loadPageRelations('p1'),
        ).thenAnswer((_) async => relations);
      },
      build: () => PagesCubit(provider),
      act: (cubit) => cubit.updatePage(page),
      expect: () => [PageDetailLoaded(page, relations)],
    );

    blocTest<PagesCubit, PagesState>(
      'emits [PagesError] when the provider throws',
      setUp: () {
        when(() => provider.updatePage(page)).thenThrow(Exception('boom'));
      },
      build: () => PagesCubit(provider),
      act: (cubit) => cubit.updatePage(page),
      expect: () => [isA<PagesError>()],
    );
  });

  group('PagesCubit.trashPage', () {
    blocTest<PagesCubit, PagesState>(
      'emits [PageTrashed] on success',
      setUp: () {
        when(() => provider.trashPage('p1')).thenAnswer((_) async {});
      },
      build: () => PagesCubit(provider),
      act: (cubit) => cubit.trashPage('p1'),
      expect: () => [const PageTrashed()],
    );

    blocTest<PagesCubit, PagesState>(
      'emits [PagesError] when the provider throws',
      setUp: () {
        when(() => provider.trashPage('p1')).thenThrow(Exception('boom'));
      },
      build: () => PagesCubit(provider),
      act: (cubit) => cubit.trashPage('p1'),
      expect: () => [isA<PagesError>()],
    );
  });

  group('PagesCubit.deleteLink', () {
    blocTest<PagesCubit, PagesState>(
      'emits [PageDetailLoaded] with refreshed relations, page unchanged',
      setUp: () {
        when(
          () => provider.deleteLink('p1', 'link-1'),
        ).thenAnswer((_) async {});
        when(
          () => provider.loadPageRelations('p1'),
        ).thenAnswer((_) async => refreshedRelations);
      },
      build: () => PagesCubit(provider),
      seed: () => PageDetailLoaded(page, relations),
      act: (cubit) => cubit.deleteLink('p1', 'link-1'),
      expect: () => [PageDetailLoaded(page, refreshedRelations)],
      verify: (_) {
        verify(() => provider.deleteLink('p1', 'link-1')).called(1);
      },
    );

    blocTest<PagesCubit, PagesState>(
      'emits [PagesError] when the provider throws',
      setUp: () {
        when(
          () => provider.deleteLink('p1', 'link-1'),
        ).thenThrow(Exception('boom'));
      },
      build: () => PagesCubit(provider),
      seed: () => PageDetailLoaded(page, relations),
      act: (cubit) => cubit.deleteLink('p1', 'link-1'),
      expect: () => [isA<PagesError>()],
    );
  });

  group('PagesCubit.updateLinkType', () {
    blocTest<PagesCubit, PagesState>(
      'emits [PageDetailLoaded] with refreshed relations, page unchanged',
      setUp: () {
        when(
          () => provider.updateLinkType('p1', 'link-1', TicketLinkType.blocks),
        ).thenAnswer((_) async {});
        when(
          () => provider.loadPageRelations('p1'),
        ).thenAnswer((_) async => refreshedRelations);
      },
      build: () => PagesCubit(provider),
      seed: () => PageDetailLoaded(page, relations),
      act: (cubit) =>
          cubit.updateLinkType('p1', 'link-1', TicketLinkType.blocks),
      expect: () => [PageDetailLoaded(page, refreshedRelations)],
      verify: (_) {
        verify(
          () => provider.updateLinkType('p1', 'link-1', TicketLinkType.blocks),
        ).called(1);
      },
    );

    blocTest<PagesCubit, PagesState>(
      'emits [PagesError] when the provider throws',
      setUp: () {
        when(
          () => provider.updateLinkType('p1', 'link-1', TicketLinkType.blocks),
        ).thenThrow(Exception('boom'));
      },
      build: () => PagesCubit(provider),
      seed: () => PageDetailLoaded(page, relations),
      act: (cubit) =>
          cubit.updateLinkType('p1', 'link-1', TicketLinkType.blocks),
      expect: () => [isA<PagesError>()],
    );
  });

  group('PagesCubit.loadWikilinkCandidates', () {
    test(
      'delegates to PageTicketProvider.getWikilinkCandidates and returns '
      'its result unmodified',
      () async {
        final resource = Ticket(
          id: 'r1',
          ticketId: 'AIO-3',
          type: TicketType.resource,
          title: 'A resource',
          status: 'backlog',
          createdAt: now,
          updatedAt: now,
        );
        when(
          () => provider.getWikilinkCandidates(),
        ).thenAnswer((_) async => [page, resource]);
        final cubit = PagesCubit(provider);

        final result = await cubit.loadWikilinkCandidates();

        expect(result, [page, resource]);
        verify(() => provider.getWikilinkCandidates()).called(1);
        await cubit.close();
      },
    );
  });
}
