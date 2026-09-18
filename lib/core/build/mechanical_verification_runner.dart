// core/build/mechanical_verification_runner.dart — MechanicalVerificationRunner + MechanicalCheckResult (core layer).

import 'dart:io';

/// One command's outcome from [MechanicalVerificationRunner.run].
class MechanicalCheckResult {
  /// Creates a [MechanicalCheckResult].
  const MechanicalCheckResult({
    required this.command,
    required this.exitCode,
    required this.output,
  });

  /// The command as given to [MechanicalVerificationRunner.run] (e.g.
  /// `'flutter analyze'`).
  final String command;

  /// The process's real exit code.
  final int exitCode;

  /// Combined stdout+stderr captured from the run.
  final String output;

  /// Whether [command] exited successfully (`0`).
  bool get passed => exitCode == 0;
}

/// Independently re-runs a [DetectedStack.checkCommand] list against a real
/// coding-execution worktree via [Process.run] — the mechanical
/// counterpart to the agentic verify turn's own self-reported
/// `VERIFICATION: PASSED`/`FAILED` line. Deliberately a method on this
/// service rather than a bare inline [Process.run] call in
/// `TicketsCubit._runCodingExecution`, so that cubit's own test coverage
/// can mock this class instead of shelling out to a real build/test/lint
/// command (slow, environment-dependent) on every `_runCodingExecution`
/// test run — the same testability rationale `DependencyCacheService
/// .installDependencies`/`TicketsCubit`'s `GitRepositoryClient`/
/// `GitHubCliClient` wrapper-class-not-bare-`Process.run` shape already
/// established elsewhere. Added for `AIO-2943`.
class MechanicalVerificationRunner {
  /// Creates a [MechanicalVerificationRunner].
  const MechanicalVerificationRunner();

  /// Runs each of [commands] sequentially inside [workingDirectory],
  /// stopping at the first non-zero exit code — so a caller can tell
  /// exactly which command failed, not just "something in the chain
  /// failed." Returns every result actually attempted (a passing run
  /// returns one entry per command in [commands]; a failing one returns
  /// only up to and including the first failure). Each command is split
  /// on whitespace and run via the shell (`runInShell: true`), matching
  /// [DetectedStack.checkCommand]'s own plain-string shape (e.g.
  /// `'flutter analyze'`, `'go build ./...'`).
  Future<List<MechanicalCheckResult>> run(
    List<String> commands,
    String workingDirectory,
  ) async {
    final results = <MechanicalCheckResult>[];
    for (final command in commands) {
      final parts = command.split(' ');
      final result = await Process.run(
        parts.first,
        parts.skip(1).toList(),
        workingDirectory: workingDirectory,
        runInShell: true,
      );
      results.add(
        MechanicalCheckResult(
          command: command,
          exitCode: result.exitCode,
          output: '${result.stdout}${result.stderr}',
        ),
      );
      if (result.exitCode != 0) break;
    }
    return results;
  }
}
