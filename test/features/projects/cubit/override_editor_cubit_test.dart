import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/projects/data/services/skill_materialization_service.dart';
import 'package:aion/features/projects/projects.dart';

class MockBaselineRepository extends Mock implements BaselineRepository {}

class MockSkillMaterializationService extends Mock
    implements SkillMaterializationService {}

void main() {
  late MockBaselineRepository baselineRepository;
  late MockSkillMaterializationService skillMaterializationService;

  const manifest = BaselineManifest(
    version: '0.3.0',
    assets: [
      BaselineAsset(
        key: 'skills/verify',
        kind: BaselineAssetKind.skill,
        bundledPath: 'assets/baseline/0.3.0/skills/verify.md',
      ),
    ],
  );
  const asset = BaselineAsset(
    key: 'skills/verify',
    kind: BaselineAssetKind.skill,
    bundledPath: 'assets/baseline/0.3.0/skills/verify.md',
  );

  setUp(() {
    baselineRepository = MockBaselineRepository();
    skillMaterializationService = MockSkillMaterializationService();
    registerFallbackValue(asset);
  });

  group('OverrideEditorCubit', () {
    blocTest<OverrideEditorCubit, OverrideEditorState>(
      'load emits [Loading, Ready(isOverridden: false)] with the bundled '
      'default when no override exists',
      setUp: () {
        when(
          () => baselineRepository.getManifest('0.3.0'),
        ).thenAnswer((_) async => manifest);
        when(
          () => baselineRepository.readOverrides('project-1'),
        ).thenAnswer((_) async => const []);
        when(
          () => baselineRepository.readBundledContent(asset),
        ).thenAnswer((_) async => 'default content');
      },
      build: () => OverrideEditorCubit(
        baselineRepository,
        skillMaterializationService,
        'project-1',
        '0.3.0',
        null,
        'skills/verify',
      ),
      act: (cubit) => cubit.load(),
      expect: () => [
        const OverrideEditorLoading(),
        const OverrideEditorReady(
          content: 'default content',
          isOverridden: false,
        ),
      ],
    );

    blocTest<OverrideEditorCubit, OverrideEditorState>(
      'load emits [Loading, Ready(isOverridden: true)] with the local '
      "override's content when one exists",
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
        when(
          () => baselineRepository.readOverrideContent(
            '/root/.aion/overrides/verify.md',
          ),
        ).thenAnswer((_) async => 'my custom override');
      },
      build: () => OverrideEditorCubit(
        baselineRepository,
        skillMaterializationService,
        'project-1',
        '0.3.0',
        null,
        'skills/verify',
      ),
      act: (cubit) => cubit.load(),
      expect: () => [
        const OverrideEditorLoading(),
        const OverrideEditorReady(
          content: 'my custom override',
          isOverridden: true,
        ),
      ],
    );

    blocTest<OverrideEditorCubit, OverrideEditorState>(
      'load emits OverrideEditorError for an asset key not in the manifest',
      setUp: () {
        when(
          () => baselineRepository.getManifest('0.3.0'),
        ).thenAnswer((_) async => manifest);
      },
      build: () => OverrideEditorCubit(
        baselineRepository,
        skillMaterializationService,
        'project-1',
        '0.3.0',
        null,
        'skills/unknown',
      ),
      act: (cubit) => cubit.load(),
      expect: () => [
        const OverrideEditorLoading(),
        isA<OverrideEditorError>(),
      ],
    );

    blocTest<OverrideEditorCubit, OverrideEditorState>(
      'save emits [Saving, Saved] and writes the override via the '
      "asset resolved by load's manifest lookup",
      setUp: () {
        when(
          () => baselineRepository.getManifest('0.3.0'),
        ).thenAnswer((_) async => manifest);
        when(
          () => baselineRepository.readOverrides('project-1'),
        ).thenAnswer((_) async => const []);
        when(
          () => baselineRepository.readBundledContent(asset),
        ).thenAnswer((_) async => 'default content');
        when(
          () => baselineRepository.writeOverride(
            projectId: 'project-1',
            asset: asset,
            content: 'edited content',
          ),
        ).thenAnswer((_) async {});
      },
      build: () => OverrideEditorCubit(
        baselineRepository,
        skillMaterializationService,
        'project-1',
        '0.3.0',
        null,
        'skills/verify',
      ),
      act: (cubit) async {
        await cubit.load();
        await cubit.save('edited content');
      },
      expect: () => [
        const OverrideEditorLoading(),
        const OverrideEditorReady(
          content: 'default content',
          isOverridden: false,
        ),
        const OverrideEditorSaving('edited content'),
        const OverrideEditorSaved(),
      ],
      verify: (_) {
        verify(
          () => baselineRepository.writeOverride(
            projectId: 'project-1',
            asset: asset,
            content: 'edited content',
          ),
        ).called(1);
      },
    );

    blocTest<OverrideEditorCubit, OverrideEditorState>(
      'save re-materializes the discoverable skill file from the just-saved '
      'content when the project has a rootPath',
      setUp: () {
        when(
          () => baselineRepository.getManifest('0.3.0'),
        ).thenAnswer((_) async => manifest);
        when(
          () => baselineRepository.readOverrides('project-1'),
        ).thenAnswer((_) async => const []);
        when(
          () => baselineRepository.readBundledContent(asset),
        ).thenAnswer((_) async => 'default content');
        when(
          () => baselineRepository.writeOverride(
            projectId: any(named: 'projectId'),
            asset: any(named: 'asset'),
            content: any(named: 'content'),
          ),
        ).thenAnswer((_) async {});
      },
      build: () => OverrideEditorCubit(
        baselineRepository,
        skillMaterializationService,
        'project-1',
        '0.3.0',
        '/root',
        'skills/verify',
      ),
      act: (cubit) async {
        await cubit.load();
        await cubit.save('edited content');
      },
      expect: () => [
        const OverrideEditorLoading(),
        const OverrideEditorReady(
          content: 'default content',
          isOverridden: false,
        ),
        const OverrideEditorSaving('edited content'),
        const OverrideEditorSaved(),
      ],
      verify: (_) {
        verify(
          () => skillMaterializationService.materializeSkill(
            rootPath: '/root',
            asset: asset,
            content: 'edited content',
          ),
        ).called(1);
      },
    );

    blocTest<OverrideEditorCubit, OverrideEditorState>(
      'save skips skill materialization entirely when the project has no '
      'rootPath (mobile/web)',
      setUp: () {
        when(
          () => baselineRepository.getManifest('0.3.0'),
        ).thenAnswer((_) async => manifest);
        when(
          () => baselineRepository.readOverrides('project-1'),
        ).thenAnswer((_) async => const []);
        when(
          () => baselineRepository.readBundledContent(asset),
        ).thenAnswer((_) async => 'default content');
        when(
          () => baselineRepository.writeOverride(
            projectId: any(named: 'projectId'),
            asset: any(named: 'asset'),
            content: any(named: 'content'),
          ),
        ).thenAnswer((_) async {});
      },
      build: () => OverrideEditorCubit(
        baselineRepository,
        skillMaterializationService,
        'project-1',
        '0.3.0',
        null,
        'skills/verify',
      ),
      act: (cubit) async {
        await cubit.load();
        await cubit.save('edited content');
      },
      verify: (_) {
        verifyNever(
          () => skillMaterializationService.materializeSkill(
            rootPath: any(named: 'rootPath'),
            asset: any(named: 'asset'),
            content: any(named: 'content'),
          ),
        );
      },
    );
  });
}
