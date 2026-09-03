// core/git/gitignore_editor.dart — GitignoreEditor (core layer).

import 'dart:io';

/// Appends bookkeeping paths to a project's `.gitignore` file so they don't
/// get committed into an attached, already-git-tracked codebase's own history.
/// Pure file I/O — no `git` subprocess involved, unlike
/// [GitRepositoryClient](git_repository_client.dart). Added for `AIO-1266`'s
/// gitignore-confirmation gate.
class GitignoreEditor {
  /// Appends any of [entries] not already present (line-exact match) to
  /// `<rootPath>/.gitignore`, creating the file (containing just
  /// [entries]) if it doesn't exist yet. Idempotent — safe to call
  /// repeatedly, or on a `.gitignore` that already has some or all of
  /// [entries] present.
  Future<void> ensureIgnored(String rootPath, List<String> entries) async {
    final file = File('$rootPath${Platform.pathSeparator}.gitignore');

    final existingLines = file.existsSync()
        ? file.readAsStringSync().split('\n')
        : <String>[];

    final missing = entries
        .where((entry) => !existingLines.contains(entry))
        .toList();
    if (missing.isEmpty) return;

    final needsLeadingNewline =
        existingLines.isNotEmpty && existingLines.last.trim().isNotEmpty;
    final addition = (needsLeadingNewline ? '\n' : '') +
        missing.map((entry) => '$entry\n').join();

    await file.writeAsString(addition, mode: FileMode.append);
  }
}
