import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/projects/projects.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

void main() {
  late MockProjectRepository repository;

  final older = Project(
    id: '1',
    name: 'Older Project',
    storageKey: '1',
    baselineVersion: '0.1.0',
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );
  final newer = Project(
    id: '2',
    name: 'Newer Project',
    storageKey: '2',
    baselineVersion: '0.1.0',
    createdAt: DateTime(2026, 1, 2),
    lastOpenedAt: DateTime(2026, 1, 5),
  );

  setUp(() {
    repository = MockProjectRepository();
  });

  group('ProjectHubCubit', () {
    blocTest<ProjectHubCubit, ProjectHubState>(
      'load emits [Loading, Loaded] sorted most-recently-opened first',
      setUp: () {
        when(
          () => repository.getAllProjects(),
        ).thenAnswer((_) async => [older, newer]);
      },
      build: () => ProjectHubCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [
        const ProjectHubLoading(),
        ProjectHubLoaded([newer, older]),
      ],
    );

    blocTest<ProjectHubCubit, ProjectHubState>(
      'load emits [Loading, Empty] when no projects exist',
      setUp: () {
        when(() => repository.getAllProjects()).thenAnswer((_) async => []);
      },
      build: () => ProjectHubCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [const ProjectHubLoading(), const ProjectHubEmpty()],
    );

    blocTest<ProjectHubCubit, ProjectHubState>(
      'load emits [Loading, Error] on repository exception',
      setUp: () {
        when(() => repository.getAllProjects()).thenThrow(Exception('boom'));
      },
      build: () => ProjectHubCubit(repository),
      act: (cubit) => cubit.load(),
      expect: () => [const ProjectHubLoading(), isA<ProjectHubError>()],
    );
  });
}
