import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/core/contracts/tool_access_tier.dart';
import 'package:aion/features/providers/providers.dart';

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

class MockAgentProvider extends Mock implements AgentProvider {}

const _opus = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'claude-opus-4-8',
  label: 'Opus 4.8',
  contextWindowTokens: 200000,
);
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
const _otherModel = AgentModelDescriptor(
  providerId: ProviderId.claudeAgentSdk,
  modelId: 'claude-other-model',
  label: 'Other Model',
  contextWindowTokens: 100000,
);

void main() {
  late MockModelRoutingRepository repository;
  late MockProviderRegistry registry;
  late MockAgentProvider provider;

  setUpAll(() {
    registerFallbackValue(ModelPhase.frontier);
    registerFallbackValue(_opus);
  });

  setUp(() {
    repository = MockModelRoutingRepository();
    registry = MockProviderRegistry();
    provider = MockAgentProvider();
    when(
      () => provider.supportedToolAccessTiers,
    ).thenReturn({ToolAccessTier.noTools, ToolAccessTier.full});
    when(
      () => provider.availableModels,
    ).thenReturn([_opus, _sonnet, _haiku]);
    when(() => registry.availableProviders).thenReturn([provider]);
  });

  group('ModelRoutingCubit', () {
    blocTest<ModelRoutingCubit, ModelRoutingState>(
      'load fetches every ModelPhase value and emits a keyed map plus '
      'per-phase available models',
      setUp: () {
        when(
          () => repository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => _opus);
        when(
          () => repository.getModelForPhase(ModelPhase.capable),
        ).thenAnswer((_) async => _sonnet);
        when(
          () => repository.getModelForPhase(ModelPhase.execution),
        ).thenAnswer((_) async => _haiku);
      },
      build: () => ModelRoutingCubit(repository, registry),
      act: (cubit) => cubit.load(),
      expect: () => [
        ModelRoutingReady(
          const {
            ModelPhase.frontier: _opus,
            ModelPhase.capable: _sonnet,
            ModelPhase.execution: _haiku,
          },
          const {
            ModelPhase.frontier: [_opus, _sonnet, _haiku],
            ModelPhase.capable: [_opus, _sonnet, _haiku],
            ModelPhase.execution: [_opus, _sonnet, _haiku],
          },
        ),
      ],
    );

    blocTest<ModelRoutingCubit, ModelRoutingState>(
      'selectModel persists the chosen phase only, leaving the other '
      "phases' entries in the re-emitted map untouched, and preserves "
      'the current availableModels',
      setUp: () {
        when(
          () => repository.setModelForPhase(ModelPhase.execution, _opus),
        ).thenAnswer((_) async {});
      },
      build: () => ModelRoutingCubit(repository, registry),
      seed: () => ModelRoutingReady(
        const {
          ModelPhase.frontier: _opus,
          ModelPhase.capable: _sonnet,
          ModelPhase.execution: _haiku,
        },
        const {
          ModelPhase.frontier: [_opus, _sonnet, _haiku],
          ModelPhase.capable: [_opus, _sonnet, _haiku],
          ModelPhase.execution: [_opus, _sonnet, _haiku],
        },
      ),
      act: (cubit) => cubit.selectModel(ModelPhase.execution, _opus),
      expect: () => [
        ModelRoutingReady(
          const {
            ModelPhase.frontier: _opus,
            ModelPhase.capable: _sonnet,
            ModelPhase.execution: _opus,
          },
          const {
            ModelPhase.frontier: [_opus, _sonnet, _haiku],
            ModelPhase.capable: [_opus, _sonnet, _haiku],
            ModelPhase.execution: [_opus, _sonnet, _haiku],
          },
        ),
      ],
      verify: (_) {
        verifyNever(
          () => repository.setModelForPhase(ModelPhase.frontier, any()),
        );
        verifyNever(
          () => repository.setModelForPhase(ModelPhase.capable, any()),
        );
      },
    );

    blocTest<ModelRoutingCubit, ModelRoutingState>(
      'a second provider lacking full tool-access support is excluded '
      "from execution's availableModels but still included in "
      "frontier's/capable's",
      setUp: () {
        final noToolsOnlyProvider = MockAgentProvider();
        when(
          () => noToolsOnlyProvider.supportedToolAccessTiers,
        ).thenReturn({ToolAccessTier.noTools});
        when(
          () => noToolsOnlyProvider.availableModels,
        ).thenReturn([_otherModel]);
        when(
          () => registry.availableProviders,
        ).thenReturn([provider, noToolsOnlyProvider]);

        when(
          () => repository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => _opus);
        when(
          () => repository.getModelForPhase(ModelPhase.capable),
        ).thenAnswer((_) async => _sonnet);
        when(
          () => repository.getModelForPhase(ModelPhase.execution),
        ).thenAnswer((_) async => _haiku);
      },
      build: () => ModelRoutingCubit(repository, registry),
      act: (cubit) => cubit.load(),
      verify: (cubit) {
        final state = cubit.state as ModelRoutingReady;
        expect(
          state.availableModels[ModelPhase.execution],
          unorderedEquals([_opus, _sonnet, _haiku]),
        );
        expect(
          state.availableModels[ModelPhase.frontier],
          unorderedEquals([_opus, _sonnet, _haiku, _otherModel]),
        );
        expect(
          state.availableModels[ModelPhase.capable],
          unorderedEquals([_opus, _sonnet, _haiku, _otherModel]),
        );
      },
    );
  });
}
