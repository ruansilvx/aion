import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/projects/projects.dart';

class MockBaselineRepository extends Mock implements BaselineRepository {}

void main() {
  late MockBaselineRepository baselineRepository;

  const manifest = BaselineManifest(
    version: '0.3.0',
    assets: [
      BaselineAsset(
        key: 'skills/verify',
        kind: BaselineAssetKind.skill,
        bundledPath: 'assets/baseline/0.3.0/skills/verify.md',
      ),
      BaselineAsset(
        key: 'conventions/architecture-conventions',
        kind: BaselineAssetKind.architectureConvention,
        bundledPath: 'assets/baseline/0.3.0/architecture_convention.md',
      ),
    ],
  );

  setUp(() {
    baselineRepository = MockBaselineRepository();
  });

  group('OverridesCubit', () {
    blocTest<OverridesCubit, OverridesState>(
      'load emits [OverridesLoading, OverridesReady] with the manifest '
      'and overrides',
      setUp: () {
        when(
          () => baselineRepository.getManifest('0.3.0'),
        ).thenAnswer((_) async => manifest);
        when(() => baselineRepository.readOverrides('project-1')).thenAnswer(
          (_) async => const [
            ProjectOverride(
              projectId: 'project-1',
              assetKey: 'skills/verify',
              overridePath: '/root/.aion/overrides/verify.md',
            ),
          ],
        );
      },
      build: () => OverridesCubit(baselineRepository, 'project-1', '0.3.0'),
      act: (cubit) => cubit.load(),
      expect: () => [
        const OverridesLoading(),
        OverridesReady(
          manifest: manifest,
          overrides: const [
            ProjectOverride(
              projectId: 'project-1',
              assetKey: 'skills/verify',
              overridePath: '/root/.aion/overrides/verify.md',
            ),
          ],
        ),
      ],
    );

    blocTest<OverridesCubit, OverridesState>(
      'load emits OverridesError when the repository throws',
      setUp: () {
        when(
          () => baselineRepository.getManifest('0.3.0'),
        ).thenThrow(Exception('boom'));
      },
      build: () => OverridesCubit(baselineRepository, 'project-1', '0.3.0'),
      act: (cubit) => cubit.load(),
      expect: () => [
        const OverridesLoading(),
        isA<OverridesError>(),
      ],
    );
  });
}
