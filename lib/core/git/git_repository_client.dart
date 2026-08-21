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
  /// Returns whether [rootPath] is already inside a git working tree —
  /// checked via `<rootPath>/.git` existing, not a `git` subprocess call
  /// (cheap, consistent with `ProjectStackDetector`'s own
  /// marker-file-only approach). `.git` may be a directory (an ordinary
  /// repo) or a file (a linked worktree/submodule) — both count as
  /// "already a repo" for this check's purposes; it doesn't distinguish
  /// between them since neither should have `git init`/bookkeeping
  /// written over it. Added for
  /// `aion-arch/changes/new-project-onboarding` — lets
  /// `CreateProjectCubit` skip re-`init`ing an already-git-tracked
  /// directory and gate its gitignore-confirmation banner.
  Future<bool> isGitRepository(String rootPath) async {
    return File(
          '$rootPath${Platform.pathSeparator}.git',
        ).existsSync() ||
        Directory(
          '$rootPath${Platform.pathSeparator}.git',
        ).existsSync();
  }

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
    await _runChecked(
      ['worktree', 'add', '-b', branchName, worktreePath],
      rootPath,
    );
  }

  /// Runs `git worktree remove <worktreePath> --force` in [rootPath].
  /// `--force` because the worktree may contain untracked build artifacts
  /// (`.dart_tool/`, `build/`) from the `flutter pub get`/coding-execution
  /// turn that ran inside it — git's default refuses removal with any
  /// untracked content present. Does not delete the worktree's branch
  /// itself; the branch survives (and stays pushed, if [push] below
  /// already ran) after the worktree is gone.
  Future<void> removeWorktree(String rootPath, String worktreePath) async {
    await _runChecked(['worktree', 'remove', worktreePath, '--force'], rootPath);
  }

  /// Runs `git push -u origin <branchName>` in [worktreePath] — pushes the
  /// branch created by [createWorktree] from inside the worktree itself
  /// (not [rootPath]), since that's where the branch's commits actually
  /// live.
  Future<void> push(String worktreePath, String branchName) async {
    await _runChecked(['push', '-u', 'origin', branchName], worktreePath);
  }

  /// Runs `git diff --name-only <baseBranch>...<branch>` in [worktreePath]
  /// and returns the count of changed files. Computed locally rather than
  /// via `gh pr view --json files` (a second network call, with a risk of
  /// eventual-consistency lag immediately after `gh pr create` returns) —
  /// the worktree already has everything needed on disk. Called just
  /// before `push` in `TicketsCubit._runCodingExecution`, from inside the
  /// worktree `push` itself already runs from. Added for
  /// `aion-arch/changes/pr-metadata-and-notification-center`.
  Future<int> changedFileCount(
    String worktreePath,
    String baseBranch,
    String branch,
  ) async {
    final result = await _runChecked(
      ['diff', '--name-only', '$baseBranch...$branch'],
      worktreePath,
    );
    final output = result.stdout.toString().trim();
    return output.isEmpty ? 0 : output.split('\n').length;
  }

  /// Runs `git rev-parse --abbrev-ref origin/HEAD` in [rootPath] (the
  /// *original* checkout, not the worktree — `origin/HEAD` is a
  /// repository-wide ref, identical either place, but `rootPath` is
  /// already resolved and doesn't require the worktree to exist yet) and
  /// strips the `origin/` prefix, returning e.g. `'main'`. Falls back to
  /// `'main'` if the command fails (a shallow clone or a repo with no
  /// `origin/HEAD` set) — matching `gh pr create`'s own base-branch
  /// resolution fallback (repository's configured default branch). Added
  /// for `aion-arch/changes/pr-metadata-and-notification-center`.
  Future<String> defaultBranch(String rootPath) async {
    final result = await _run(
      ['rev-parse', '--abbrev-ref', 'origin/HEAD'],
      rootPath,
    );
    if (result.exitCode != 0) return 'main';
    final ref = result.stdout.toString().trim();
    return ref.startsWith('origin/') ? ref.substring('origin/'.length) : ref;
  }

  Future<ProcessResult> _run(List<String> args, String rootPath) {
    return Process.run('git', args, workingDirectory: rootPath);
  }

  /// Same as [_run], but throws a [ProcessException] (carrying `stderr`)
  /// if `git` exits non-zero. [createWorktree]/[removeWorktree]/[push]
  /// use this rather than [init]/[add]/[commit]/[hasChanges]'s existing
  /// fire-and-forget shape, because a silently swallowed failure here
  /// leaves a coding-execution run believing an isolated worktree exists
  /// when it doesn't — confirmed via a live manual run: `git worktree
  /// add` failing silently left the model's turn pointed at an empty
  /// temp directory, which it escaped by finding and committing to the
  /// developer's real checkout instead of throwing loudly and aborting.
  /// A `/verify` follow-up fix for
  /// `aion-arch/changes/coding-execution-reliability-and-safety`.
  Future<ProcessResult> _runChecked(List<String> args, String rootPath) async {
    final result = await _run(args, rootPath);
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      throw ProcessException(
        'git',
        args,
        stderr.isEmpty ? 'git ${args.join(' ')} exited ${result.exitCode}' : stderr,
        result.exitCode,
      );
    }
    return result;
  }
}
