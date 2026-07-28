import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/active_project_provider.dart';
import 'package:aion/features/projects/projects.dart';

class MockBaselineRepository extends Mock implements BaselineRepository {}

class MockActiveProjectProvider extends Mock implements ActiveProjectProvider {}

void main() {
  late MockBaselineRepository baselineRepository;
  late MockActiveProjectProvider activeProjectProvider;

  Project buildProject({String baselineVersion = '0.1.0'}) => Project(
    id: '1',
    name: 'Test Project',
    storageKey: '1',
    baselineVersion: baselineVersion,
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    baselineRepository = MockBaselineRepository();
    activeProjectProvider = MockActiveProjectProvider();
  });

  BaselineUpgradeCubit buildCubit() =>
      BaselineUpgradeCubit(baselineRepository, activeProjectProvider);

  group('BaselineUpgradeCubit', () {
    blocTest<BaselineUpgradeCubit, BaselineUpgradeState>(
      'load emits BaselineUpgradeReady with the correct current/latest '
      'versions',
      setUp: () {
        when(
          () => baselineRepository.getAvailableBaselineVersions(),
        ).thenAnswer((_) async => ['0.1.0', '0.2.0']);
        when(
          () => activeProjectProvider.activeProject,
        ).thenReturn(buildProject());
      },
      build: buildCubit,
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<BaselineUpgradeReady>()
            .having((s) => s.currentVersion, 'currentVersion', '0.1.0')
            .having((s) => s.latestVersion, 'latestVersion', '0.2.0'),
      ],
    );

    blocTest<BaselineUpgradeCubit, BaselineUpgradeState>(
      'upgrade emits isUpgrading: true then a final ready state '
      'reflecting the bumped version, calling acceptBaselineUpgrade '
      'exactly once',
      setUp: () {
        when(
          () => baselineRepository.getAvailableBaselineVersions(),
        ).thenAnswer((_) async => ['0.1.0', '0.2.0']);
        when(() => activeProjectProvider.activeProject).thenAnswer(
          (_) => buildProject(),
        );
        when(
          () => activeProjectProvider.acceptBaselineUpgrade(),
        ).thenAnswer((_) async {
          when(
            () => activeProjectProvider.activeProject,
          ).thenReturn(buildProject(baselineVersion: '0.2.0'));
        });
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.load();
        await cubit.upgrade();
      },
      expect: () => [
        isA<BaselineUpgradeReady>().having(
          (s) => s.currentVersion,
          'currentVersion',
          '0.1.0',
        ),
        isA<BaselineUpgradeReady>().having(
          (s) => s.isUpgrading,
          'isUpgrading',
          isTrue,
        ),
        isA<BaselineUpgradeReady>()
            .having((s) => s.isUpgrading, 'isUpgrading', isFalse)
            .having((s) => s.currentVersion, 'currentVersion', '0.2.0'),
      ],
      verify: (_) {
        verify(() => activeProjectProvider.acceptBaselineUpgrade()).called(1);
      },
    );

    blocTest<BaselineUpgradeCubit, BaselineUpgradeState>(
      'upgrade is a no-op when already isUpToDate',
      setUp: () {
        when(
          () => baselineRepository.getAvailableBaselineVersions(),
        ).thenAnswer((_) async => ['0.1.0']);
        when(
          () => activeProjectProvider.activeProject,
        ).thenReturn(buildProject());
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.load();
        await cubit.upgrade();
      },
      expect: () => [
        isA<BaselineUpgradeReady>().having(
          (s) => s.isUpToDate,
          'isUpToDate',
          isTrue,
        ),
      ],
      verify: (_) {
        verifyNever(() => activeProjectProvider.acceptBaselineUpgrade());
      },
    );
  });
}
