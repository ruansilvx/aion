// core/build/project_stack_detector.dart — DetectedStack + ProjectStackDetector, plus DetectedVersionFile/VersionFileKind for release-version read/write (core layer).

import 'dart:convert';
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

/// Which per-stack version-file convention a [DetectedVersionFile]
/// follows — determines how [ProjectStackDetector.writeVersion] parses
/// and rewrites it. Only stacks with a real, machine-parseable version
/// field are represented here. `go.mod` and `requirements.txt` are still
/// detected by [ProjectStackDetector.detect] for prompt-guidance
/// purposes (see [DetectedStack]'s dartdoc), but
/// [ProjectStackDetector.detectVersionFile] returns `null` for both:
/// `go.mod`'s `go 1.x` line is a language-version pin, not the app's own
/// release version, and `requirements.txt` has no project-metadata
/// version field at all. Prepare Release still tags a project on either
/// stack — it just skips the version-bump step, surfaced by
/// `ReleaseDraftScreen`'s "no version file detected" notice. Added for
/// `AIO-1782`; see that
/// change's design.md §1.
enum VersionFileKind {
  /// `pubspec.yaml`'s top-level `version:` field.
  pubspecYaml,

  /// `package.json`'s top-level `"version"` key.
  packageJson,

  /// `Cargo.toml`'s `[package]` section's `version = "..."` line, scoped
  /// to that section so a dependency's own `version = "..."` line
  /// elsewhere in the file is never matched.
  cargoToml,

  /// `pyproject.toml`'s `[project]` section's `version = "..."` line,
  /// same section-scoped strategy as [cargoToml]. PEP 621 layout only —
  /// a `[tool.poetry]`-style project is not handled this round, a known,
  /// documented gap.
  pyprojectToml,
}

/// Where a project's own release version lives, and how to read/rewrite
/// it. Returned by [ProjectStackDetector.detectVersionFile] — `null` when
/// the detected stack (or no stack at all) has no supported version file
/// this round; see [VersionFileKind]'s dartdoc for exactly which stacks
/// qualify. Distinct from [DetectedStack]: that class is guidance text
/// only, never read by Aion's own code, while this one backs a real read
/// (this class) and write ([ProjectStackDetector.writeVersion]), driving
/// `TicketsCubit.prepareReleaseDraft`/`.confirmRelease`. Added for
/// `AIO-1782`.
class DetectedVersionFile {
  /// Creates a [DetectedVersionFile].
  const DetectedVersionFile({
    required this.file,
    required this.currentVersion,
    required this.kind,
  });

  /// The version file itself, resolved under the project root.
  final File file;

  /// The version string as currently written in [file] (e.g. `"1.4.2"`),
  /// as of when [ProjectStackDetector.detectVersionFile] ran — a stale
  /// snapshot, not a live read; a caller that needs the latest value
  /// after some other write must re-run [ProjectStackDetector
  /// .detectVersionFile].
  final String currentVersion;

  /// Which stack's version-file convention [file] follows.
  final VersionFileKind kind;
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

  /// Locates [rootPath]'s version file and reads its current version, per
  /// [VersionFileKind]'s per-stack table (see that enum's dartdoc).
  /// Checked in the same order [_markers] lists its four supported
  /// entries — `pubspec.yaml`, `package.json`, `Cargo.toml`,
  /// `pyproject.toml` — first match wins, mirroring [detect]'s own
  /// marker-priority behavior. Returns `null` when none of those four
  /// marker files exists, or when the one that does exist has a version
  /// field this round's parser can't find (e.g. a `pyproject.toml` using
  /// `[tool.poetry]` instead of PEP 621's `[project]` — see
  /// [VersionFileKind.pyprojectToml]'s documented gap) — a caller treats
  /// both cases identically as "no version file detected." `go.mod`/
  /// `requirements.txt` always return `null` here even though [detect]
  /// still recognizes them for guidance text.
  DetectedVersionFile? detectVersionFile(String rootPath) {
    final sep = Platform.pathSeparator;

    final pubspec = _detectPubspecVersion(File('$rootPath$sep' 'pubspec.yaml'));
    if (pubspec != null) return pubspec;

    final packageJson = _detectPackageJsonVersion(
      File('$rootPath$sep' 'package.json'),
    );
    if (packageJson != null) return packageJson;

    final cargo = _detectSectionVersion(
      File('$rootPath$sep' 'Cargo.toml'),
      '[package]',
      VersionFileKind.cargoToml,
    );
    if (cargo != null) return cargo;

    final pyproject = _detectSectionVersion(
      File('$rootPath$sep' 'pyproject.toml'),
      '[project]',
      VersionFileKind.pyprojectToml,
    );
    if (pyproject != null) return pyproject;

    return null;
  }

  /// Rewrites [detected]'s version field to [newVersion], preserving
  /// every other byte of the file where possible. Dispatches on
  /// [DetectedVersionFile.kind]:
  /// - [VersionFileKind.pubspecYaml]/[VersionFileKind.cargoToml]/
  ///   [VersionFileKind.pyprojectToml]: replaces just the matched
  ///   `version:`/`version = "..."` line in place — every other line is
  ///   untouched.
  /// - [VersionFileKind.packageJson]: decodes/re-encodes the whole file
  ///   via `dart:convert` (safer than a regex for real JSON), which means
  ///   — unlike the other three — the file's original key order and
  ///   formatting are not guaranteed to survive. An accepted trade-off
  ///   for correctness over cosmetics on this one stack.
  ///
  /// Called by `TicketsCubit.confirmRelease` only when
  /// [ReleaseDraft.detectedVersionFile] is non-null. Throws if
  /// [detected]'s `.file` no longer exists or the version field it
  /// matched at detect time is no longer present (e.g. hand-edited
  /// between drafting and confirming).
  Future<void> writeVersion(
    DetectedVersionFile detected,
    String newVersion,
  ) async {
    final content = await detected.file.readAsString();
    final updated = switch (detected.kind) {
      VersionFileKind.pubspecYaml => _writeLineVersion(
        content,
        _pubspecVersionPattern,
        'version: $newVersion',
      ),
      VersionFileKind.packageJson => _writePackageJsonVersion(
        content,
        newVersion,
      ),
      VersionFileKind.cargoToml => _writeSectionVersion(
        content,
        '[package]',
        newVersion,
      ),
      VersionFileKind.pyprojectToml => _writeSectionVersion(
        content,
        '[project]',
        newVersion,
      ),
    };
    await detected.file.writeAsString(updated);
  }

  static final RegExp _pubspecVersionPattern = RegExp(
    r'^version:\s*(.+)$',
    multiLine: true,
  );

  static final RegExp _sectionVersionPattern = RegExp(
    r'^version\s*=\s*"([^"]*)"',
    multiLine: true,
  );

  DetectedVersionFile? _detectPubspecVersion(File file) {
    if (!file.existsSync()) return null;
    final match = _pubspecVersionPattern.firstMatch(file.readAsStringSync());
    if (match == null) return null;
    return DetectedVersionFile(
      file: file,
      currentVersion: match.group(1)!.trim(),
      kind: VersionFileKind.pubspecYaml,
    );
  }

  DetectedVersionFile? _detectPackageJsonVersion(File file) {
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic> && decoded['version'] is String) {
        return DetectedVersionFile(
          file: file,
          currentVersion: decoded['version'] as String,
          kind: VersionFileKind.packageJson,
        );
      }
    } on FormatException {
      // Malformed JSON — treated the same as "no version file detected".
    }
    return null;
  }

  DetectedVersionFile? _detectSectionVersion(
    File file,
    String sectionHeader,
    VersionFileKind kind,
  ) {
    if (!file.existsSync()) return null;
    final body = _sectionBody(file.readAsStringSync(), sectionHeader);
    if (body == null) return null;
    final match = _sectionVersionPattern.firstMatch(body);
    if (match == null) return null;
    return DetectedVersionFile(
      file: file,
      currentVersion: match.group(1)!,
      kind: kind,
    );
  }

  /// Returns the substring of [content] from just after [sectionHeader]
  /// up to the next `[section]` header (or end of file) — scopes
  /// [_sectionVersionPattern] to just that section, so a dependency's own
  /// `version = "..."` line elsewhere in the file is never matched.
  /// `null` if [sectionHeader] doesn't appear in [content] at all.
  String? _sectionBody(String content, String sectionHeader) {
    final headerIndex = content.indexOf(sectionHeader);
    if (headerIndex == -1) return null;
    final afterHeader = headerIndex + sectionHeader.length;
    final nextSectionIndex = content.indexOf(
      RegExp(r'^\[', multiLine: true),
      afterHeader,
    );
    return content.substring(
      afterHeader,
      nextSectionIndex == -1 ? content.length : nextSectionIndex,
    );
  }

  String _writeLineVersion(String content, RegExp pattern, String newLine) {
    return content.replaceFirst(pattern, newLine);
  }

  String _writePackageJsonVersion(String content, String newVersion) {
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    decoded['version'] = newVersion;
    return '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
  }

  String _writeSectionVersion(
    String content,
    String sectionHeader,
    String newVersion,
  ) {
    final headerIndex = content.indexOf(sectionHeader);
    if (headerIndex == -1) {
      throw StateError('$sectionHeader not found while writing version.');
    }
    final afterHeader = headerIndex + sectionHeader.length;
    final nextSectionIndex = content.indexOf(
      RegExp(r'^\[', multiLine: true),
      afterHeader,
    );
    final sectionEnd = nextSectionIndex == -1
        ? content.length
        : nextSectionIndex;
    final before = content.substring(0, afterHeader);
    final section = content.substring(afterHeader, sectionEnd);
    final after = content.substring(sectionEnd);
    final updatedSection = section.replaceFirst(
      _sectionVersionPattern,
      'version = "$newVersion"',
    );
    return before + updatedSection + after;
  }
}
