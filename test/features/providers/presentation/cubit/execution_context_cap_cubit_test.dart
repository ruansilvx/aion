import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/features/providers/providers.dart';

class MockExecutionContextCapRepository extends Mock
    implements ExecutionContextCapRepository {}

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

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
  late MockExecutionContextCapRepository capRepository;
  late MockModelRoutingRepository modelRoutingRepository;

  setUp(() {
    capRepository = MockExecutionContextCapRepository();
    modelRoutingRepository = MockModelRoutingRepository();
  });

  ExecutionContextCapCubit buildCubit() =>
      ExecutionContextCapCubit(capRepository, modelRoutingRepository);

  group('load', () {
    blocTest<ExecutionContextCapCubit, ExecutionContextCapState>(
      'reads the persisted override and the execution model\'s real '
      'contextWindowTokens, and emits ExecutionContextCapReady',
      setUp: () {
        when(
          () => capRepository.getContextCapOverride(),
        ).thenAnswer((_) async => 50000);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).thenAnswer((_) async => _sonnet);
      },
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [
        const ExecutionContextCapReady(
          overrideTokens: 50000,
          modelDefaultTokens: 200000,
        ),
      ],
    );

    blocTest<ExecutionContextCapCubit, ExecutionContextCapState>(
      'emits overrideTokens: null when no override is persisted',
      setUp: () {
        when(
          () => capRepository.getContextCapOverride(),
        ).thenAnswer((_) async => null);
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).thenAnswer((_) async => _haiku);
      },
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [
        const ExecutionContextCapReady(
          overrideTokens: null,
          modelDefaultTokens: 200000,
        ),
      ],
    );
  });

  group('setOverride', () {
    blocTest<ExecutionContextCapCubit, ExecutionContextCapState>(
      'persists a valid override below the model\'s real limit unchanged',
      setUp: () {
        when(
          () => capRepository.setContextCapOverride(50000),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const ExecutionContextCapReady(
        overrideTokens: null,
        modelDefaultTokens: 200000,
      ),
      act: (cubit) => cubit.setOverride(50000),
      expect: () => [
        const ExecutionContextCapReady(
          overrideTokens: 50000,
          modelDefaultTokens: 200000,
        ),
      ],
      verify: (_) {
        verify(() => capRepository.setContextCapOverride(50000)).called(1);
      },
    );

    blocTest<ExecutionContextCapCubit, ExecutionContextCapState>(
      'clamps a value at the model\'s real limit to one below it',
      setUp: () {
        when(
          () => capRepository.setContextCapOverride(199999),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const ExecutionContextCapReady(
        overrideTokens: null,
        modelDefaultTokens: 200000,
      ),
      act: (cubit) => cubit.setOverride(200000),
      expect: () => [
        const ExecutionContextCapReady(
          overrideTokens: 199999,
          modelDefaultTokens: 200000,
        ),
      ],
      verify: (_) {
        verify(() => capRepository.setContextCapOverride(199999)).called(1);
      },
    );

    blocTest<ExecutionContextCapCubit, ExecutionContextCapState>(
      'clamps a value far above the model\'s real limit the same way',
      setUp: () {
        when(
          () => capRepository.setContextCapOverride(199999),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const ExecutionContextCapReady(
        overrideTokens: null,
        modelDefaultTokens: 200000,
      ),
      act: (cubit) => cubit.setOverride(999999),
      expect: () => [
        const ExecutionContextCapReady(
          overrideTokens: 199999,
          modelDefaultTokens: 200000,
        ),
      ],
    );

    blocTest<ExecutionContextCapCubit, ExecutionContextCapState>(
      'clears the override on null',
      setUp: () {
        when(
          () => capRepository.setContextCapOverride(null),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const ExecutionContextCapReady(
        overrideTokens: 50000,
        modelDefaultTokens: 200000,
      ),
      act: (cubit) => cubit.setOverride(null),
      expect: () => [
        const ExecutionContextCapReady(
          overrideTokens: null,
          modelDefaultTokens: 200000,
        ),
      ],
      verify: (_) {
        verify(() => capRepository.setContextCapOverride(null)).called(1);
      },
    );

    blocTest<ExecutionContextCapCubit, ExecutionContextCapState>(
      'clears the override on a value <= 0',
      setUp: () {
        when(
          () => capRepository.setContextCapOverride(null),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const ExecutionContextCapReady(
        overrideTokens: 50000,
        modelDefaultTokens: 200000,
      ),
      act: (cubit) => cubit.setOverride(0),
      expect: () => [
        const ExecutionContextCapReady(
          overrideTokens: null,
          modelDefaultTokens: 200000,
        ),
      ],
    );

    blocTest<ExecutionContextCapCubit, ExecutionContextCapState>(
      'falls back to re-reading the model default when called before '
      'load (state is still Loading)',
      setUp: () {
        when(
          () => modelRoutingRepository.getModelForPhase(ModelPhase.execution),
        ).thenAnswer((_) async => _sonnet);
        when(
          () => capRepository.setContextCapOverride(75000),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) => cubit.setOverride(75000),
      expect: () => [
        const ExecutionContextCapReady(
          overrideTokens: 75000,
          modelDefaultTokens: 200000,
        ),
      ],
    );
  });
}
