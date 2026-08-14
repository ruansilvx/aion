// test/features/providers/presentation/cubit/execution_scheduling_cubit_test.dart — ExecutionSchedulingCubit tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/providers/providers.dart';

class MockExecutionSchedulingRepository extends Mock
    implements ExecutionSchedulingRepository {}

void main() {
  late MockExecutionSchedulingRepository repository;

  setUpAll(() {
    registerFallbackValue(ExecutionSchedulingMode.strictFifo);
  });

  setUp(() {
    repository = MockExecutionSchedulingRepository();
  });

  ExecutionSchedulingCubit buildCubit() => ExecutionSchedulingCubit(repository);

  group('load', () {
    blocTest<ExecutionSchedulingCubit, ExecutionSchedulingState>(
      'reads the persisted mode and concurrency ceiling and emits '
      'ExecutionSchedulingReady',
      setUp: () {
        when(
          () => repository.getMode(),
        ).thenAnswer((_) async => ExecutionSchedulingMode.hybrid);
        when(() => repository.getConcurrencyCeiling()).thenAnswer((_) async => 4);
      },
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [
        const ExecutionSchedulingReady(
          mode: ExecutionSchedulingMode.hybrid,
          concurrencyCeiling: 4,
        ),
      ],
    );

    blocTest<ExecutionSchedulingCubit, ExecutionSchedulingState>(
      'defaults to strictFifo/2 when nothing has been persisted',
      setUp: () {
        when(
          () => repository.getMode(),
        ).thenAnswer((_) async => ExecutionSchedulingMode.strictFifo);
        when(() => repository.getConcurrencyCeiling()).thenAnswer((_) async => 2);
      },
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [
        const ExecutionSchedulingReady(
          mode: ExecutionSchedulingMode.strictFifo,
          concurrencyCeiling: 2,
        ),
      ],
    );
  });

  group('selectMode', () {
    blocTest<ExecutionSchedulingCubit, ExecutionSchedulingState>(
      'persists the new mode, preserving the current concurrency ceiling',
      setUp: () {
        when(
          () => repository.setMode(ExecutionSchedulingMode.parallel),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const ExecutionSchedulingReady(
        mode: ExecutionSchedulingMode.strictFifo,
        concurrencyCeiling: 3,
      ),
      act: (cubit) => cubit.selectMode(ExecutionSchedulingMode.parallel),
      expect: () => [
        const ExecutionSchedulingReady(
          mode: ExecutionSchedulingMode.parallel,
          concurrencyCeiling: 3,
        ),
      ],
      verify: (_) {
        verify(
          () => repository.setMode(ExecutionSchedulingMode.parallel),
        ).called(1);
      },
    );

    blocTest<ExecutionSchedulingCubit, ExecutionSchedulingState>(
      'is a no-op when called before load (state is still Loading)',
      build: buildCubit,
      act: (cubit) => cubit.selectMode(ExecutionSchedulingMode.parallel),
      expect: () => const <ExecutionSchedulingState>[],
      verify: (_) {
        verifyNever(() => repository.setMode(any()));
      },
    );
  });

  group('setConcurrencyCeiling', () {
    blocTest<ExecutionSchedulingCubit, ExecutionSchedulingState>(
      'persists a valid ceiling unchanged, preserving the current mode',
      setUp: () {
        when(() => repository.setConcurrencyCeiling(5)).thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const ExecutionSchedulingReady(
        mode: ExecutionSchedulingMode.hybrid,
        concurrencyCeiling: 2,
      ),
      act: (cubit) => cubit.setConcurrencyCeiling(5),
      expect: () => [
        const ExecutionSchedulingReady(
          mode: ExecutionSchedulingMode.hybrid,
          concurrencyCeiling: 5,
        ),
      ],
      verify: (_) {
        verify(() => repository.setConcurrencyCeiling(5)).called(1);
      },
    );

    blocTest<ExecutionSchedulingCubit, ExecutionSchedulingState>(
      'clamps a ceiling below 1 up to 1',
      setUp: () {
        when(() => repository.setConcurrencyCeiling(1)).thenAnswer((_) async {});
      },
      build: buildCubit,
      seed: () => const ExecutionSchedulingReady(
        mode: ExecutionSchedulingMode.parallel,
        concurrencyCeiling: 2,
      ),
      act: (cubit) => cubit.setConcurrencyCeiling(0),
      expect: () => [
        const ExecutionSchedulingReady(
          mode: ExecutionSchedulingMode.parallel,
          concurrencyCeiling: 1,
        ),
      ],
      verify: (_) {
        verify(() => repository.setConcurrencyCeiling(1)).called(1);
      },
    );

    blocTest<ExecutionSchedulingCubit, ExecutionSchedulingState>(
      'is a no-op when called before load (state is still Loading)',
      build: buildCubit,
      act: (cubit) => cubit.setConcurrencyCeiling(3),
      expect: () => const <ExecutionSchedulingState>[],
      verify: (_) {
        verifyNever(() => repository.setConcurrencyCeiling(any()));
      },
    );
  });
}
