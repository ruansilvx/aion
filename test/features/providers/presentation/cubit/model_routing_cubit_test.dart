import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/providers/providers.dart';

class MockModelRoutingRepository extends Mock
    implements ModelRoutingRepository {}

void main() {
  late MockModelRoutingRepository repository;

  setUpAll(() {
    registerFallbackValue(ModelPhase.frontier);
    registerFallbackValue(AgentModel.sonnet);
  });

  setUp(() {
    repository = MockModelRoutingRepository();
  });

  group('ModelRoutingCubit', () {
    blocTest<ModelRoutingCubit, ModelRoutingState>(
      'load fetches every ModelPhase value and emits a keyed map',
      setUp: () {
        when(
          () => repository.getModelForPhase(ModelPhase.frontier),
        ).thenAnswer((_) async => AgentModel.opus);
        when(
          () => repository.getModelForPhase(ModelPhase.capable),
        ).thenAnswer((_) async => AgentModel.sonnet);
        when(
          () => repository.getModelForPhase(ModelPhase.execution),
        ).thenAnswer((_) async => AgentModel.haiku);
      },
      build: () => ModelRoutingCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const ModelRoutingReady({
          ModelPhase.frontier: AgentModel.opus,
          ModelPhase.capable: AgentModel.sonnet,
          ModelPhase.execution: AgentModel.haiku,
        }),
      ],
    );

    blocTest<ModelRoutingCubit, ModelRoutingState>(
      'selectModel persists the chosen phase only, leaving the other '
      "phases' entries in the re-emitted map untouched",
      setUp: () {
        when(
          () => repository.setModelForPhase(ModelPhase.execution, AgentModel.opus),
        ).thenAnswer((_) async {});
      },
      build: () => ModelRoutingCubit(repository),
      seed: () => const ModelRoutingReady({
        ModelPhase.frontier: AgentModel.opus,
        ModelPhase.capable: AgentModel.sonnet,
        ModelPhase.execution: AgentModel.haiku,
      }),
      act: (cubit) => cubit.selectModel(ModelPhase.execution, AgentModel.opus),
      expect: () => [
        const ModelRoutingReady({
          ModelPhase.frontier: AgentModel.opus,
          ModelPhase.capable: AgentModel.sonnet,
          ModelPhase.execution: AgentModel.opus,
        }),
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
  });
}
