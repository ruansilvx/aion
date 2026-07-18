import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/projects/projects.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockBaselineRepository extends Mock implements BaselineRepository {}

void main() {
  late MockProjectRepository projectRepository;
  late MockBaselineRepository baselineRepository;
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
  });

  setUp(() async {
    projectRepository = MockProjectRepository();
    baselineRepository = MockBaselineRepository();
    tempDir = await Directory.systemTemp.createTemp('create_project_test_');
    when(
      () => projectRepository.getAllProjects(),
    ).thenAnswer((_) async => [existing]);
    when(
      () => baselineRepository.getAvailableBaselineVersions(),
    ).thenAnswer((_) async => ['0.1.0']);
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
      build: () => CreateProjectCubit(projectRepository, baselineRepository),
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
      build: () => CreateProjectCubit(projectRepository, baselineRepository),
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
      'submit with valid input reaches Success',
      setUp: () {
        when(
          () => projectRepository.createProject(any()),
        ).thenAnswer((_) async {});
      },
      build: () => CreateProjectCubit(projectRepository, baselineRepository),
      act: (cubit) =>
          cubit.submit(name: 'A New Project', rootPath: tempDir.path),
      expect: () => [
        const CreateProjectValidating(),
        isA<CreateProjectReady>(),
        const CreateProjectSubmitting(),
        isA<CreateProjectSuccess>(),
      ],
      verify: (_) {
        verify(() => projectRepository.createProject(any())).called(1);
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
      build: () => CreateProjectCubit(projectRepository, baselineRepository),
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
