import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/features/tickets/data/services/ticket_document_search_service.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketDocumentSearchService extends Mock
    implements TicketDocumentSearchService {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

void main() {
  late MockTicketRepository repository;
  late MockTicketDocumentSearchService searchService;

  final rootPage = Ticket(
    id: 'page-1',
    ticketId: 'AIO-1',
    type: TicketType.page,
    title: 'Root page',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final childResource = Ticket(
    id: 'resource-1',
    ticketId: 'AIO-2',
    type: TicketType.resource,
    title: 'Child resource',
    status: TicketStatus.backlog,
    parentId: rootPage.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUp(() {
    repository = MockTicketRepository();
    searchService = MockTicketDocumentSearchService();
  });

  DocumentationCubit buildCubit() =>
      DocumentationCubit(repository, searchService);

  group('load', () {
    blocTest<DocumentationCubit, DocumentationState>(
      'emits [DocumentationLoading, DocumentationLoaded] with root docs',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            null,
            types: const [TicketType.page, TicketType.resource],
          ),
        ).thenAnswer((_) async => [rootPage]);
      },
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [
        const DocumentationLoading(),
        DocumentationLoaded(
          rootDocs: [rootPage],
          childrenByParentId: const {},
          expandedIds: const {},
        ),
      ],
    );

    blocTest<DocumentationCubit, DocumentationState>(
      'emits DocumentationError when the repository call throws',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            null,
            types: any(named: 'types'),
          ),
        ).thenThrow(Exception('boom'));
      },
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [
        const DocumentationLoading(),
        isA<DocumentationError>(),
      ],
    );
  });

  group('loadChildren', () {
    blocTest<DocumentationCubit, DocumentationState>(
      'lazily fetches and caches a page\'s children on first expand',
      setUp: () {
        when(
          () => repository.getTicketsByParent(
            rootPage.id,
            types: const [TicketType.page, TicketType.resource],
          ),
        ).thenAnswer((_) async => [childResource]);
      },
      build: buildCubit,
      seed: () => DocumentationLoaded(
        rootDocs: [rootPage],
        childrenByParentId: const {},
        expandedIds: const {},
      ),
      act: (cubit) => cubit.loadChildren(rootPage.id),
      expect: () => [
        DocumentationLoaded(
          rootDocs: [rootPage],
          childrenByParentId: {rootPage.id: [childResource]},
          expandedIds: {rootPage.id},
        ),
      ],
    );

    blocTest<DocumentationCubit, DocumentationState>(
      'collapses (removes from expandedIds) on a second call, no re-fetch',
      build: buildCubit,
      seed: () => DocumentationLoaded(
        rootDocs: [rootPage],
        childrenByParentId: {rootPage.id: [childResource]},
        expandedIds: {rootPage.id},
      ),
      act: (cubit) => cubit.loadChildren(rootPage.id),
      expect: () => [
        DocumentationLoaded(
          rootDocs: [rootPage],
          childrenByParentId: {rootPage.id: [childResource]},
          expandedIds: const {},
        ),
      ],
      verify: (_) {
        verifyNever(
          () => repository.getTicketsByParent(
            rootPage.id,
            types: any(named: 'types'),
          ),
        );
      },
    );

    blocTest<DocumentationCubit, DocumentationState>(
      'no-ops while a search is active',
      build: buildCubit,
      seed: () => DocumentationLoaded(
        rootDocs: [rootPage],
        childrenByParentId: const {},
        expandedIds: const {},
        searchResults: [rootPage],
      ),
      act: (cubit) => cubit.loadChildren(rootPage.id),
      expect: () => [],
    );
  });

  group('search / clearSearch', () {
    blocTest<DocumentationCubit, DocumentationState>(
      'search populates searchResults, preserving tree state',
      setUp: () {
        when(
          () => searchService.search('notes'),
        ).thenAnswer((_) async => [rootPage]);
      },
      build: buildCubit,
      seed: () => DocumentationLoaded(
        rootDocs: [rootPage],
        childrenByParentId: const {},
        expandedIds: const {},
      ),
      act: (cubit) => cubit.search('notes'),
      expect: () => [
        DocumentationLoaded(
          rootDocs: [rootPage],
          childrenByParentId: const {},
          expandedIds: const {},
          searchResults: [rootPage],
        ),
      ],
    );

    blocTest<DocumentationCubit, DocumentationState>(
      'debounces rapid calls — only the last query within the window is searched',
      setUp: () {
        when(
          () => searchService.search('final'),
        ).thenAnswer((_) async => [rootPage]);
      },
      build: buildCubit,
      seed: () => DocumentationLoaded(
        rootDocs: [rootPage],
        childrenByParentId: const {},
        expandedIds: const {},
      ),
      act: (cubit) async {
        // Fire-and-forget the superseded calls; only await the last one,
        // matching how the widget calls search() on every keystroke with
        // no debounce of its own.
        unawaited(cubit.search('f'));
        unawaited(cubit.search('fin'));
        await cubit.search('final');
      },
      expect: () => [
        DocumentationLoaded(
          rootDocs: [rootPage],
          childrenByParentId: const {},
          expandedIds: const {},
          searchResults: [rootPage],
        ),
      ],
      verify: (_) {
        verifyNever(() => searchService.search('f'));
        verifyNever(() => searchService.search('fin'));
        verify(() => searchService.search('final')).called(1);
      },
    );

    blocTest<DocumentationCubit, DocumentationState>(
      'an empty/whitespace query is equivalent to clearSearch',
      build: buildCubit,
      seed: () => DocumentationLoaded(
        rootDocs: [rootPage],
        childrenByParentId: const {},
        expandedIds: const {},
        searchResults: [rootPage],
      ),
      act: (cubit) => cubit.search('   '),
      expect: () => [
        DocumentationLoaded(
          rootDocs: [rootPage],
          childrenByParentId: const {},
          expandedIds: const {},
        ),
      ],
      verify: (_) {
        verifyNever(() => searchService.search(any()));
      },
    );

    blocTest<DocumentationCubit, DocumentationState>(
      'clearSearch returns to tree mode',
      build: buildCubit,
      seed: () => DocumentationLoaded(
        rootDocs: [rootPage],
        childrenByParentId: const {},
        expandedIds: const {},
        searchResults: [rootPage],
      ),
      act: (cubit) => cubit.clearSearch(),
      expect: () => [
        DocumentationLoaded(
          rootDocs: [rootPage],
          childrenByParentId: const {},
          expandedIds: const {},
        ),
      ],
    );
  });
}
