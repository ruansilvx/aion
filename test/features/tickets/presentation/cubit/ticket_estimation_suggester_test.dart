import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_estimation_suggester.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

class MockAgentProvider extends Mock implements AgentProvider {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockTicketRepository extends Mock implements TicketRepository {}

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

const _sonnet = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'claude-sonnet-5',
  label: 'Sonnet 5',
  contextWindowTokens: 200000,
);

/// Builds a raw `Float32List` embedding, serialized the same way
/// `EmbeddingProvider.embed` does.
Uint8List _vector(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

void main() {
  late MockEmbeddingProvider embeddingProvider;
  late MockProviderRegistry providerRegistry;
  late MockAgentProvider agentProvider;
  late MockAgentModelClient client;
  late MockTicketRepository repository;
  late MockModelRoutingRepository modelRoutingRepository;
  late TicketEstimationSuggester suggester;

  Ticket ticket({
    String id = 't1',
    TicketEstimationSource? complexitySource,
    TicketEstimationSource? estimateSource,
    TicketComplexity? complexity,
    int? estimate,
  }) => Ticket(
    id: id,
    ticketId: 'AIO-$id',
    type: TicketType.task,
    title: 'Do the thing',
    description: 'Some description',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    complexity: complexity,
    estimate: estimate,
    complexitySource: complexitySource,
    estimateSource: estimateSource,
  );

  setUpAll(() {
    registerFallbackValue(const AgentRequest(prompt: '', model: ''));
  });

  setUp(() {
    embeddingProvider = MockEmbeddingProvider();
    providerRegistry = MockProviderRegistry();
    agentProvider = MockAgentProvider();
    client = MockAgentModelClient();
    repository = MockTicketRepository();
    modelRoutingRepository = MockModelRoutingRepository();

    when(() => agentProvider.client).thenReturn(client);
    when(
      () => providerRegistry.providerById(ProviderId.claudeAgentSdk),
    ).thenReturn(agentProvider);
    when(
      () => modelRoutingRepository.getModelForPhase(ModelPhase.capable),
    ).thenAnswer((_) async => _sonnet);
    when(
      () => embeddingProvider.embed(any()),
    ).thenAnswer((_) async => _vector([1.0, 0.0]));
    when(() => repository.getAllTickets()).thenAnswer((_) async => []);

    suggester = TicketEstimationSuggester(
      repository,
      embeddingProvider: embeddingProvider,
      providerRegistry: providerRegistry,
      modelRoutingRepository: modelRoutingRepository,
    );
  });

  void mockModelReply(String text) {
    when(() => client.run(any())).thenAnswer(
      (_) async => Stream.fromIterable([AgentTextEvent(text), AgentDoneEvent()]),
    );
  }

  group('suggest', () {
    test('no-ops without ever calling the model when both fields are '
        'manual-locked', () async {
      await suggester.suggest(
        ticket(
          complexitySource: TicketEstimationSource.manual,
          estimateSource: TicketEstimationSource.manual,
        ),
      );

      verifyNever(() => embeddingProvider.embed(any()));
      verifyNever(() => client.run(any()));
      verifyNever(
        () => repository.applyEstimationSuggestion(
          any(),
          complexity: any(named: 'complexity'),
          estimate: any(named: 'estimate'),
        ),
      );
    });

    test('cold start (no comparable tickets) marks both fields '
        'low-confidence', () async {
      mockModelReply('COMPLEXITY: medium\nESTIMATE_MINUTES: 90');

      await suggester.suggest(ticket());

      final captured = verify(
        () => repository.applyEstimationSuggestion(
          't1',
          complexity: captureAny(named: 'complexity'),
          estimate: captureAny(named: 'estimate'),
        ),
      ).captured;
      final complexityArg =
          captured[0] as ({TicketComplexity value, bool lowConfidence})?;
      final estimateArg = captured[1] as ({int value, bool lowConfidence})?;

      expect(complexityArg!.value, TicketComplexity.medium);
      expect(complexityArg.lowConfidence, isTrue);
      expect(estimateArg!.value, 90);
      expect(estimateArg.lowConfidence, isTrue);
    });

    test('comparable tickets found marks both fields plain aiSuggested', () async {
      final comparable = ticket(
        id: 'other',
        complexity: TicketComplexity.large,
        estimate: 240,
      );
      when(() => repository.getAllTickets()).thenAnswer(
        (_) async => [
          Ticket(
            id: comparable.id,
            ticketId: comparable.ticketId,
            type: comparable.type,
            title: comparable.title,
            status: comparable.status,
            createdAt: comparable.createdAt,
            updatedAt: comparable.updatedAt,
            complexity: comparable.complexity,
            estimate: comparable.estimate,
            embedding: _vector([1.0, 0.0]),
          ),
        ],
      );
      mockModelReply('COMPLEXITY: large\nESTIMATE_MINUTES: 200');

      await suggester.suggest(ticket());

      final captured = verify(
        () => repository.applyEstimationSuggestion(
          't1',
          complexity: captureAny(named: 'complexity'),
          estimate: captureAny(named: 'estimate'),
        ),
      ).captured;
      final complexityArg =
          captured[0] as ({TicketComplexity value, bool lowConfidence})?;
      final estimateArg = captured[1] as ({int value, bool lowConfidence})?;

      expect(complexityArg!.lowConfidence, isFalse);
      expect(estimateArg!.lowConfidence, isFalse);
    });

    test('a missing/malformed response line skips only that field', () async {
      mockModelReply('COMPLEXITY: small\nnothing else useful here');

      await suggester.suggest(ticket());

      final captured = verify(
        () => repository.applyEstimationSuggestion(
          't1',
          complexity: captureAny(named: 'complexity'),
          estimate: captureAny(named: 'estimate'),
        ),
      ).captured;
      final complexityArg =
          captured[0] as ({TicketComplexity value, bool lowConfidence})?;
      final estimateArg = captured[1] as ({int value, bool lowConfidence})?;

      expect(complexityArg!.value, TicketComplexity.small);
      expect(estimateArg, isNull);
    });

    test('an ESTIMATE_MINUTES of 0 is treated as missing', () async {
      mockModelReply('COMPLEXITY: small\nESTIMATE_MINUTES: 0');

      await suggester.suggest(ticket());

      final captured = verify(
        () => repository.applyEstimationSuggestion(
          't1',
          complexity: captureAny(named: 'complexity'),
          estimate: captureAny(named: 'estimate'),
        ),
      ).captured;
      expect(captured[1], isNull);
    });

    test('an AgentErrorEvent is swallowed without writing anything', () async {
      when(() => client.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [
          AgentErrorEvent('model unavailable'),
        ]),
      );

      await suggester.suggest(ticket());

      verifyNever(
        () => repository.applyEstimationSuggestion(
          any(),
          complexity: any(named: 'complexity'),
          estimate: any(named: 'estimate'),
        ),
      );
    });

    test('a thrown exception from a dependency is swallowed', () async {
      when(() => embeddingProvider.embed(any())).thenThrow(Exception('boom'));

      // Should not throw.
      await suggester.suggest(ticket());

      verifyNever(
        () => repository.applyEstimationSuggestion(
          any(),
          complexity: any(named: 'complexity'),
          estimate: any(named: 'estimate'),
        ),
      );
    });

    test('no-ops entirely without an EmbeddingProvider/ProviderRegistry', () async {
      final bareSuggester = TicketEstimationSuggester(repository);

      await bareSuggester.suggest(ticket());

      verifyNever(
        () => repository.applyEstimationSuggestion(
          any(),
          complexity: any(named: 'complexity'),
          estimate: any(named: 'estimate'),
        ),
      );
    });
  });

  group('regenerate', () {
    test('bypasses the lock for only the forced field, leaving the other '
        "field's source completely untouched", () async {
      mockModelReply('COMPLEXITY: large\nESTIMATE_MINUTES: 500');

      await suggester.regenerate(
        ticket(
          complexitySource: TicketEstimationSource.manual,
          estimateSource: TicketEstimationSource.manual,
        ),
        forceComplexity: true,
      );

      final captured = verify(
        () => repository.applyEstimationSuggestion(
          't1',
          complexity: captureAny(named: 'complexity'),
          estimate: captureAny(named: 'estimate'),
        ),
      ).captured;
      final complexityArg =
          captured[0] as ({TicketComplexity value, bool lowConfidence})?;
      final estimateArg = captured[1] as ({int value, bool lowConfidence})?;

      expect(complexityArg, isNotNull);
      expect(estimateArg, isNull);
    });
  });
}
