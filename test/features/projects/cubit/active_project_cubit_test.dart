import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/projects/projects.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

void main() {
  late MockProjectRepository repository;

  final project = Project(
    id: '1',
    name: 'Test Project',
    storageKey: '1',
    baselineVersion: '0.1.0',
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    repository = MockProjectRepository();
    when(
      () => repository.updateLastOpened(any(), any()),
    ).thenAnswer((_) async {});
  });

  group('ActiveProjectCubit', () {
    test('starts at ActiveProjectNone', () {
      final cubit = ActiveProjectCubit(repository);
      expect(cubit.state, const ActiveProjectNone());
      expect(cubit.activeProject, isNull);
    });

    blocTest<ActiveProjectCubit, ActiveProjectState>(
      'switchTo emits [Switching, Open] and persists lastOpenedAt',
      build: () => ActiveProjectCubit(repository),
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
      build: () => ActiveProjectCubit(repository),
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
  });
}
