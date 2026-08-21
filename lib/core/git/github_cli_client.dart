// core/git/github_cli_client.dart — GitHubCliClient (core layer).

import 'dart:io';

/// Thin wrapper around the `gh` CLI, invoked via [Process.run]. Mirrors
/// [GitRepositoryClient]'s shape — one implementation, no
/// `core/contracts/` interface, since it has no feature-specific logic to
/// invert. Desktop-only, same scope as [GitRepositoryClient]. Added for
/// `aion-arch/changes/coding-execution-reliability-and-safety` so a
/// coding-execution run's PR is opened by Aion itself, only after its
/// verification gate passes — never by the model's own tool calls.
class GitHubCliClient {
  /// Runs `gh pr create --title <title> --body <body> --head <branch>` in
  /// [rootPath] (the worktree the branch's commits live in — `gh` resolves
  /// the remote/base branch from the local repo config the same way it
  /// does for a human running the command by hand). Returns the created
  /// PR's URL (parsed from `gh pr create`'s stdout, its last non-empty
  /// line, as before) plus its number, parsed from that same URL's last
  /// path segment — `gh pr create` never prints the number on its own
  /// (`gh pr create --help` documents it as printing only the URL; unlike
  /// `gh pr view`/`gh pr list`, `pr create` has no `--json` flag). Throws a
  /// [ProcessException] on failure (`gh` not installed/authenticated) —
  /// the caller (`TicketsCubit._runCodingExecution`) surfaces this as a
  /// normal execution failure, not a special case. `int.parse` on the
  /// number is intentionally unguarded — if `gh`'s URL format ever changes
  /// shape, this should fail loudly (caught by that same surrounding
  /// `catch`) rather than silently produce a wrong number. Added for
  /// `aion-arch/changes/pr-metadata-and-notification-center`.
  Future<({String url, int number})> openPullRequest({
    required String rootPath,
    required String branch,
    required String title,
    required String body,
  }) async {
    final result = await Process.run('gh', [
      'pr',
      'create',
      '--title',
      title,
      '--body',
      body,
      '--head',
      branch,
    ], workingDirectory: rootPath);
    if (result.exitCode != 0) {
      throw ProcessException('gh', [
        'pr',
        'create',
      ], result.stderr.toString());
    }
    final url = result.stdout.toString().trim().split('\n').last;
    final number = int.parse(url.split('/').last);
    return (url: url, number: number);
  }
}
