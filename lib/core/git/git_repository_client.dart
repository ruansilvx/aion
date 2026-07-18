// core/git/git_repository_client.dart — GitRepositoryClient (core layer).

import 'dart:io';

/// Thin wrapper around the `git` CLI, invoked via [Process.run]. Plain
/// `core/` infrastructure, not a `core/contracts/` interface — there is
/// one implementation, and both `features/projects/` (repo
/// initialization) and `features/tickets/` (per-ticket commits) import it
/// directly, since it has no feature-specific logic to invert behind an
/// interface.
///
/// Desktop-only, matching the existing desktop-only scope of per-project
/// git repos (`CreateProjectCubit._initializeDesktopProject`).
class GitRepositoryClient {
  /// Runs `git init` in [rootPath].
  Future<void> init(String rootPath) async {
    await _run(['init'], rootPath);
  }

  /// Runs `git add <relativePath>` in [rootPath].
  Future<void> add(String rootPath, String relativePath) async {
    await _run(['add', relativePath], rootPath);
  }

  /// Returns whether `git status --porcelain` in [rootPath] reports any
  /// pending changes (staged or unstaged). Used to skip a commit when a
  /// write didn't actually change the serialized content.
  Future<bool> hasChanges(String rootPath) async {
    final result = await _run(['status', '--porcelain'], rootPath);
    return result.stdout.toString().trim().isNotEmpty;
  }

  /// Runs `git commit -m <message>` in [rootPath].
  Future<void> commit(String rootPath, String message) async {
    await _run(['commit', '-m', message], rootPath);
  }

  Future<ProcessResult> _run(List<String> args, String rootPath) {
    return Process.run('git', args, workingDirectory: rootPath);
  }
}
