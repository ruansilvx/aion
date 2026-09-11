// test/features/projects/data/models/project_model_test.dart — ProjectModel round-trip tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/data/models/project_model.dart';
import 'package:aion/features/projects/domain/entities/project.dart';

void main() {
  final createdAt = DateTime(2026, 1, 1);
  final lastOpenedAt = DateTime(2026, 2, 1);

  test('fromRow carries ticketsRootPath through from a registry row', () {
    final row = ProjectRegistryData(
      id: '1',
      name: 'Test Project',
      storageKey: '1',
      rootPath: '/project/root',
      ticketsRootPath: '/tickets/repo',
      baselineVersion: '0.1.0',
      createdAt: createdAt.millisecondsSinceEpoch,
      lastOpenedAt: lastOpenedAt.millisecondsSinceEpoch,
    );

    final model = ProjectModel.fromRow(row);

    expect(model.ticketsRootPath, '/tickets/repo');
  });

  test('fromRow leaves ticketsRootPath null when the row has none', () {
    final row = ProjectRegistryData(
      id: '1',
      name: 'Test Project',
      storageKey: '1',
      baselineVersion: '0.1.0',
      createdAt: createdAt.millisecondsSinceEpoch,
      lastOpenedAt: lastOpenedAt.millisecondsSinceEpoch,
    );

    expect(ProjectModel.fromRow(row).ticketsRootPath, isNull);
  });

  test('fromEntity carries ticketsRootPath through from a Project', () {
    final project = Project(
      id: '1',
      name: 'Test Project',
      storageKey: '1',
      ticketsRootPath: '/tickets/repo',
      baselineVersion: '0.1.0',
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt,
    );

    expect(ProjectModel.fromEntity(project).ticketsRootPath, '/tickets/repo');
  });

  test('toEntity carries ticketsRootPath back through to a Project', () {
    const model = ProjectModel(
      id: '1',
      name: 'Test Project',
      storageKey: '1',
      ticketsRootPath: '/tickets/repo',
      baselineVersion: '0.1.0',
      createdAtMillis: 0,
      lastOpenedAtMillis: 0,
    );

    expect(model.toEntity().ticketsRootPath, '/tickets/repo');
  });

  test('toCompanion wraps ticketsRootPath in a Value', () {
    const model = ProjectModel(
      id: '1',
      name: 'Test Project',
      storageKey: '1',
      ticketsRootPath: '/tickets/repo',
      baselineVersion: '0.1.0',
      createdAtMillis: 0,
      lastOpenedAtMillis: 0,
    );

    final companion = model.toCompanion();

    expect(companion.ticketsRootPath.value, '/tickets/repo');
  });

  test(
    'a full fromEntity -> toCompanion -> fromRow -> toEntity round trip preserves ticketsRootPath',
    () {
      final project = Project(
        id: '1',
        name: 'Test Project',
        storageKey: '1',
        ticketsRootPath: '/tickets/repo',
        baselineVersion: '0.1.0',
        createdAt: createdAt,
        lastOpenedAt: lastOpenedAt,
      );

      final companion = ProjectModel.fromEntity(project).toCompanion();
      final row = ProjectRegistryData(
        id: companion.id.value,
        name: companion.name.value,
        storageKey: companion.storageKey.value,
        rootPath: companion.rootPath.value,
        ticketsRootPath: companion.ticketsRootPath.value,
        baselineVersion: companion.baselineVersion.value,
        createdAt: companion.createdAt.value,
        lastOpenedAt: companion.lastOpenedAt.value,
      );

      final roundTripped = ProjectModel.fromRow(row).toEntity();

      expect(roundTripped.ticketsRootPath, '/tickets/repo');
    },
  );
}
