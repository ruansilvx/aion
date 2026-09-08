// core/build/orphaned_worktree_temp_sweeper.dart — sweepOrphanedWorktreeTempDirs.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Reaps stale `aion_exec_*`/`aion_skill_*`/`aion_analysis_*` directories
/// left under the OS temp directory (`Directory.systemTemp`) by a
/// coding-execution, skill-attachment, or full-codebase-analysis run whose
/// `git worktree` cleanup never ran — a process killed mid-run (the
/// `finally` that owns `GitRepositoryClient.removeWorktree` never executes
/// when the whole isolate is torn down), or an exception/early return that
/// used to fire *before* that `finally` was even entered, orphaning the
/// bare [Directory.createTempSync] result with nothing left to remove it.
/// The latter class was the dominant one in practice — confirmed via
/// ~10,000 orphaned directories accumulated under one developer's %TEMP%,
/// ~99% of them empty (i.e. `git worktree add` was never even reached) —
/// and is fixed at the source in `TicketsCubit._runCodingExecution` /
/// `_runFullSummarization` (the temp dir is now created only once every
/// early exit ahead of their `try`/`finally` is behind them). This sweep is
/// the backstop for what that source fix can't prevent: a hard process
/// kill, or `removeWorktree` itself failing (e.g. a locked file) and being
/// swallowed as best-effort cleanup — and it also reclaims the backlog that
/// already accumulated before the source fix landed.
///
/// Only entries matching one of the three prefixes above, and whose
/// last-modified time is older than [minAge] (comfortably longer than any
/// real run should ever take), are removed — a worktree still legitimately
/// in use by this session is always far younger than that and is never
/// touched. Best-effort per entry: a delete that fails (e.g. a file still
/// locked by an antivirus scan or another process) is skipped rather than
/// thrown for, matching every other cleanup path in this codebase (see the
/// `catch (_)` blocks around `GitRepositoryClient.removeWorktree` in
/// `TicketsCubit`) — it simply survives to the next sweep. Desktop-only,
/// called once from `AionApp.initState` (`main.dart`), fire-and-forget —
/// never awaited there, so it can never delay app startup.
Future<void> sweepOrphanedWorktreeTempDirs({
  Duration minAge = const Duration(hours: 24),
  Directory? tempDir,
}) async {
  final dir = tempDir ?? Directory.systemTemp;
  final cutoff = DateTime.now().subtract(minAge);
  const prefixes = ['aion_exec_', 'aion_skill_', 'aion_analysis_'];

  List<FileSystemEntity> entries;
  try {
    entries = await dir.list().toList();
  } catch (_) {
    // Can't even list the temp directory — nothing to do.
    return;
  }

  for (final entry in entries) {
    if (entry is! Directory) continue;
    final name = p.basename(entry.path);
    if (!prefixes.any(name.startsWith)) continue;
    try {
      final stat = await entry.stat();
      if (stat.modified.isAfter(cutoff)) continue;
      await entry.delete(recursive: true);
    } catch (_) {
      // Best-effort only — see this function's dartdoc.
    }
  }
}
