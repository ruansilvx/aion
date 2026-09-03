// core/build/dependency_cache_service.dart — DependencyCacheService (core layer).

import 'dart:io';

import 'package:path/path.dart' as p;

/// Seeds a coding-execution worktree's `node_modules` from a per-project
/// cache directory, and writes it back after a successful `npm install`, so
/// later runs against the same project start warm. Desktop-only (matches
/// `GitRepositoryClient`'s existing desktop-only scope — coding execution
/// itself is desktop-only). Copy-based, not hardlink-based: `dart:io` has no
/// native hardlink API (`Link` creates symlinks only), and shelling out to
/// `ln`/`mklink` per file across a multi-thousand-file `node_modules` tree
/// would mean thousands of subprocess spawns per run — almost certainly
/// slower and more fragile than one recursive [File.copy] walk. Scoped to
/// Node.js only by [TicketsCubit._runCodingExecution] — see that method's
/// dartdoc for why Flutter/Dart, Rust, Go, and Python are out of scope for
/// this class.
///
/// Never live-shared across concurrent worktrees: the cache directory this
/// class manages is only ever read from ([seed]) into a private per-worktree
/// `node_modules`, or written to ([writeBack]) from one, never
/// symlinked/junctioned directly into a worktree. With `AIO-1400`'s
/// N-concurrent-runs already shipped, a live-shared directory would let two
/// simultaneous Node.js runs corrupt each other's `node_modules` mid-install.
/// Added for `AIO-722`.
class DependencyCacheService {
  /// Creates a [DependencyCacheService].
  const DependencyCacheService();

  /// Copies every file under [cacheDir] into [targetDir], preserving
  /// relative paths, creating parent directories as needed. No-ops (leaves
  /// [targetDir] untouched) if [cacheDir] doesn't exist yet — a project's
  /// first coding-execution run has nothing to seed from.
  Future<void> seed(String cacheDir, String targetDir) async {
    final source = Directory(cacheDir);
    if (!source.existsSync()) return;
    await for (final entity in source.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: cacheDir);
      final destination = File(p.join(targetDir, relative));
      await destination.parent.create(recursive: true);
      await entity.copy(destination.path);
    }
  }

  /// Replaces [cacheDir]'s contents with [sourceDir]'s current contents —
  /// delete-then-copy, chosen over a diff/sync for simplicity and
  /// correctness over the O(size) cost, which is already being paid by
  /// `npm install`'s own writes this same run. Called only after a
  /// successful install (see `TicketsCubit._runCodingExecution`) — never
  /// caches a broken/partial `node_modules`.
  Future<void> writeBack(String sourceDir, String cacheDir) async {
    final cache = Directory(cacheDir);
    if (cache.existsSync()) await cache.delete(recursive: true);
    await cache.create(recursive: true);
    await seed(sourceDir, cacheDir); // same walk-and-copy, source ↔ dest swapped
  }

  /// Runs `npm install` in [worktreePath] and returns whether it exited
  /// successfully. Deliberately a method on this service (rather than a
  /// bare inline [Process.run] call in
  /// `TicketsCubit._runCodingExecution`) so that cubit's own test
  /// coverage can mock this class's [installDependencies] instead of
  /// shelling out to a real `npm install` (network/registry-dependent,
  /// far too slow for a unit test) on every `_runCodingExecution` test
  /// run — the same testability rationale `TicketsCubit`'s
  /// `GitRepositoryClient`/`GitHubCliClient` wrapper-class-not-bare-
  /// `Process.run` shape already established elsewhere.
  Future<bool> installDependencies(String worktreePath) async {
    final result = await Process.run(
      'npm',
      ['install'],
      workingDirectory: worktreePath,
    );
    return result.exitCode == 0;
  }

  /// Resolves [projectId]'s cache directory for [dependencyDirName]'s
  /// dependency directory name (e.g. `'node_modules'` for Node.js) —
  /// co-located under [Directory.systemTemp] alongside every
  /// coding-execution worktree (`TicketsCubit._runCodingExecution`'s
  /// `createTempSync('aion_exec_')`), not under the project's own
  /// `rootPath`. Keeps the cache on the same volume as every worktree
  /// (avoiding any cross-volume copy concern) and out of the user's actual
  /// checkout. Keyed by [projectId] (`Project.id`, not `Project.storageKey`
  /// — `TicketsCubit` only carries the former as `_projectId`, already a
  /// unique-per-project UUID, so it serves the same keying purpose without
  /// threading a whole `Project` instance through
  /// `_runCodingExecution` just for this).
  String cacheDirFor(String projectId, String dependencyDirName) {
    return p.join(
      Directory.systemTemp.path,
      'aion_dep_cache',
      projectId,
      dependencyDirName,
    );
  }
}
