import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_context_enricher.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

/// Builds a raw `Float32List` embedding, serialized the same way
/// `EmbeddingProvider.embed` does.
Uint8List _vector(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

void main() {
  late MockTicketRepository repository;
  late MockTicketLinkRepository linkRepository;
  late MockEmbeddingProvider embeddingProvider;

  Ticket ticket({
    required String id,
    TicketType type = TicketType.task,
    String title = 'Untitled',
    String? description,
    String? parentId,
    Uint8List? embedding,
  }) => Ticket(
    id: id,
    ticketId: 'AIO-$id',
    type: type,
    title: title,
    description: description,
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    parentId: parentId,
    embedding: embedding,
  );

  setUp(() {
    repository = MockTicketRepository();
    linkRepository = MockTicketLinkRepository();
    embeddingProvider = MockEmbeddingProvider();

    when(() => repository.getAllTickets()).thenAnswer((_) async => []);
    when(
      () => linkRepository.getLinksForTicket(any()),
    ).thenAnswer((_) async => []);
    when(
      () => embeddingProvider.embed(any()),
    ).thenAnswer((_) async => _vector([1.0, 0.0]));
  });

  group('relatedTicketsSection', () {
    test('returns "" for a ticket with no parent, no links, and no '
        'embedding provider configured', () async {
      final enricher = TicketContextEnricher(repository);
      when(
        () => repository.getAllTickets(),
      ).thenAnswer((_) async => [ticket(id: 't1')]);

      final result = await enricher.relatedTicketsSection(ticket(id: 't1'));

      expect(result, '');
    });

    test('renders a multi-level ancestor chain nearest-first, each with its '
        'type label', () async {
      final epic = ticket(
        id: 'epic',
        type: TicketType.epic,
        title: 'Epic title',
      );
      final story = ticket(
        id: 'story',
        type: TicketType.story,
        title: 'Story title',
        parentId: 'epic',
      );
      final task = ticket(
        id: 'task',
        type: TicketType.task,
        title: 'Task title',
        parentId: 'story',
      );
      when(
        () => repository.getAllTickets(),
      ).thenAnswer((_) async => [epic, story, task]);
      final enricher = TicketContextEnricher(repository);

      final result = await enricher.relatedTicketsSection(task);

      expect(result, contains('## Related tickets'));
      final storyLine = '- Story — "Story title"';
      final epicLine = '- Epic — "Epic title"';
      expect(result, contains(storyLine));
      expect(result, contains(epicLine));
      expect(
        result.indexOf(storyLine) < result.indexOf(epicLine),
        isTrue,
        reason: 'nearer ancestor (Story) should render before Epic',
      );
    });

    test('a cyclic parentId chain terminates instead of looping', () async {
      final a = ticket(id: 'a', title: 'A', parentId: 'b');
      final b = ticket(id: 'b', title: 'B', parentId: 'a');
      when(() => repository.getAllTickets()).thenAnswer((_) async => [a, b]);
      final enricher = TicketContextEnricher(repository);

      final result = await enricher
          .relatedTicketsSection(a)
          .timeout(const Duration(seconds: 5));

      expect(result, contains('"B"'));
      expect(result, contains('"A"'));
    });

    for (final storedType in TicketLinkType.values) {
      test('a stored ${storedType.name} link renders correctly from both the '
          'source and target side', () async {
        final source = ticket(id: 'source', title: 'Source ticket');
        final target = ticket(id: 'target', title: 'Target ticket');
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [source, target]);
        final enricher = TicketContextEnricher(
          repository,
          linkRepository: linkRepository,
        );

        final row = TicketLinkData(
          id: 'link1',
          sourceTicketId: 'source',
          targetTicketId: 'target',
          linkType: storedType.name,
        );
        when(
          () => linkRepository.getLinksForTicket('source'),
        ).thenAnswer((_) async => [row]);
        when(
          () => linkRepository.getLinksForTicket('target'),
        ).thenAnswer((_) async => [row]);

        final fromSource = await enricher.relatedTicketsSection(source);
        final fromTarget = await enricher.relatedTicketsSection(target);

        expect(fromSource, contains('- ${storedType.name} — "Target ticket"'));
        expect(
          fromTarget,
          contains('- ${storedType.inverse.name} — "Source ticket"'),
        );
      });
    }

    test('a similarity match below the threshold is excluded; one at or '
        'above it is included', () async {
      final source = ticket(id: 'source', title: 'Source ticket');
      final belowThreshold = ticket(
        id: 'below',
        title: 'Below threshold',
        embedding: _vector([0.0, 1.0]), // orthogonal → similarity 0.0
      );
      final aboveThreshold = ticket(
        id: 'above',
        title: 'Above threshold',
        embedding: _vector([1.0, 0.0]), // identical → similarity 1.0
      );
      when(
        () => repository.getAllTickets(),
      ).thenAnswer((_) async => [source, belowThreshold, aboveThreshold]);
      final enricher = TicketContextEnricher(
        repository,
        embeddingProvider: embeddingProvider,
      );

      final result = await enricher.relatedTicketsSection(source);

      expect(result, contains('- similar — "Above threshold"'));
      expect(result, isNot(contains('Below threshold')));
    });

    test('a ticket already surfaced by the structured walk is never '
        'duplicated in the similar section, even if it also scores above '
        'the threshold', () async {
      final source = ticket(id: 'source', title: 'Source ticket');
      final linked = ticket(
        id: 'linked',
        title: 'Linked ticket',
        embedding: _vector([1.0, 0.0]), // identical → similarity 1.0
      );
      when(
        () => repository.getAllTickets(),
      ).thenAnswer((_) async => [source, linked]);
      when(() => linkRepository.getLinksForTicket('source')).thenAnswer(
        (_) async => [
          TicketLinkData(
            id: 'link1',
            sourceTicketId: 'source',
            targetTicketId: 'linked',
            linkType: TicketLinkType.relatesTo.name,
          ),
        ],
      );
      final enricher = TicketContextEnricher(
        repository,
        linkRepository: linkRepository,
        embeddingProvider: embeddingProvider,
      );

      final result = await enricher.relatedTicketsSection(source);

      expect(result, contains('- relatesTo — "Linked ticket"'));
      expect(result, isNot(contains('similar')));
    });

    test(
      'more than the top-K similarity matches above threshold are capped',
      () async {
        final source = ticket(id: 'source', title: 'Source ticket');
        final others = List.generate(
          8,
          (i) => ticket(
            id: 'sim$i',
            title: 'Similar $i',
            embedding: _vector([1.0, 0.0]),
          ),
        );
        when(
          () => repository.getAllTickets(),
        ).thenAnswer((_) async => [source, ...others]);
        final enricher = TicketContextEnricher(
          repository,
          embeddingProvider: embeddingProvider,
        );

        final result = await enricher.relatedTicketsSection(source);

        final matchCount = 'similar —'.allMatches(result).length;
        expect(matchCount, 5);
      },
    );

    test('a description longer than the snippet cap is truncated with a '
        'trailing ellipsis; a null/empty description renders '
        '"(no description)"', () async {
      final longDescription = 'x' * 500;
      final epic = ticket(
        id: 'epic',
        type: TicketType.epic,
        title: 'Epic with long description',
        description: longDescription,
      );
      final noDescriptionParent = ticket(
        id: 'noDesc',
        type: TicketType.story,
        title: 'Story with no description',
        parentId: 'epic',
      );
      final task = ticket(id: 'task', title: 'Task', parentId: 'noDesc');
      when(
        () => repository.getAllTickets(),
      ).thenAnswer((_) async => [epic, noDescriptionParent, task]);
      final enricher = TicketContextEnricher(repository);

      final result = await enricher.relatedTicketsSection(task);

      expect(result, contains('${'x' * 400}…'));
      expect(result, isNot(contains('x' * 401)));
      expect(
        result,
        contains('- Story — "Story with no description": (no description)'),
      );
    });
  });
}
