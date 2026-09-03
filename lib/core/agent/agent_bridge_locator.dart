// core/agent/agent_bridge_locator.dart — AgentBridgeLocator (core layer).

import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the absolute path to the bundled Node.js bridge script
/// (`agent_bridge/index.mjs`, sibling to the Flutter project root — see
/// `AIO-1699` §3). Desktop-only,
/// same gate as `GitRepositoryClient`'s callers.
///
/// Tries a `Directory.current`-relative path first (matches `flutter run`'s
/// working directory during development), then walks upward from the
/// running executable's own directory (see [_ancestorCandidates]) — a
/// built desktop binary lives several directories below the project root
/// (e.g. Windows' `build/windows/x64/runner/Release/`, 4 levels below
/// `aion/`), and `Directory.current` only happens to be the project root
/// when the process was launched exactly like `flutter run` launches it;
/// any other launch method (a desktop shortcut, Start Menu entry, a
/// differently-`cd`'d terminal) leaves `Directory.current` pointing
/// somewhere else entirely, so relying on it alone silently breaks every
/// agent-powered feature. The ancestor walk fixes that: it finds the real
/// `agent_bridge/` sibling directory regardless of launch method, as long
/// as the binary is still running from inside its original checkout.
/// Returns the first candidate that exists on disk; if none does, returns
/// the first candidate anyway so the resulting error (surfaced by
/// `ClaudeAgentSdkClient` as a readable `AgentErrorEvent`) names an
/// actual path rather than throwing here.
class AgentBridgeLocator {
  /// Creates an [AgentBridgeLocator]. [currentDirectory]/[executablePath]
  /// default to the real process-global values
  /// (`Directory.current.path`/`Platform.resolvedExecutable`) — every
  /// real construction site (`main.dart`) uses the defaults; tests
  /// override them to exercise [resolve] against a fake directory layout
  /// without touching the actual process's working directory.
  AgentBridgeLocator({String? currentDirectory, String? executablePath})
    : _currentDirectory = currentDirectory ?? Directory.current.path,
      _executablePath = executablePath ?? Platform.resolvedExecutable;

  final String _currentDirectory;
  final String _executablePath;

  /// Returns the absolute path to `agent_bridge/index.mjs`.
  String resolve() {
    final candidates = [
      p.join(_currentDirectory, 'agent_bridge', 'index.mjs'),
      ..._ancestorCandidates(p.dirname(_executablePath)),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return candidates.first;
  }

  /// Yields the would-be `agent_bridge/index.mjs` path at [startDir]
  /// itself, then at each of up to [maxLevels] ancestor directories in
  /// turn — [startDir] first so a binary sitting directly next to
  /// `agent_bridge/` (unlikely today, but cheap to keep) still resolves
  /// in one step, then walking up covers the actual built-binary case.
  /// Stops early if it reaches the filesystem root before [maxLevels] is
  /// exhausted. [maxLevels] defaults generously (8) since the exact
  /// nesting depth is platform-build-specific (Windows' `build/windows/
  /// x64/runner/Release/` is 4 levels; other platforms differ) and an
  /// extra few `File.existsSync()` checks that never match cost nothing
  /// worth guarding against.
  Iterable<String> _ancestorCandidates(String startDir, {int maxLevels = 8}) sync* {
    var dir = Directory(startDir);
    for (var level = 0; level <= maxLevels; level++) {
      yield p.join(dir.path, 'agent_bridge', 'index.mjs');
      final parent = dir.parent;
      if (parent.path == dir.path) break; // reached the filesystem root
      dir = parent;
    }
  }
}
