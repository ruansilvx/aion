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

  /// Runs `git worktree add -b <branchName> <worktreePath>` in [rootPath],
  /// creating a new branch checked out into an isolated working directory
  /// at [worktreePath] — the branch starts from [rootPath]'s current HEAD.
  /// Throws if `worktreePath` already exists or `branchName` is already
  /// checked out elsewhere. Added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety` — isolates
  /// a coding-execution run from the developer's real checkout.
  Future<void> createWorktree(
    String rootPath,
    String worktreePath,
    String branchName,
  ) async {
    await _run(['worktree', 'add', '-b', branchName, worktreePath], rootPath);
  }

  /// Runs `git worktree remove <worktreePath> --force` in [rootPath].
  /// `--force` because the worktree may contain untracked build artifacts
  /// (`.dart_tool/`, `build/`) from the `flutter pub get`/coding-execution
  /// turn that ran inside it — git's default refuses removal with any
  /// untracked content present. Does not delete the worktree's branch
  /// itself; the branch survives (and stays pushed, if [push] below
  /// already ran) after the worktree is gone.
  Future<void> removeWorktree(String rootPath, String worktreePath) async {
    await _run(['worktree', 'remove', worktreePath, '--force'], rootPath);
  }

  /// Runs `git push -u origin <branchName>` in [worktreePath] — pushes the
  /// branch created by [createWorktree] from inside the worktree itself
  /// (not [rootPath]), since that's where the branch's commits actually
  /// live.
  Future<void> push(String worktreePath, String branchName) async {
    await _run(['push', '-u', 'origin', branchName], worktreePath);
  }

  Future<ProcessResult> _run(List<String> args, String rootPath) {
    return Process.run('git', args, workingDirectory: rootPath);
  }
}
