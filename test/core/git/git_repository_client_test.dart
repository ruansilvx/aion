import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/git/git_repository_client.dart';

void main() {
  late Directory tempDir;
  late GitRepositoryClient client;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('git_client_test_');
    client = GitRepositoryClient();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('isGitRepository', () {
    test('returns false for a directory with no .git entry', () async {
      final result = await client.isGitRepository(tempDir.path);
      expect(result, isFalse);
    });

    test('returns true when .git is a directory', () async {
      Directory(
        '${tempDir.path}${Platform.pathSeparator}.git',
      ).createSync();
      final result = await client.isGitRepository(tempDir.path);
      expect(result, isTrue);
    });

    test('returns true when .git is a file (linked worktree/submodule)', () async {
      File(
        '${tempDir.path}${Platform.pathSeparator}.git',
      ).writeAsStringSync('gitdir: ../.git/worktrees/example\n');
      final result = await client.isGitRepository(tempDir.path);
      expect(result, isTrue);
    });
  });
}
