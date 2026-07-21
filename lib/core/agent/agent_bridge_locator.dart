// core/agent/agent_bridge_locator.dart — AgentBridgeLocator (core layer).

import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the absolute path to the bundled Node.js bridge script
/// (`agent_bridge/index.mjs`, sibling to the Flutter project root — see
/// `aion-arch/changes/provider-configuration/design.md` §3). Desktop-only,
/// same gate as `GitRepositoryClient`'s callers.
///
/// Tries a `Directory.current`-relative path first (matches `flutter run`'s
/// working directory during development), then a path relative to the
/// running executable's directory (for a built desktop binary, whose
/// working directory may not be the project root). Returns the first
/// candidate that exists on disk; if neither does, returns the first
/// candidate anyway so the resulting error (surfaced by
/// `ClaudeAgentSdkClient` as a readable `AgentErrorEvent`) names an
/// actual path rather than throwing here.
class AgentBridgeLocator {
  /// Returns the absolute path to `agent_bridge/index.mjs`.
  String resolve() {
    final candidates = [
      p.join(Directory.current.path, 'agent_bridge', 'index.mjs'),
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'agent_bridge',
        'index.mjs',
      ),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return candidates.first;
  }
}
