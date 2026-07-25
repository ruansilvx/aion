// core/build/project_stack_detector.dart — DetectedStack + ProjectStackDetector (core layer).

import 'dart:io';

/// A stack detected by [ProjectStackDetector.detect] — a display name
/// plus a suggested setup/check command, written as guidance text into
/// a project's `conventions/architecture-conventions` override by
/// `BaselineTailoringService`. Purely informational: nothing in Aion's
/// own Dart code runs [checkCommand] — it's read by the model during a
/// coding-execution implement/verify turn (see `TicketsCubit`'s
/// `_effectiveAssetContent`), the same way any other line of `Project
/// conventions` is.
class DetectedStack {
  /// Creates a [DetectedStack].
  const DetectedStack({
    required this.language,
    this.setupCommand,
    required this.checkCommand,
  });

  /// Human-readable display name for the detected language/stack (e.g.
  /// `"Flutter/Dart"`).
  final String language;

  /// A suggested one-time setup command (e.g. `"npm install"`), or
  /// `null` if this stack typically needs none.
  final String? setupCommand;

  /// A suggested build/lint/test command (e.g. `"flutter analyze"`).
  final String checkCommand;
}

/// Lightweight marker-file detection — no dependency parsing, just
/// "does this file exist at the project root." Order matters only in
/// that the first match wins; today's marker set doesn't overlap.
class ProjectStackDetector {
  static const _markers = <String, DetectedStack>{
    'pubspec.yaml': DetectedStack(
      language: 'Flutter/Dart',
      setupCommand: 'flutter pub get',
      checkCommand: 'flutter analyze',
    ),
    'package.json': DetectedStack(
      language: 'Node.js',
      setupCommand: 'npm install',
      checkCommand: 'npm test',
    ),
    'Cargo.toml': DetectedStack(
      language: 'Rust',
      checkCommand: 'cargo check',
    ),
    'go.mod': DetectedStack(language: 'Go', checkCommand: 'go build ./...'),
    'pyproject.toml': DetectedStack(
      language: 'Python',
      setupCommand: 'pip install -e .',
      checkCommand: 'pytest',
    ),
    'requirements.txt': DetectedStack(
      language: 'Python',
      setupCommand: 'pip install -r requirements.txt',
      checkCommand: 'pytest',
    ),
  };

  /// Returns the first detected stack for [rootPath], or `null` if no
  /// known marker file exists — `BaselineTailoringService` simply writes
  /// no override in that case, leaving the generic placeholder content
  /// in place for the model to reason from directly.
  DetectedStack? detect(String rootPath) {
    for (final entry in _markers.entries) {
      if (File(
        '$rootPath${Platform.pathSeparator}${entry.key}',
      ).existsSync()) {
        return entry.value;
      }
    }
    return null;
  }
}
