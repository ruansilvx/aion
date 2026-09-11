// test/features/projects/domain/entities/project_test.dart — Project entity equality tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/projects/domain/entities/project.dart';

void main() {
  Project buildProject({
    String? rootPath = '/project/root',
    String? ticketsRootPath,
  }) {
    final now = DateTime(2026, 1, 1);
    return Project(
      id: '1',
      name: 'Test Project',
      storageKey: '1',
      rootPath: rootPath,
      ticketsRootPath: ticketsRootPath,
      baselineVersion: '0.1.0',
      createdAt: now,
      lastOpenedAt: now,
    );
  }

  test('ticketsRootPath defaults to null when omitted', () {
    final project = buildProject();
    expect(project.ticketsRootPath, isNull);
  });

  test('two projects with the same ticketsRootPath are equal', () {
    final a = buildProject(ticketsRootPath: '/tickets/repo');
    final b = buildProject(ticketsRootPath: '/tickets/repo');

    expect(a, equals(b));
  });

  test(
    'two otherwise-identical projects with different ticketsRootPath are not equal',
    () {
      final a = buildProject(ticketsRootPath: '/tickets/repo');
      final b = buildProject();

      expect(a, isNot(equals(b)));
    },
  );

  group('ticketsGitRootPath', () {
    test('is null when both rootPath and ticketsRootPath are unset', () {
      final project = buildProject(rootPath: null);
      expect(project.ticketsGitRootPath, isNull);
    });

    test('falls back to rootPath when ticketsRootPath is unset', () {
      final project = buildProject();
      expect(project.ticketsGitRootPath, '/project/root');
    });

    test('prefers ticketsRootPath when both are set', () {
      final project = buildProject(ticketsRootPath: '/tickets/repo');
      expect(project.ticketsGitRootPath, '/tickets/repo');
    });
  });
}
