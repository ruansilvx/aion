import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/core/git/gitignore_editor.dart';
import 'package:aion/features/projects/data/services/baseline_tailoring_service.dart';
import 'package:aion/features/projects/data/services/skill_materialization_service.dart';
import 'package:aion/features/projects/projects.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockBaselineRepository extends Mock implements BaselineRepository {}

class MockBaselineTailoringService extends Mock
    implements BaselineTailoringService {}

class MockSkillMaterializationService extends Mock
    implements SkillMaterializationService {}

class MockGitRepositoryClient extends Mock implements GitRepositoryClient {}

class MockGitignoreEditor extends Mock implements GitignoreEditor {}

void main() {
  late MockProjectRepository projectRepository;
  late MockBaselineRepository baselineRepository;
  late MockBaselineTailoringService baselineTailoringService;
  late MockSkillMaterializationService skillMaterializationService;
  late MockGitRepositoryClient gitClient;
  late MockGitignoreEditor gitignoreEditor;
  late Directory tempDir;

  final existing = Project(
    id: 'existing',
    name: 'Existing Project',
    storageKey: 'existing',
    baselineVersion: '0.1.0',
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );

  setUpAll(() {
    registerFallbackValue(existing);
    registerFallbackValue(const BaselineManifest(version: '0.1.0', assets: []));
  });

  setUp(() async {
    projectRepository = MockProjectRepository();
    baselineRepository = MockBaselineRepository();
    baselineTailoringService = MockBaselineTailoringService();
    skillMaterializationService = MockSkillMaterializationService();
    gitClient = MockGitRepositoryClient();
    gitignoreEditor = MockGitignoreEditor();
    tempDir = await Directory.systemTemp.createTemp('create_project_test_');
    when(
      () => projectRepository.getAllProjects(),
    ).thenAnswer((_) async => [existing]);
    when(
      () => baselineRepository.getAvailableBaselineVersions(),
    ).thenAnswer((_) async => ['0.1.0']);
    when(
      () => baselineRepository.getManifest('0.1.0'),
    ).thenAnswer((_) async => const BaselineManifest(version: '0.1.0', assets: []));
    when(
      () => baselineTailoringService.tailorForDetectedStack(
        projectId: any(named: 'projectId'),
        rootPath: any(named: 'rootPath'),
        manifest: any(named: 'manifest'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => skillMaterializationService.materializeAll(
        projectId: any(named: 'projectId'),
        rootPath: any(named: 'rootPath'),
        manifest: any(named: 'manifest'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => gitClient.isGitRepository(any()),
    ).thenAnswer((_) async => false);
    when(() => gitClient.init(any())).thenAnswer((_) async {});
    when(() => gitClient.addRemote(any(), any())).thenAnswer((_) async {});
    when(
      () => gitignoreEditor.ensureIgnored(any(), any()),
    ).thenAnswer((_) async {});
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CreateProjectCubit', () {
    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit rejects a name that collides with an existing project '
      '(case-insensitive)',
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) =>
          cubit.submit(name: 'existing project', rootPath: tempDir.path),
      expect: () => [
        const CreateProjectValidating(),
        const CreateProjectFailure(
          '',
          reason: CreateProjectFailureReason.duplicateName,
        ),
      ],
      verify: (_) {
        verifyNever(() => projectRepository.createProject(any()));
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit rejects a directory already used by another project',
      setUp: () {
        Directory('${tempDir.path}${Platform.pathSeparator}.aion').createSync();
        File(
          '${tempDir.path}${Platform.pathSeparator}.aion${Platform.pathSeparator}manifest.json',
        ).writeAsStringSync('{}');
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) =>
          cubit.submit(name: 'A New Project', rootPath: tempDir.path),
      expect: () => [
        const CreateProjectValidating(),
        const CreateProjectFailure(
          '',
          reason: CreateProjectFailureReason.directoryAlreadyInUse,
        ),
      ],
      verify: (_) {
        verifyNever(() => projectRepository.createProject(any()));
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit with valid input reaches Success on a non-repo directory, '
      'initializing a fresh git repo and skipping the gitignore editor',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) =>
          cubit.submit(name: 'A New Project', rootPath: tempDir.path),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>().having(
          (s) => s.wasExistingGitRepo,
          'wasExistingGitRepo',
          isFalse,
        ),
      ],
      verify: (_) {
        verify(() => projectRepository.createProject(any())).called(1);
        verify(() => gitClient.init(tempDir.path)).called(1);
        verifyNever(() => gitignoreEditor.ensureIgnored(any(), any()));
        verify(
          () => baselineTailoringService.tailorForDetectedStack(
            projectId: any(named: 'projectId'),
            rootPath: tempDir.path,
            manifest: any(named: 'manifest'),
          ),
        ).called(1);
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit materializes the pinned version\'s skill assets, and does so '
      'only after the project row exists (both baseline side effects '
      "resolve the project's rootPath through ProjectRepository)",
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) =>
          cubit.submit(name: 'A New Project', rootPath: tempDir.path),
      verify: (_) {
        verifyInOrder([
          () => projectRepository.createProject(any()),
          () => baselineTailoringService.tailorForDetectedStack(
            projectId: any(named: 'projectId'),
            rootPath: tempDir.path,
            manifest: any(named: 'manifest'),
          ),
          () => skillMaterializationService.materializeAll(
            projectId: any(named: 'projectId'),
            rootPath: tempDir.path,
            manifest: any(named: 'manifest'),
          ),
        ]);
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit skips skill materialization when validation fails before the '
      'project is ever created',
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) => cubit.submit(name: '  ', rootPath: tempDir.path),
      verify: (_) {
        verifyNever(
          () => skillMaterializationService.materializeAll(
            projectId: any(named: 'projectId'),
            rootPath: any(named: 'rootPath'),
            manifest: any(named: 'manifest'),
          ),
        );
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit on an already-git-tracked directory with appendGitignore '
      'true skips git init and appends .aion//tickets/ to .gitignore',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
        when(
          () => gitClient.isGitRepository(tempDir.path),
        ).thenAnswer((_) async => true);
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) => cubit.submit(
        name: 'A New Project',
        rootPath: tempDir.path,
        appendGitignore: true,
      ),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>().having(
          (s) => s.wasExistingGitRepo,
          'wasExistingGitRepo',
          isTrue,
        ),
      ],
      verify: (_) {
        verifyNever(() => gitClient.init(any()));
        verify(
          () => gitignoreEditor.ensureIgnored(tempDir.path, [
            '.aion/',
            'tickets/',
          ]),
        ).called(1);
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit on an already-git-tracked directory with appendGitignore '
      'false skips both git init and the gitignore editor, still succeeds',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
        when(
          () => gitClient.isGitRepository(tempDir.path),
        ).thenAnswer((_) async => true);
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) => cubit.submit(
        name: 'A New Project',
        rootPath: tempDir.path,
        appendGitignore: false,
      ),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>().having(
          (s) => s.wasExistingGitRepo,
          'wasExistingGitRepo',
          isTrue,
        ),
      ],
      verify: (_) {
        verify(() => projectRepository.createProject(any())).called(1);
        verifyNever(() => gitClient.init(any()));
        verifyNever(() => gitignoreEditor.ensureIgnored(any(), any()));
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit with separateTicketsRepo defaulted (false) leaves '
      'ticketsRootPath unset, matching pre-AIO-2847 behavior',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) =>
          cubit.submit(name: 'A New Project', rootPath: tempDir.path),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>().having(
          (s) => s.project.ticketsRootPath,
          'project.ticketsRootPath',
          isNull,
        ),
      ],
      verify: (_) {
        verify(() => gitClient.init(tempDir.path)).called(1);
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit with separateTicketsRepo: true sets ticketsRootPath under '
      '.aion/tickets-repo and git-inits it',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) => cubit.submit(
        name: 'A New Project',
        rootPath: tempDir.path,
        separateTicketsRepo: true,
      ),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>().having(
          (s) => s.project.ticketsRootPath,
          'project.ticketsRootPath',
          '${tempDir.path}${Platform.pathSeparator}.aion${Platform.pathSeparator}tickets-repo',
        ),
      ],
      verify: (_) {
        final ticketsRootPath =
            '${tempDir.path}${Platform.pathSeparator}.aion${Platform.pathSeparator}tickets-repo';
        // Both the source rootPath (fresh, not already a repo) and the
        // new dedicated ticketsRootPath get their own `git init`.
        verify(() => gitClient.init(tempDir.path)).called(1);
        verify(() => gitClient.init(ticketsRootPath)).called(1);
        expect(Directory('$ticketsRootPath/tickets').existsSync(), isTrue);
        verifyNever(() => gitClient.addRemote(any(), any()));
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit with separateTicketsRepo: true on an already-git-tracked '
      'directory still git-inits only the new ticketsRootPath, not '
      'rootPath itself',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
        when(
          () => gitClient.isGitRepository(tempDir.path),
        ).thenAnswer((_) async => true);
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) => cubit.submit(
        name: 'A New Project',
        rootPath: tempDir.path,
        separateTicketsRepo: true,
      ),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>(),
      ],
      verify: (_) {
        final ticketsRootPath =
            '${tempDir.path}${Platform.pathSeparator}.aion${Platform.pathSeparator}tickets-repo';
        verifyNever(() => gitClient.init(tempDir.path));
        verify(() => gitClient.init(ticketsRootPath)).called(1);
        expect(Directory('$ticketsRootPath/tickets').existsSync(), isTrue);
        // The default rootPath/tickets/ directory is not created at all
        // once a separate ticketsRootPath is in play.
        expect(Directory('${tempDir.path}/tickets').existsSync(), isFalse);
        verifyNever(() => gitClient.addRemote(any(), any()));
        // appendGitignore defaults to true and this directory is already
        // a git repo, so ensureIgnored does fire -- but narrowed to
        // .aion/ only, since tickets/ is never created here once a
        // separate ticketsRootPath is in play (AIO-2857).
        verify(
          () => gitignoreEditor.ensureIgnored(tempDir.path, ['.aion/']),
        ).called(1);
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit with separateTicketsRepo: false on an already-git-tracked '
      'directory still appends both .aion/ and tickets/ to .gitignore '
      '(unchanged pre-AIO-2857 behavior)',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
        when(
          () => gitClient.isGitRepository(tempDir.path),
        ).thenAnswer((_) async => true);
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) =>
          cubit.submit(name: 'A New Project', rootPath: tempDir.path),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>(),
      ],
      verify: (_) {
        verify(
          () => gitignoreEditor.ensureIgnored(tempDir.path, [
            '.aion/',
            'tickets/',
          ]),
        ).called(1);
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit with separateTicketsRepo: true and a ticketsRepoRemoteUrl '
      'configures that url as the new tickets repo\'s origin remote',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) => cubit.submit(
        name: 'A New Project',
        rootPath: tempDir.path,
        separateTicketsRepo: true,
        ticketsRepoRemoteUrl: 'https://example.com/my-tickets.git',
      ),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>(),
      ],
      verify: (_) {
        final ticketsRootPath =
            '${tempDir.path}${Platform.pathSeparator}.aion${Platform.pathSeparator}tickets-repo';
        verify(() => gitClient.init(ticketsRootPath)).called(1);
        verify(
          () => gitClient.addRemote(
            ticketsRootPath,
            'https://example.com/my-tickets.git',
          ),
        ).called(1);
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit with separateTicketsRepo: true and an empty '
      'ticketsRepoRemoteUrl behaves as if none was given — local-only, '
      'no remote configured',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) => cubit.submit(
        name: 'A New Project',
        rootPath: tempDir.path,
        separateTicketsRepo: true,
        ticketsRepoRemoteUrl: '',
      ),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>(),
      ],
      verify: (_) {
        verifyNever(() => gitClient.addRemote(any(), any()));
      },
    );

    blocTest<CreateProjectCubit, CreateProjectState>(
      'submit surfaces a repository failure with a raw message, distinct '
      'from a classified validation failure',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenThrow(Exception('disk write error'));
      },
      build: () => CreateProjectCubit(
        projectRepository,
        baselineRepository,
        baselineTailoringService,
        skillMaterializationService,
        gitClient,
        gitignoreEditor,
      ),
      act: (cubit) =>
          cubit.submit(name: 'A New Project', rootPath: tempDir.path),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectFailure>()
            .having((f) => f.reason, 'reason', isNull)
            .having((f) => f.message, 'message', isNotEmpty),
      ],
    );
  });
}
