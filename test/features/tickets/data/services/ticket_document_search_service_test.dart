import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/features/tickets/data/services/ticket_document_search_service.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

class MockTicketRepository extends Mock implements TicketRepository {}

/// Builds a raw `Float32List` embedding of [values], serialized the same
/// way [EmbeddingProvider.embed] does.
Uint8List _vector(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

void main() {
  late MockEmbeddingProvider embeddingProvider;
  late MockTicketRepository repository;
  late TicketDocumentSearchService service;

  Ticket doc({
    required String id,
    required TicketType type,
    Uint8List? embedding,
  }) => Ticket(
    id: id,
    ticketId: 'AIO-$id',
    type: type,
    title: 'Doc $id',
    status: TicketStatus.backlog,
    embedding: embedding,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUp(() {
    embeddingProvider = MockEmbeddingProvider();
    repository = MockTicketRepository();
    service = TicketDocumentSearchService(embeddingProvider, repository);
  });

  test('ranks candidates by cosine similarity, highest first', () async {
    when(
      () => embeddingProvider.embed('query'),
    ).thenAnswer((_) async => _vector([1.0, 0.0]));

    final exactMatch = doc(
      id: 'a',
      type: TicketType.page,
      embedding: _vector([1.0, 0.0]),
    );
    final orthogonal = doc(
      id: 'b',
      type: TicketType.page,
      embedding: _vector([0.0, 1.0]),
    );
    final opposite = doc(
      id: 'c',
      type: TicketType.resource,
      embedding: _vector([-1.0, 0.0]),
    );

    when(
      () => repository.getAllTicketsByType(const [
        TicketType.page,
        TicketType.resource,
      ]),
    ).thenAnswer((_) async => [orthogonal, opposite, exactMatch]);

    final results = await service.search('query');

    expect(results.map((t) => t.id), ['a', 'b', 'c']);
  });

  test('excludes candidates with no embedding', () async {
    when(
      () => embeddingProvider.embed('query'),
    ).thenAnswer((_) async => _vector([1.0, 0.0]));

    final withEmbedding = doc(
      id: 'a',
      type: TicketType.page,
      embedding: _vector([1.0, 0.0]),
    );
    final withoutEmbedding = doc(id: 'b', type: TicketType.page);

    when(
      () => repository.getAllTicketsByType(const [
        TicketType.page,
        TicketType.resource,
      ]),
    ).thenAnswer((_) async => [withEmbedding, withoutEmbedding]);

    final results = await service.search('query');

    expect(results.map((t) => t.id), ['a']);
  });

  test('caps results at limit', () async {
    when(
      () => embeddingProvider.embed('query'),
    ).thenAnswer((_) async => _vector([1.0, 0.0]));

    final candidates = List.generate(
      5,
      (i) => doc(
        id: '$i',
        type: TicketType.page,
        embedding: _vector([1.0, 0.0]),
      ),
    );
    when(
      () => repository.getAllTicketsByType(const [
        TicketType.page,
        TicketType.resource,
      ]),
    ).thenAnswer((_) async => candidates);

    final results = await service.search('query', limit: 2);

    expect(results.length, 2);
  });
}
