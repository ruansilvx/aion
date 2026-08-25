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

  /// Runs `git` with [args] in [tempDir], throwing on a non-zero exit —
  /// used to build a real repo fixture for `changedFileCount`/
  /// `defaultBranch` below (both shell out to `git` themselves, so a real
  /// repo is the only faithful way to exercise them). Added for
  /// `aion-arch/changes/pr-metadata-and-notification-center`.
  Future<void> runGit(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: tempDir.path);
    if (result.exitCode != 0) {
      fail('git ${args.join(' ')} failed: ${result.stderr}');
    }
  }

  group('changedFileCount', () {
    test('counts files changed on branch relative to base', () async {
      await runGit(['init', '-b', 'main']);
      await runGit(['config', 'user.email', 'test@example.com']);
      await runGit(['config', 'user.name', 'Test']);
      File(
        '${tempDir.path}${Platform.pathSeparator}a.txt',
      ).writeAsStringSync('a');
      await runGit(['add', 'a.txt']);
      await runGit(['commit', '-m', 'base']);
      await runGit(['checkout', '-b', 'feature']);
      File(
        '${tempDir.path}${Platform.pathSeparator}b.txt',
      ).writeAsStringSync('b');
      File(
        '${tempDir.path}${Platform.pathSeparator}c.txt',
      ).writeAsStringSync('c');
      await runGit(['add', 'b.txt', 'c.txt']);
      await runGit(['commit', '-m', 'feature work']);

      final count = await client.changedFileCount(
        tempDir.path,
        'main',
        'feature',
      );
      expect(count, 2);
    });

    test('returns 0 when nothing changed', () async {
      await runGit(['init', '-b', 'main']);
      await runGit(['config', 'user.email', 'test@example.com']);
      await runGit(['config', 'user.name', 'Test']);
      File(
        '${tempDir.path}${Platform.pathSeparator}a.txt',
      ).writeAsStringSync('a');
      await runGit(['add', 'a.txt']);
      await runGit(['commit', '-m', 'base']);
      await runGit(['checkout', '-b', 'feature']);

      final count = await client.changedFileCount(
        tempDir.path,
        'main',
        'feature',
      );
      expect(count, 0);
    });
  });

  group('defaultBranch', () {
    test('falls back to main when origin/HEAD is not set', () async {
      await runGit(['init', '-b', 'main']);
      final branch = await client.defaultBranch(tempDir.path);
      expect(branch, 'main');
    });

    test('resolves the branch origin/HEAD points at', () async {
      final bareDir = await Directory.systemTemp.createTemp('git_bare_');
      addTearDown(() async {
        if (bareDir.existsSync()) await bareDir.delete(recursive: true);
      });
      await Process.run('git', [
        'init',
        '--bare',
        '-b',
        'trunk',
      ], workingDirectory: bareDir.path);

      await runGit(['init', '-b', 'trunk']);
      await runGit(['config', 'user.email', 'test@example.com']);
      await runGit(['config', 'user.name', 'Test']);
      File(
        '${tempDir.path}${Platform.pathSeparator}a.txt',
      ).writeAsStringSync('a');
      await runGit(['add', 'a.txt']);
      await runGit(['commit', '-m', 'base']);
      await runGit(['remote', 'add', 'origin', bareDir.path]);
      await runGit(['push', 'origin', 'trunk']);
      await runGit(['remote', 'set-head', 'origin', 'trunk']);

      final branch = await client.defaultBranch(tempDir.path);
      expect(branch, 'trunk');
    });
  });

  group('createWorktree / removeWorktree / deleteBranch', () {
    Future<String> initRepoWithCommit() async {
      await runGit(['init', '-b', 'main']);
      await runGit(['config', 'user.email', 'test@example.com']);
      await runGit(['config', 'user.name', 'Test']);
      File(
        '${tempDir.path}${Platform.pathSeparator}a.txt',
      ).writeAsStringSync('a');
      await runGit(['add', 'a.txt']);
      await runGit(['commit', '-m', 'base']);
      return tempDir.path;
    }

    test(
      'removeWorktree does not delete the branch — reproduces the retry '
      'collision found live: recreating a worktree on the same branch '
      "name fails with 'already exists' until deleteBranch runs first",
      () async {
        final rootPath = await initRepoWithCommit();
        final worktreeDir = await Directory.systemTemp.createTemp(
          'git_client_worktree_',
        );
        addTearDown(() async {
          if (worktreeDir.existsSync()) {
            await worktreeDir.delete(recursive: true);
          }
        });

        await client.createWorktree(
          rootPath,
          worktreeDir.path,
          'aion/task-fixture',
        );
        await client.removeWorktree(rootPath, worktreeDir.path);

        // The exact collision: TicketsCubit._runCodingExecution reuses
        // this same branch name on every retry of the same task.
        await expectLater(
          client.createWorktree(
            rootPath,
            worktreeDir.path,
            'aion/task-fixture',
          ),
          throwsA(isA<ProcessException>()),
        );

        // The fix: deleting the abandoned branch first lets the next
        // attempt recreate it cleanly, exactly as a first attempt would.
        await client.deleteBranch(rootPath, 'aion/task-fixture');
        await client.createWorktree(
          rootPath,
          worktreeDir.path,
          'aion/task-fixture',
        );
        expect(await Directory(worktreeDir.path).exists(), isTrue);
      },
    );
  });
}
