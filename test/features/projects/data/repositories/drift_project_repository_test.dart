import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/data/repositories/drift_project_repository.dart';
import 'package:aion/features/projects/domain/entities/project.dart';

/// [DriftProjectRepository] talks to [RegistryDatabase] through Drift's
/// fluent query-builder chain (`select().where()`, `into().insert()`,
/// `update().write()`, `delete().go()`) rather than a DAO with a plain
/// method surface — there is no seam a mocktail mock can intercept
/// without re-implementing Drift's builder internals. Per
/// `flutter-conventions.md`'s stated exception (see `ticket_dao_test.dart`'s
/// own rationale for the same tradeoff), this uses a real in-memory Drift
/// instance instead of a mock.
void main() {
  late RegistryDatabase database;
  late DriftProjectRepository repository;

  Project buildProject({
    String id = '1',
    String name = 'Test Project',
    DateTime? lastOpenedAt,
  }) {
    final now = DateTime(2026, 1, 1);
    return Project(
      id: id,
      name: name,
      storageKey: id,
      baselineVersion: '0.1.0',
      createdAt: now,
      lastOpenedAt: lastOpenedAt ?? now,
    );
  }

  setUp(() {
    database = RegistryDatabase(NativeDatabase.memory());
    repository = DriftProjectRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('getAllProjects returns an empty list when none exist', () async {
    expect(await repository.getAllProjects(), isEmpty);
  });

  test(
    'createProject then getAllProjects returns the created project',
    () async {
      await repository.createProject(buildProject());
      final projects = await repository.getAllProjects();

      expect(projects, hasLength(1));
      expect(projects.first.name, 'Test Project');
    },
  );

  test('getProject returns the matching project when found', () async {
    await repository.createProject(buildProject(id: 'abc'));
    final found = await repository.getProject('abc');

    expect(found, isNotNull);
    expect(found!.id, 'abc');
  });

  test('getProject returns null when not found', () async {
    expect(await repository.getProject('missing'), isNull);
  });

  test('updateLastOpened changes only the lastOpenedAt field', () async {
    await repository.createProject(
      buildProject(id: '1', lastOpenedAt: DateTime(2026, 1, 1)),
    );
    final newTimestamp = DateTime(2026, 6, 1);

    await repository.updateLastOpened('1', newTimestamp);
    final found = await repository.getProject('1');

    expect(found!.lastOpenedAt, newTimestamp);
    expect(found.name, 'Test Project');
  });

  test('removeProject deletes the registry entry', () async {
    await repository.createProject(buildProject(id: '1'));
    await repository.removeProject('1');

    expect(await repository.getProject('1'), isNull);
  });
}
