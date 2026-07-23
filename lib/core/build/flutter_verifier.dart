// core/build/flutter_verifier.dart — FlutterVerifier (core layer).

import 'dart:io';

/// Result of a [FlutterVerifier.analyze] run.
class FlutterVerifyResult {
  /// Creates a [FlutterVerifyResult].
  const FlutterVerifyResult({required this.passed, required this.output});

  /// Whether `flutter analyze` exited 0 (no issues at or above the
  /// project's configured `analysis_options.yaml` severity).
  final bool passed;

  /// Raw combined stdout/stderr, fed back to the model verbatim as the
  /// corrective turn's prompt content on failure.
  final String output;
}

/// Thin wrapper around `flutter analyze`/`flutter pub get`, invoked via
/// [Process.run]. One implementation, no interface — same shape as
/// `GitRepositoryClient`/`GitHubCliClient` (`core/git/`). Added for
/// `aion-arch/changes/coding-execution-reliability-and-safety` —
/// [analyze] is the verification gate a coding-execution run must pass
/// before Aion pushes and opens a PR; [pubGet] is the one-time setup that
/// gate (and the model's own tool calls) need in a fresh worktree.
/// `design.md` §8's pseudocode originally sketched the `pub get` call as
/// an inline `Process.run` in `TicketsCubit` — it landed here instead so
/// tests can mock it rather than spawning a real `flutter` subprocess,
/// consistent with why [analyze] itself is a class method and not an
/// inline call.
class FlutterVerifier {
  /// Runs `flutter analyze` in [rootPath] (a coding-execution worktree).
  Future<FlutterVerifyResult> analyze(String rootPath) async {
    final result = await Process.run('flutter', [
      'analyze',
    ], workingDirectory: rootPath);
    return FlutterVerifyResult(
      passed: result.exitCode == 0,
      output: '${result.stdout}\n${result.stderr}'.trim(),
    );
  }

  /// Runs `flutter pub get` in [rootPath] — the one-time setup a fresh
  /// coding-execution worktree needs so [analyze] (and the model's own
  /// tool calls) see a working `.dart_tool/package_config.json`. Kept on
  /// this same injectable class (rather than a raw `Process.run` inline
  /// in `TicketsCubit`) specifically so tests can mock it instead of
  /// spawning a real `flutter` subprocess.
  Future<void> pubGet(String rootPath) async {
    await Process.run('flutter', ['pub', 'get'], workingDirectory: rootPath);
  }
}
