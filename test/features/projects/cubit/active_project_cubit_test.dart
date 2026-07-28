import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/projects/data/services/baseline_tailoring_service.dart';
import 'package:aion/features/projects/projects.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockBaselineRepository extends Mock implements BaselineRepository {}

class MockBaselineTailoringService extends Mock
    implements BaselineTailoringService {}

void main() {
  late MockProjectRepository repository;
  late MockBaselineRepository baselineRepository;
  late MockBaselineTailoringService baselineTailoringService;

  final project = Project(
    id: '1',
    name: 'Test Project',
    storageKey: '1',
    baselineVersion: '0.1.0',
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );

  final desktopProject = Project(
    id: '1',
    name: 'Test Project',
    storageKey: '1',
    rootPath: '/tmp/test-project',
    baselineVersion: '0.1.0',
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );

  const oldManifest = BaselineManifest(version: '0.1.0', assets: []);
  const newManifest = BaselineManifest(version: '0.2.0', assets: []);

  ActiveProjectCubit buildCubit() =>
      ActiveProjectCubit(repository, baselineRepository, baselineTailoringService);

  setUpAll(() {
    registerFallbackValue(oldManifest);
  });

  setUp(() {
    repository = MockProjectRepository();
    baselineRepository = MockBaselineRepository();
    baselineTailoringService = MockBaselineTailoringService();
    when(
      () => repository.updateLastOpened(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => repository.updateBaselineVersion(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => baselineRepository.getAvailableBaselineVersions(),
    ).thenAnswer((_) async => ['0.1.0']);
    when(
      () => baselineRepository.getManifest(any()),
    ).thenAnswer((_) async => oldManifest);
    when(
      () => baselineTailoringService.tailorNewlyIntroducedAssets(
        projectId: any(named: 'projectId'),
        rootPath: any(named: 'rootPath'),
        oldManifest: any(named: 'oldManifest'),
        newManifest: any(named: 'newManifest'),
      ),
    ).thenAnswer((_) async {});
  });

  group('ActiveProjectCubit', () {
    test('starts at ActiveProjectNone', () {
      final cubit = buildCubit();
      expect(cubit.state, const ActiveProjectNone());
      expect(cubit.activeProject, isNull);
    });

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'switchTo emits [Switching, Open] and persists lastOpenedAt',
      build: buildCubit,
      act: (cubit) => cubit.switchTo(project),
      expect: () => [
        ActiveProjectSwitching(from: null, to: project),
        isA<ActiveProjectOpen>().having(
          (s) => s.project.id,
          'project.id',
          project.id,
        ),
      ],
      verify: (_) {
        verify(() => repository.updateLastOpened(project.id, any())).called(1);
      },
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'switching to a second project carries the first as `from`',
      build: buildCubit,
      act: (cubit) async {
        await cubit.switchTo(project);
        final other = Project(
          id: '2',
          name: 'Other Project',
          storageKey: '2',
          baselineVersion: '0.1.0',
          createdAt: DateTime(2026, 1, 1),
          lastOpenedAt: DateTime(2026, 1, 1),
        );
        await cubit.switchTo(other);
      },
      expect: () => [
        ActiveProjectSwitching(from: null, to: project),
        isA<ActiveProjectOpen>(),
        isA<ActiveProjectSwitching>().having(
          (s) => s.from?.id,
          'from.id',
          project.id,
        ),
        isA<ActiveProjectOpen>().having((s) => s.project.id, 'project.id', '2'),
      ],
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'switchTo with offerCodebaseAnalysis true carries it on ActiveProjectOpen',
      build: buildCubit,
      act: (cubit) => cubit.switchTo(project, offerCodebaseAnalysis: true),
      expect: () => [
        isA<ActiveProjectSwitching>(),
        isA<ActiveProjectOpen>().having(
          (s) => s.offerCodebaseAnalysis,
          'offerCodebaseAnalysis',
          isTrue,
        ),
      ],
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'consumeCodebaseAnalysisOffer clears a true flag back to false',
      build: buildCubit,
      act: (cubit) async {
        await cubit.switchTo(project, offerCodebaseAnalysis: true);
        cubit.consumeCodebaseAnalysisOffer();
      },
      expect: () => [
        isA<ActiveProjectSwitching>(),
        isA<ActiveProjectOpen>().having(
          (s) => s.offerCodebaseAnalysis,
          'offerCodebaseAnalysis',
          isTrue,
        ),
        isA<ActiveProjectOpen>().having(
          (s) => s.offerCodebaseAnalysis,
          'offerCodebaseAnalysis',
          isFalse,
        ),
      ],
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'consumeCodebaseAnalysisOffer no-ops when the flag is already false',
      build: buildCubit,
      act: (cubit) async {
        await cubit.switchTo(project);
        cubit.consumeCodebaseAnalysisOffer();
      },
      expect: () => [
        isA<ActiveProjectSwitching>(),
        isA<ActiveProjectOpen>().having(
          (s) => s.offerCodebaseAnalysis,
          'offerCodebaseAnalysis',
          isFalse,
        ),
      ],
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'consumeCodebaseAnalysisOffer no-ops when not in ActiveProjectOpen',
      build: buildCubit,
      act: (cubit) => cubit.consumeCodebaseAnalysisOffer(),
      expect: () => <ActiveProjectState>[],
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'switchTo emits offerBaselineUpgrade: true when the pinned version '
      "isn't the latest bundled one",
      setUp: () {
        when(
          () => baselineRepository.getAvailableBaselineVersions(),
        ).thenAnswer((_) async => ['0.1.0', '0.2.0']);
      },
      build: buildCubit,
      act: (cubit) => cubit.switchTo(project),
      expect: () => [
        isA<ActiveProjectSwitching>(),
        isA<ActiveProjectOpen>().having(
          (s) => s.offerBaselineUpgrade,
          'offerBaselineUpgrade',
          isTrue,
        ),
      ],
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'switchTo emits offerBaselineUpgrade: false when already on the '
      'latest version',
      build: buildCubit,
      act: (cubit) => cubit.switchTo(project),
      expect: () => [
        isA<ActiveProjectSwitching>(),
        isA<ActiveProjectOpen>().having(
          (s) => s.offerBaselineUpgrade,
          'offerBaselineUpgrade',
          isFalse,
        ),
      ],
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'consumeBaselineUpgradeOffer clears only that flag, leaving '
      'offerCodebaseAnalysis as it was',
      setUp: () {
        when(
          () => baselineRepository.getAvailableBaselineVersions(),
        ).thenAnswer((_) async => ['0.1.0', '0.2.0']);
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.switchTo(project, offerCodebaseAnalysis: true);
        cubit.consumeBaselineUpgradeOffer();
      },
      expect: () => [
        isA<ActiveProjectSwitching>(),
        isA<ActiveProjectOpen>()
            .having((s) => s.offerBaselineUpgrade, 'offerBaselineUpgrade', isTrue)
            .having(
              (s) => s.offerCodebaseAnalysis,
              'offerCodebaseAnalysis',
              isTrue,
            ),
        isA<ActiveProjectOpen>()
            .having(
              (s) => s.offerBaselineUpgrade,
              'offerBaselineUpgrade',
              isFalse,
            )
            .having(
              (s) => s.offerCodebaseAnalysis,
              'offerCodebaseAnalysis',
              isTrue,
            ),
      ],
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'acceptBaselineUpgrade updates the registry, writes the manifest, '
      'and tailors newly-introduced assets when rootPath is set',
      setUp: () {
        when(
          () => baselineRepository.getAvailableBaselineVersions(),
        ).thenAnswer((_) async => ['0.1.0', '0.2.0']);
        when(
          () => baselineRepository.getManifest('0.1.0'),
        ).thenAnswer((_) async => oldManifest);
        when(
          () => baselineRepository.getManifest('0.2.0'),
        ).thenAnswer((_) async => newManifest);
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.switchTo(desktopProject);
        await cubit.acceptBaselineUpgrade();
      },
      verify: (_) {
        verify(
          () => repository.updateBaselineVersion(desktopProject.id, '0.2.0'),
        ).called(1);
        verify(
          () => baselineTailoringService.tailorNewlyIntroducedAssets(
            projectId: desktopProject.id,
            rootPath: desktopProject.rootPath!,
            oldManifest: oldManifest,
            newManifest: newManifest,
          ),
        ).called(1);
      },
      expect: () => [
        isA<ActiveProjectSwitching>(),
        isA<ActiveProjectOpen>().having(
          (s) => s.project.baselineVersion,
          'project.baselineVersion',
          '0.1.0',
        ),
        isA<ActiveProjectOpen>()
            .having(
              (s) => s.project.baselineVersion,
              'project.baselineVersion',
              '0.2.0',
            )
            .having(
              (s) => s.offerBaselineUpgrade,
              'offerBaselineUpgrade',
              isFalse,
            ),
      ],
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'acceptBaselineUpgrade skips the manifest write and tailoring when '
      'rootPath is null',
      setUp: () {
        when(
          () => baselineRepository.getAvailableBaselineVersions(),
        ).thenAnswer((_) async => ['0.1.0', '0.2.0']);
        when(
          () => baselineRepository.getManifest('0.2.0'),
        ).thenAnswer((_) async => newManifest);
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.switchTo(project);
        await cubit.acceptBaselineUpgrade();
      },
      verify: (_) {
        verify(
          () => repository.updateBaselineVersion(project.id, '0.2.0'),
        ).called(1);
        verifyNever(
          () => baselineTailoringService.tailorNewlyIntroducedAssets(
            projectId: any(named: 'projectId'),
            rootPath: any(named: 'rootPath'),
            oldManifest: any(named: 'oldManifest'),
            newManifest: any(named: 'newManifest'),
          ),
        );
      },
    );

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'acceptBaselineUpgrade no-ops when already on the latest version',
      build: buildCubit,
      act: (cubit) async {
        await cubit.switchTo(project);
        await cubit.acceptBaselineUpgrade();
      },
      verify: (_) {
        verifyNever(() => repository.updateBaselineVersion(any(), any()));
      },
      expect: () => [
        isA<ActiveProjectSwitching>(),
        isA<ActiveProjectOpen>(),
      ],
    );
  });
}
