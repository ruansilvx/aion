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

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

class MockAgentProvider extends Mock implements AgentProvider {}

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

class _FakeAgentRequest extends Fake implements AgentRequest {}

const _sonnet = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'claude-sonnet-5',
  label: 'Sonnet 5',
  contextWindowTokens: 200000,
);
const _haiku = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'claude-haiku-4-5',
  label: 'Haiku 4.5',
  contextWindowTokens: 200000,
);

void main() {
  late MockAgentModelClient client;
  late MockAgentProvider provider;
  late MockProviderRegistry registry;
  late MockModelRoutingRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeAgentRequest());
    registerFallbackValue(_sonnet);
    registerFallbackValue(ModelPhase.frontier);
    registerFallbackValue(ProviderId.claudeAgentSdk);
  });

  setUp(() {
    client = MockAgentModelClient();
    provider = MockAgentProvider();
    registry = MockProviderRegistry();
    repository = MockModelRoutingRepository();

    when(() => provider.client).thenReturn(client);
    when(
      () => provider.normalizeErrorMessage(any()),
    ).thenAnswer((invocation) => invocation.positionalArguments[0] as String);
    when(
      () => registry.providerById(ProviderId.claudeAgentSdk),
    ).thenReturn(provider);
  });

  group('ProviderSettingsCubit', () {
    blocTest<ProviderSettingsCubit, ProviderSettingsState>(
      'load emits [Ready(unknown), Ready(checking), Ready(connected)] on a '
      'successful connection test, pinging the Frontier-tier model',
      setUp: () {
        when(
          () => repository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => _sonnet);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      build: () => ProviderSettingsCubit(registry, repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.unknown,
        ),
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.checking,
        ),
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.connected,
        ),
      ],
    );

    blocTest<ProviderSettingsCubit, ProviderSettingsState>(
      'load emits Ready(disconnected) carrying the error message on a '
      'failed connection test',
      setUp: () {
        when(
          () => repository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => _sonnet);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentErrorEvent('Node.js not found.'),
          ]),
        );
      },
      build: () => ProviderSettingsCubit(registry, repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.unknown,
        ),
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.checking,
        ),
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.disconnected,
          statusMessage: 'Node.js not found.',
        ),
      ],
    );

    blocTest<ProviderSettingsCubit, ProviderSettingsState>(
      "load emits Ready(disconnected) with the statusMessage passed "
      'through AgentProvider.normalizeErrorMessage, not the raw message',
      setUp: () {
        when(
          () => repository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => _sonnet);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentErrorEvent('Please run `/login` to reauthenticate.'),
          ]),
        );
        when(
          () => provider.normalizeErrorMessage(
            'Please run `/login` to reauthenticate.',
          ),
        ).thenReturn('Authentication failed.');
      },
      build: () => ProviderSettingsCubit(registry, repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.unknown,
        ),
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.checking,
        ),
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.disconnected,
          statusMessage: 'Authentication failed.',
        ),
      ],
    );

    blocTest<ProviderSettingsCubit, ProviderSettingsState>(
      'load emits Ready(connected) carrying an overage notice as '
      'statusMessage, not a disconnected failure',
      setUp: () {
        when(
          () => repository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => _sonnet);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentOverageDetectedEvent('Over your plan\'s usage limit.'),
            AgentDoneEvent(),
          ]),
        );
      },
      build: () => ProviderSettingsCubit(registry, repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.unknown,
        ),
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.checking,
        ),
        const ProviderSettingsReady(
          selectedModel: _sonnet,
          status: ProviderConnectionStatus.connected,
          statusMessage: 'Over your plan\'s usage limit.',
        ),
      ],
    );

    blocTest<ProviderSettingsCubit, ProviderSettingsState>(
      'testConnection re-reads the Frontier-tier model fresh from the '
      'repository, picking up a change made since the last test',
      setUp: () {
        when(
          () => repository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => _haiku);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentDoneEvent()]),
        );
      },
      seed: () => const ProviderSettingsReady(
        selectedModel: _sonnet,
        status: ProviderConnectionStatus.connected,
      ),
      build: () => ProviderSettingsCubit(registry, repository),
      act: (cubit) => cubit.testConnection(),
      expect: () => [
        const ProviderSettingsReady(
          selectedModel: _haiku,
          status: ProviderConnectionStatus.checking,
        ),
        const ProviderSettingsReady(
          selectedModel: _haiku,
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

    test(
      'testConnection no-ops while a test is already checking, instead of '
      'racing a second in-flight test',
      () async {
        when(
          () => repository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => _sonnet);
        final controller = StreamController<AgentEvent>();
        when(
          () => client.run(any()),
        ).thenAnswer((_) async => controller.stream);

        final cubit = ProviderSettingsCubit(registry, repository);
        final loadFuture = cubit.load();
        // Yield once so `load()` reaches the `checking` state — the
        // `client.run` stream never emits until `controller` is closed
        // below, so this is deterministic rather than a timing guess.
        await Future<void>.delayed(Duration.zero);
        expect(
          (cubit.state as ProviderSettingsReady).status,
          ProviderConnectionStatus.checking,
        );

        await cubit.testConnection();

        // Only load()'s own call went through — the no-op above didn't
        // start a second run().
        verify(() => client.run(any())).called(1);

        controller.add(const AgentDoneEvent());
        await controller.close();
        await loadFuture;
        await cubit.close();
      },
    );
  });
}
