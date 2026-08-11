// presentation/cubit/ticket_rollup_recomputer.dart — Shared estimate/timeSpent rollup-recompute walk for TicketsCubit/TrashCubit (presentation layer).

import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/domain/utils/ticket_rollup_calculator.dart';

/// Recomputes and persists the estimate/timeSpent rollup for every ticket
/// on a structural ancestor chain, batching every changed ancestor into
/// one git commit. Factored out of `TicketsCubit` so `TrashCubit` doesn't
/// duplicate the walk — both cubits construct one instance (wired to the
/// same [TicketRepository]/optional [TicketGitProjector]/root path they
/// already hold) instead of each carrying a full copy of this logic. See
/// `aion-arch/changes/estimate-timespent-rollup-for-ticket-hierarchy/design.md`
/// §2.1.
class TicketRollupRecomputer {
  /// Creates a [TicketRollupRecomputer] backed by [_repository].
  /// [gitProjector]/[projectRootPath] are optional — when either is
  /// `null`, [recompute]'s git-projection side effect simply no-ops,
  /// matching `TicketsCubit`/`TrashCubit`'s existing optional-dependency
  /// pattern for their own single-ticket git projection.
  TicketRollupRecomputer(
    this._repository, {
    TicketGitProjector? gitProjector,
    String? projectRootPath,
  }) {
    _gitProjector = gitProjector;
    _projectRootPath = projectRootPath;
  }

  final TicketRepository _repository;
  // Assigned in the constructor body rather than via `this._gitProjector`/
  // `this._projectRootPath` initializing formals — the public parameter
  // names (`gitProjector`/`projectRootPath`) intentionally omit the
  // leading underscore their private field counterparts carry, which an
  // initializing formal can't do (its parameter name must match the field
  // name verbatim). Same pattern `TrashCubit`'s own constructor already
  // uses for its identical `gitProjector`/`projectRootPath` fields.
  late final TicketGitProjector? _gitProjector;
  late final String? _projectRootPath;

  /// Recomputes and persists the rollup for every ticket on the path from
  /// each id in [startIds] up to its structural root (inclusive of each
  /// starting id itself — callers pass the *parent* of whatever mutated,
  /// or the changed ticket's own id when it may itself have children; see
  /// `TicketsCubit`/`TrashCubit`'s call sites), then projects every
  /// ticket whose rollup actually changed to git in one batched commit
  /// labelled [eventLabel]. No-ops (and does no I/O at all) if [startIds]
  /// is empty. Intended to be fired with `unawaited(...)` from every call
  /// site — never awaited by the caller's own return path, same pattern
  /// as `TicketsCubit._triggerEmbeddingRegen`/`_triggerGitProjection`.
  Future<void> recompute(Set<String> startIds, String eventLabel) async {
    if (startIds.isEmpty) return;
    final all = await _repository.getAllTickets();
    final byId = {for (final t in all) t.id: t};
    final nodes = [
      for (final t in all)
        (
          id: t.id,
          parentId: t.parentId,
          estimate: t.estimate,
          timeSpent: t.timeSpent,
        ),
    ];
    final results = computeRollups(nodes);

    // Walk every starting id upward to its root, collecting the full
    // ancestor chain (deduplicated — two starting ids can share upper
    // ancestors, e.g. two siblings both trashed under the same parent in
    // one bulk call).
    final chainIds = <String>{};
    for (final start in startIds) {
      var current = byId[start];
      while (current != null && chainIds.add(current.id)) {
        final parentId = current.parentId;
        current = parentId == null ? null : byId[parentId];
      }
    }

    final changed = <Ticket>[];
    for (final id in chainIds) {
      final ticket = byId[id];
      if (ticket == null) continue;
      final result = results[id];
      final newEstimateRollup = result?.estimateRollup;
      final newTimeSpentRollup = result?.timeSpentRollup;
      if (newEstimateRollup == ticket.estimateRollup &&
          newTimeSpentRollup == ticket.timeSpentRollup) {
        continue; // no real change — skip the write and the file rewrite
      }
      await _repository.updateRollup(
        id,
        estimateRollup: newEstimateRollup,
        timeSpentRollup: newTimeSpentRollup,
      );
      changed.add(_withRollup(ticket, newEstimateRollup, newTimeSpentRollup));
    }

    if (changed.isEmpty) return;
    final projector = _gitProjector;
    final rootPath = _projectRootPath;
    if (projector == null || rootPath == null) return;
    await projector.projectBatch(changed, rootPath, eventLabel);
  }

  /// Rebuilds [ticket] with [estimateRollup]/[timeSpentRollup] applied.
  /// [Ticket.copyWith] deliberately has no parameters for either field
  /// (see [Ticket.estimateRollup]'s dartdoc), so this reconstructs the
  /// entity directly rather than adding a backdoor to `copyWith`.
  Ticket _withRollup(Ticket ticket, int? estimateRollup, int? timeSpentRollup) {
    return Ticket(
      id: ticket.id,
      ticketId: ticket.ticketId,
      type: ticket.type,
      title: ticket.title,
      description: ticket.description,
      status: ticket.status,
      priority: ticket.priority,
      parentId: ticket.parentId,
      embedding: ticket.embedding,
      syncStatus: ticket.syncStatus,
      estimate: ticket.estimate,
      timeSpent: ticket.timeSpent,
      createdAt: ticket.createdAt,
      updatedAt: ticket.updatedAt,
      deletedAt: ticket.deletedAt,
      complexity: ticket.complexity,
      sddStage: ticket.sddStage,
      severity: ticket.severity,
      stepsToReproduce: ticket.stepsToReproduce,
      expectedBehavior: ticket.expectedBehavior,
      actualBehavior: ticket.actualBehavior,
      suggestedType: ticket.suggestedType,
      inboxPurpose: ticket.inboxPurpose,
      estimateRollup: estimateRollup,
      timeSpentRollup: timeSpentRollup,
    );
  }
}
