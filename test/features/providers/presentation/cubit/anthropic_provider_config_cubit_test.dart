import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/providers.dart';

class MockAnthropicApiKeyRepository extends Mock
    implements AnthropicApiKeyRepository {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

class MockAgentProvider extends Mock implements AgentProvider {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class _FakeAgentRequest extends Fake implements AgentRequest {}

const _opus = AgentModelDescriptor(
  providerId: ProviderId.anthropicMessagesApi,
  modelId: 'claude-opus-4-8',
  label: 'Opus 4.8',
  contextWindowTokens: 200000,
);
const _haiku = AgentModelDescriptor(
  providerId: ProviderId.anthropicMessagesApi,
  modelId: 'claude-haiku-4-5',
  label: 'Haiku 4.5',
  contextWindowTokens: 200000,
);

void main() {
  late MockAnthropicApiKeyRepository repository;
  late MockProviderRegistry registry;
  late MockAgentProvider provider;
  late MockAgentModelClient client;

  setUpAll(() {
    registerFallbackValue(_FakeAgentRequest());
  });

  setUp(() {
    repository = MockAnthropicApiKeyRepository();
    registry = MockProviderRegistry();
    provider = MockAgentProvider();
    client = MockAgentModelClient();

    when(() => provider.client).thenReturn(client);
    when(() => provider.availableModels).thenReturn(const [_opus, _haiku]);
    when(
      () => provider.normalizeErrorMessage(any()),
    ).thenAnswer((invocation) => invocation.positionalArguments[0] as String);
    when(
      () => registry.providerById(ProviderId.anthropicMessagesApi),
    ).thenReturn(provider);
  });

  group('AnthropicProviderConfigCubit', () {
    blocTest<AnthropicProviderConfigCubit, AnthropicProviderConfigState>(
      'load emits Ready(hasApiKey: false, unknown) when nothing is stored, '
      'without ever calling the client',
      setUp: () {
        when(() => repository.getApiKey()).thenAnswer((_) async => null);
      },
      build: () => AnthropicProviderConfigCubit(repository, registry),
      act: (cubit) => cubit.load(),
      expect: () => [
        const AnthropicProviderConfigReady(
          hasApiKey: false,
          status: ProviderConnectionStatus.unknown,
        ),
      ],
      verify: (_) {
        verifyNever(() => client.run(any()));
      },
    );

    blocTest<AnthropicProviderConfigCubit, AnthropicProviderConfigState>(
      'load emits Ready(hasApiKey: true, unknown) when a key is stored, '
      'without ever calling the client',
      setUp: () {
        when(
          () => repository.getApiKey(),
        ).thenAnswer((_) async => 'sk-ant-abc123');
      },
      build: () => AnthropicProviderConfigCubit(repository, registry),
      act: (cubit) => cubit.load(),
      expect: () => [
        const AnthropicProviderConfigReady(
          hasApiKey: true,
          status: ProviderConnectionStatus.unknown,
        ),
      ],
      verify: (_) {
        verifyNever(() => client.run(any()));
      },
    );

    blocTest<AnthropicProviderConfigCubit, AnthropicProviderConfigState>(
      'saveApiKey trims the raw key and persists it, resetting status to '
      'unknown',
      setUp: () {
        when(() => repository.setApiKey(any())).thenAnswer((_) async {});
      },
      seed: () => const AnthropicProviderConfigReady(
        hasApiKey: false,
        status: ProviderConnectionStatus.connected,
      ),
      build: () => AnthropicProviderConfigCubit(repository, registry),
      act: (cubit) => cubit.saveApiKey('  sk-ant-abc123  '),
      expect: () => [
        const AnthropicProviderConfigReady(
          hasApiKey: true,
          status: ProviderConnectionStatus.unknown,
        ),
      ],
      verify: (_) {
        verify(() => repository.setApiKey('sk-ant-abc123')).called(1);
      },
    );

    blocTest<AnthropicProviderConfigCubit, AnthropicProviderConfigState>(
      'saveApiKey with an empty/whitespace-only value clears the stored '
      'key',
      setUp: () {
        when(() => repository.setApiKey(any())).thenAnswer((_) async {});
      },
      seed: () => const AnthropicProviderConfigReady(
        hasApiKey: true,
        status: ProviderConnectionStatus.connected,
      ),
      build: () => AnthropicProviderConfigCubit(repository, registry),
      act: (cubit) => cubit.saveApiKey('   '),
      expect: () => [
        const AnthropicProviderConfigReady(
          hasApiKey: false,
          status: ProviderConnectionStatus.unknown,
        ),
      ],
      verify: (_) {
        verify(() => repository.setApiKey(null)).called(1);
      },
    );

    blocTest<AnthropicProviderConfigCubit, AnthropicProviderConfigState>(
      'testConnection no-ops when no API key is stored',
      seed: () => const AnthropicProviderConfigReady(
        hasApiKey: false,
        status: ProviderConnectionStatus.unknown,
      ),
      build: () => AnthropicProviderConfigCubit(repository, registry),
      act: (cubit) => cubit.testConnection(),
      expect: () => <AnthropicProviderConfigState>[],
      verify: (_) {
        verifyNever(() => client.run(any()));
      },
    );

    blocTest<AnthropicProviderConfigCubit, AnthropicProviderConfigState>(
      'testConnection no-ops while a test is already checking',
      seed: () => const AnthropicProviderConfigReady(
        hasApiKey: true,
        status: ProviderConnectionStatus.checking,
      ),
      build: () => AnthropicProviderConfigCubit(repository, registry),
      act: (cubit) => cubit.testConnection(),
      expect: () => <AnthropicProviderConfigState>[],
      verify: (_) {
        verifyNever(() => client.run(any()));
      },
    );

    blocTest<AnthropicProviderConfigCubit, AnthropicProviderConfigState>(
      'testConnection pings the cheapest model (availableModels.last) and '
      'emits connected on success',
      setUp: () {
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      seed: () => const AnthropicProviderConfigReady(
        hasApiKey: true,
        status: ProviderConnectionStatus.unknown,
      ),
      build: () => AnthropicProviderConfigCubit(repository, registry),
      act: (cubit) => cubit.testConnection(),
      expect: () => [
        const AnthropicProviderConfigReady(
          hasApiKey: true,
          status: ProviderConnectionStatus.checking,
        ),
        const AnthropicProviderConfigReady(
          hasApiKey: true,
          status: ProviderConnectionStatus.connected,
        ),
      ],
      verify: (_) {
        verify(
          () => client.run(
            any(
              that: predicate<AgentRequest>(
                (request) => request.model == _haiku.modelId,
              ),
            ),
          ),
        ).called(1);
      },
    );

    blocTest<AnthropicProviderConfigCubit, AnthropicProviderConfigState>(
      'testConnection emits disconnected with the normalized error message '
      'on failure',
      setUp: () {
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentErrorEvent('HTTP 401 error.'),
          ]),
        );
        when(
          () => provider.normalizeErrorMessage('HTTP 401 error.'),
        ).thenReturn('Invalid API key.');
      },
      seed: () => const AnthropicProviderConfigReady(
        hasApiKey: true,
        status: ProviderConnectionStatus.unknown,
      ),
      build: () => AnthropicProviderConfigCubit(repository, registry),
      act: (cubit) => cubit.testConnection(),
      expect: () => [
        const AnthropicProviderConfigReady(
          hasApiKey: true,
          status: ProviderConnectionStatus.checking,
        ),
        const AnthropicProviderConfigReady(
          hasApiKey: true,
          status: ProviderConnectionStatus.disconnected,
          statusMessage: 'Invalid API key.',
        ),
      ],
    );

    blocTest<AnthropicProviderConfigCubit, AnthropicProviderConfigState>(
      'testConnection emits connected carrying an overage notice as '
      'statusMessage, not a disconnected failure',
      setUp: () {
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentOverageDetectedEvent('Rate limited — too many requests.'),
            AgentDoneEvent(),
          ]),
        );
      },
      seed: () => const AnthropicProviderConfigReady(
        hasApiKey: true,
        status: ProviderConnectionStatus.unknown,
      ),
      build: () => AnthropicProviderConfigCubit(repository, registry),
      act: (cubit) => cubit.testConnection(),
      expect: () => [
        const AnthropicProviderConfigReady(
          hasApiKey: true,
          status: ProviderConnectionStatus.checking,
        ),
        const AnthropicProviderConfigReady(
          hasApiKey: true,
          status: ProviderConnectionStatus.connected,
          statusMessage: 'Rate limited — too many requests.',
        ),
      ],
    );

    test(
      'testConnection no-ops while a test it itself started is still '
      'in flight, instead of racing a second one',
      () async {
        when(
          () => repository.getApiKey(),
        ).thenAnswer((_) async => 'sk-ant-abc123');
        final controller = StreamController<AgentEvent>();
        when(
          () => client.run(any()),
        ).thenAnswer((_) async => controller.stream);

        final cubit = AnthropicProviderConfigCubit(repository, registry);
        await cubit.load();

        final testFuture = cubit.testConnection();
        // Yield once so `testConnection` reaches the `checking` state —
        // `client.run`'s stream never emits until `controller` is closed
        // below, so this is deterministic rather than a timing guess.
        await Future<void>.delayed(Duration.zero);
        expect(
          (cubit.state as AnthropicProviderConfigReady).status,
          ProviderConnectionStatus.checking,
        );

        await cubit.testConnection();

        // Only the first call went through — the no-op above didn't start
        // a second run().
        verify(() => client.run(any())).called(1);

        controller.add(const AgentDoneEvent());
        await controller.close();
        await testFuture;
        await cubit.close();
      },
    );
  });
}
