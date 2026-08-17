import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_token_predictor.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

class MockTicketRepository extends Mock implements TicketRepository {}

/// Builds a raw `Float32List` embedding, serialized the same way
/// `EmbeddingProvider.embed` does — mirrors
/// `ticket_estimation_suggester_test.dart`'s own helper.
Uint8List _vector(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

void main() {
  late MockEmbeddingProvider embeddingProvider;
  late MockTicketRepository repository;
  late TicketTokenPredictor predictor;

  Ticket ticket({
    String id = 't1',
    TicketType type = TicketType.task,
    Uint8List? embedding,
    int? predictedExecutionTokensLow,
    int? predictedExecutionTokensHigh,
  }) => Ticket(
    id: id,
    ticketId: 'AIO-$id',
    type: type,
    title: 'Do the thing',
    description: 'Some description',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    embedding: embedding,
    predictedExecutionTokensLow: predictedExecutionTokensLow,
    predictedExecutionTokensHigh: predictedExecutionTokensHigh,
  );

  setUp(() {
    embeddingProvider = MockEmbeddingProvider();
    repository = MockTicketRepository();

    // Default: no existing "Coding Execution — " chat, no candidate pool.
    when(
      () => repository.getTicketsByParent(
        any(),
        types: any(named: 'types'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => repository.getAllTicketsByType(any()),
    ).thenAnswer((_) async => []);
    when(
      () => repository.getExecutionTokenTotals(any()),
    ).thenAnswer((_) async => {});
    when(
      () => repository.applyTokenPrediction(
        any(),
        low: any(named: 'low'),
        high: any(named: 'high'),
      ),
    ).thenAnswer((_) async {});

    predictor = TicketTokenPredictor(
      repository,
      embeddingProvider: embeddingProvider,
    );
  });

  void verifyNeverApplied() {
    verifyNever(
      () => repository.applyTokenPrediction(
        any(),
        low: any(named: 'low'),
        high: any(named: 'high'),
      ),
    );
  }

  group('suggest — guard chain', () {
    test('no-ops without an EmbeddingProvider', () async {
      final bare = TicketTokenPredictor(repository);

      await bare.suggest(ticket(embedding: _vector([1.0, 0.0])));

      verifyNeverApplied();
      verifyNever(() => repository.getAllTicketsByType(any()));
    });

    test('no-ops for a ticket type other than task/bug', () async {
      await predictor.suggest(
        ticket(type: TicketType.epic, embedding: _vector([1.0, 0.0])),
      );

      verifyNeverApplied();
      verifyNever(() => repository.getAllTicketsByType(any()));
    });

    test('no-ops when the ticket has no embedding yet', () async {
      await predictor.suggest(ticket());

      verifyNeverApplied();
      verifyNever(() => repository.getAllTicketsByType(any()));
    });

    test(
      'no-ops when the ticket already has a "Coding Execution — " child '
      'chat',
      () async {
        when(
          () => repository.getTicketsByParent(
            't1',
            types: [TicketType.chat],
          ),
        ).thenAnswer(
          (_) async => [
            Ticket(
              id: 'chat-1',
              ticketId: 'AIO-chat-1',
              type: TicketType.chat,
              title: 'Coding Execution — Do the thing',
              status: TicketStatus.backlog,
              parentId: 't1',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        );

        await predictor.suggest(ticket(embedding: _vector([1.0, 0.0])));

        verifyNeverApplied();
        verifyNever(() => repository.getAllTicketsByType(any()));
      },
    );
  });

  group('suggest — candidate walk', () {
    test(
      'a populated candidate set persists the correct min/max range',
      () async {
        when(() => repository.getAllTicketsByType(const [
          TicketType.task,
          TicketType.bug,
        ])).thenAnswer(
          (_) async => [
            ticket(id: 'a', embedding: _vector([1.0, 0.0])),
            ticket(id: 'b', embedding: _vector([1.0, 0.0])),
            ticket(id: 'c', embedding: _vector([1.0, 0.0])),
          ],
        );
        when(() => repository.getExecutionTokenTotals(any())).thenAnswer(
          (_) async => {'a': 12000, 'b': 34000},
        );

        await predictor.suggest(ticket(embedding: _vector([1.0, 0.0])));

        final captured = verify(
          () => repository.applyTokenPrediction(
            't1',
            low: captureAny(named: 'low'),
            high: captureAny(named: 'high'),
          ),
        ).captured;
        expect(captured[0], 12000);
        expect(captured[1], 34000);
      },
    );

    test(
      'a single comparable candidate with history yields a degenerate '
      'low == high range',
      () async {
        when(() => repository.getAllTicketsByType(any())).thenAnswer(
          (_) async => [ticket(id: 'a', embedding: _vector([1.0, 0.0]))],
        );
        when(
          () => repository.getExecutionTokenTotals(any()),
        ).thenAnswer((_) async => {'a': 5000});

        await predictor.suggest(ticket(embedding: _vector([1.0, 0.0])));

        final captured = verify(
          () => repository.applyTokenPrediction(
            't1',
            low: captureAny(named: 'low'),
            high: captureAny(named: 'high'),
          ),
        ).captured;
        expect(captured[0], 5000);
        expect(captured[1], 5000);
      },
    );

    test(
      'zero comparable candidates with execution history leaves fields '
      'untouched (no write)',
      () async {
        when(() => repository.getAllTicketsByType(any())).thenAnswer(
          (_) async => [ticket(id: 'a', embedding: _vector([1.0, 0.0]))],
        );
        when(
          () => repository.getExecutionTokenTotals(any()),
        ).thenAnswer((_) async => {});

        await predictor.suggest(ticket(embedding: _vector([1.0, 0.0])));

        verifyNeverApplied();
      },
    );

    test('a candidate pool with no embedding at all leaves fields '
        'untouched (no write)', () async {
      when(() => repository.getAllTicketsByType(any())).thenAnswer(
        (_) async => [ticket(id: 'a')], // no embedding
      );

      await predictor.suggest(ticket(embedding: _vector([1.0, 0.0])));

      verifyNeverApplied();
      verifyNever(() => repository.getExecutionTokenTotals(any()));
    });

    test('a thrown exception from a dependency is swallowed', () async {
      when(
        () => repository.getAllTicketsByType(any()),
      ).thenThrow(Exception('boom'));

      // Should not throw.
      await predictor.suggest(ticket(embedding: _vector([1.0, 0.0])));

      verifyNeverApplied();
    });
  });
}
