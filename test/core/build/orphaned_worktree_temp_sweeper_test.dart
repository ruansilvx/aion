// test/core/build/orphaned_worktree_temp_sweeper_test.dart — sweepOrphanedWorktreeTempDirs tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aion/core/build/orphaned_worktree_temp_sweeper.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sweeper_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Directory> makeDir(String name) =>
      Directory(p.join(tempDir.path, name)).create();

  test(
    'removes a matching-prefix directory once it is older than minAge',
    () async {
      final stale = await makeDir('aion_exec_stale');

      // minAge: zero — every freshly-created entry is, by construction,
      // already at or past `now`, so this simulates "created well in the
      // past" without needing to fake the directory's own mtime (dart:io
      // has no `Directory.setLastModified`, unlike `File`).
      await sweepOrphanedWorktreeTempDirs(
        tempDir: tempDir,
        minAge: Duration.zero,
      );

      expect(stale.existsSync(), isFalse);
    },
  );

  test(
    'leaves a matching-prefix directory younger than minAge untouched — a '
    'run still legitimately in flight is never this old',
    () async {
      final fresh = await makeDir('aion_exec_fresh');

      await sweepOrphanedWorktreeTempDirs(
        tempDir: tempDir,
        minAge: const Duration(hours: 24),
      );

      expect(fresh.existsSync(), isTrue);
    },
  );

  test(
    'leaves a directory with an unrelated name untouched even past minAge — '
    'only the three known prefixes are ever swept',
    () async {
      final unrelated = await makeDir('some_other_apps_temp_dir');

      await sweepOrphanedWorktreeTempDirs(
        tempDir: tempDir,
        minAge: Duration.zero,
      );

      expect(unrelated.existsSync(), isTrue);
    },
  );

  test(
    'sweeps all three known prefixes — aion_exec_/aion_skill_/aion_analysis_',
    () async {
      final exec = await makeDir('aion_exec_a');
      final skill = await makeDir('aion_skill_b');
      final analysis = await makeDir('aion_analysis_c');

      await sweepOrphanedWorktreeTempDirs(
        tempDir: tempDir,
        minAge: Duration.zero,
      );

      expect(exec.existsSync(), isFalse);
      expect(skill.existsSync(), isFalse);
      expect(analysis.existsSync(), isFalse);
    },
  );

  test('removes a stale directory even when it still has content', () async {
    final stale = await makeDir('aion_exec_populated');
    File(p.join(stale.path, 'leftover.txt')).writeAsStringSync('data');

    await sweepOrphanedWorktreeTempDirs(
      tempDir: tempDir,
      minAge: Duration.zero,
    );

    expect(stale.existsSync(), isFalse);
  });

  test('is a safe no-op against an empty temp directory', () async {
    await sweepOrphanedWorktreeTempDirs(
      tempDir: tempDir,
      minAge: const Duration(hours: 24),
    );

    expect(tempDir.listSync(), isEmpty);
  });
}
