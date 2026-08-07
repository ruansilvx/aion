// presentation/cubit/trash_cubit.dart — TrashCubit business logic (presentation layer).

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/trash_state.dart';

/// Loads and mutates the trash (`/tickets/trash`) via [TicketRepository].
/// Screen-scoped — provided per visit to the Trash screen, not at the app
/// root.
class TrashCubit extends Cubit<TrashState> {
  /// Creates a [TrashCubit] backed by [_repository]. [gitProjector] and
  /// [projectRootPath] are optional — when either is `null` (the default,
  /// and every existing call site/test), [restore]'s git-projection side
  /// effect simply no-ops, matching `TicketsCubit`'s identical
  /// optional-dependency pattern for the same desktop-only feature. Real
  /// usage (`app_router.dart`) supplies both whenever the active project
  /// has a `rootPath`.
  TrashCubit(
    this._repository, {
    TicketGitProjector? gitProjector,
    String? projectRootPath,
  }) : super(const TrashLoading()) {
    _gitProjector = gitProjector;
    _projectRootPath = projectRootPath;
  }

  final TicketRepository _repository;
  late final TicketGitProjector? _gitProjector;
  late final String? _projectRootPath;

  /// How old a trashed ticket must be before "Purge old" will remove it.
  /// Fixed, not user-configurable (see proposal.md's Non-goals).
  static const Duration purgeAgeThreshold = Duration(days: 30);

  /// Fetches every currently trashed ticket, then reduces the flat list
  /// to roots + per-root descendant counts (see [TrashLoaded]'s dartdoc)
  /// and counts how many are old enough for [purgeOldTrash] to remove,
  /// before emitting. Emits [TrashLoading] then [TrashLoaded] on success,
  /// or [TrashError] if the repository call throws.
  Future<void> load() async {
    emit(const TrashLoading());
    try {
      final all = await _repository.getTrashedTickets();
      final trashedIds = all.map((t) => t.id).toSet();
      final childrenByParent = <String, List<Ticket>>{};
      for (final t in all) {
        final parentId = t.parentId;
        if (parentId != null) {
          childrenByParent.putIfAbsent(parentId, () => []).add(t);
        }
      }

      final roots = all
          .where(
            (t) => t.parentId == null || !trashedIds.contains(t.parentId),
          )
          .toList();
      final descendantCounts = {
        for (final root in roots)
          root.id: _countDescendants(root.id, childrenByParent),
      };
      final cutoff = DateTime.now().subtract(purgeAgeThreshold);
      final purgeEligibleCount = all
          .where((t) => t.deletedAt!.isBefore(cutoff))
          .length;

      emit(TrashLoaded(roots, descendantCounts, purgeEligibleCount));
    } catch (e) {
      emit(TrashError(e.toString()));
    }
  }

  /// Counts every ticket reachable from [id] by walking [childrenByParent]
  /// (an adjacency map built once per [load] call from the full trashed
  /// set), recursively.
  int _countDescendants(
    String id,
    Map<String, List<Ticket>> childrenByParent,
  ) {
    var count = 0;
    for (final child in childrenByParent[id] ?? const []) {
      count += 1 + _countDescendants(child.id, childrenByParent);
    }
    return count;
  }

  /// Restores the ticket with internal id [id] via
  /// [TicketRepository.restoreTicket], fires a fire-and-forget
  /// `'restored'` git-projection for it (see [_triggerGitProjection]),
  /// then reloads the trash list. Note: [TicketRepository.restoreTicket]
  /// also revives any currently-trashed ancestors/descendants of [id],
  /// but only [id] itself is projected here — mirroring
  /// `TicketsCubit.trashTickets`' existing scope simplification for the
  /// symmetric trash-side case. Emits [TrashError] if the repository
  /// call throws.
  Future<void> restore(String id) async {
    try {
      await _repository.restoreTicket(id);
      final restored = await _repository.getTicketById(id);
      if (restored != null) {
        unawaited(_triggerGitProjection(restored, 'restored'));
      }
      await load();
    } catch (e) {
      emit(TrashError(e.toString()));
    }
  }

  /// Permanently deletes the ticket with internal id [id] via
  /// [TicketRepository.permanentlyDeleteTicket], then reloads the trash
  /// list. Emits [TrashError] if the repository call throws.
  Future<void> permanentlyDelete(String id) async {
    try {
      await _repository.permanentlyDeleteTicket(id);
      await load();
    } catch (e) {
      emit(TrashError(e.toString()));
    }
  }

  /// Permanently deletes every currently trashed ticket via
  /// [TicketRepository.emptyTrash], then reloads the trash list. Emits
  /// [TrashError] if the repository call throws.
  Future<void> emptyTrash() async {
    try {
      await _repository.emptyTrash();
      await load();
    } catch (e) {
      emit(TrashError(e.toString()));
    }
  }

  /// Permanently deletes every trashed ticket older than
  /// [purgeAgeThreshold] via [TicketRepository.purgeTrashOlderThan],
  /// then reloads the trash list. Emits [TrashError] if the repository
  /// call throws.
  Future<void> purgeOldTrash() async {
    try {
      await _repository.purgeTrashOlderThan(purgeAgeThreshold);
      await load();
    } catch (e) {
      emit(TrashError(e.toString()));
    }
  }

  /// Projects [ticket] to its Markdown file and commits it, labelled
  /// [eventLabel]. No-ops if no [_gitProjector]/[_projectRootPath] was
  /// provided (see the constructor's dartdoc) — desktop-only in
  /// practice, since `WorkspaceShell` only supplies these on desktop.
  Future<void> _triggerGitProjection(Ticket ticket, String eventLabel) async {
    final projector = _gitProjector;
    final rootPath = _projectRootPath;
    if (projector == null || rootPath == null) return;
    await projector.project(ticket, rootPath, eventLabel);
  }
}
