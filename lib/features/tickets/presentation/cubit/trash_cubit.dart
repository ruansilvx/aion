// presentation/cubit/trash_cubit.dart — TrashCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/data/services/ticket_parent_trash_service.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_sort_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/domain/utils/ticket_sort_comparator.dart';
import 'package:aion/features/tickets/presentation/cubit/trash_state.dart';

/// Loads and mutates the trash (`/tickets/trash`) via [TicketRepository].
/// Screen-scoped — provided per visit to the Trash screen, not at the app
/// root.
class TrashCubit extends Cubit<TrashState> {
  /// Creates a [TrashCubit] backed by [_repository]. [gitProjector] and
  /// [projectRootPath] are optional — when either is `null` (the default, and
  /// every existing call site/test), [_parentTrashService]'s git-projection
  /// side effect simply no-ops, matching `TicketsCubit`'s identical
  /// optional-dependency pattern for the same desktop-only feature. Real usage
  /// (`app_router.dart`) supplies both whenever the active project has a
  /// `rootPath`. [sortRepository]/[projectId] follow the same
  /// optional-dependency pattern once more — `null` for either makes
  /// [_resolveSort] fall back to `createdAt` descending with no persisted sort
  /// applied; real usage (`app_router.dart`) always supplies both, mirroring
  /// `TicketsCubit`'s own `sortRepository`/`projectId`. Added for `AIO-2371`.
  TrashCubit(
    this._repository, {
    TicketGitProjector? gitProjector,
    String? projectRootPath,
    TicketListSortRepository? sortRepository,
    String? projectId,
  }) : super(const TrashLoading()) {
    _sortRepository = sortRepository;
    _projectId = projectId;
    _parentTrashService = TicketParentTrashService(
      _repository,
      gitProjector: gitProjector,
      projectRootPath: projectRootPath,
    );
  }

  final TicketRepository _repository;
  late final TicketListSortRepository? _sortRepository;
  late final String? _projectId;

  /// Shared parentId-reparent and trash/restore domain logic — see
  /// [TicketParentTrashService]. Wired to the same [_repository] and the
  /// constructor's `gitProjector`/`projectRootPath`, so [restore]
  /// delegates to one instance instead of duplicating cascade logic that
  /// `TicketMarkdownReconciler`/`TicketRepairService` also need.
  late final TicketParentTrashService _parentTrashService;

  /// How old a trashed ticket must be before "Purge old" will remove it.
  /// Fixed, not user-configurable (see proposal.md's Non-goals).
  static const Duration purgeAgeThreshold = Duration(days: 30);

  /// Fetches every currently trashed ticket, then reduces the flat list to
  /// roots + per-root descendant counts (see [TrashLoaded]'s dartdoc) and
  /// counts how many are old enough for [purgeOldTrash] to remove, before
  /// emitting. Sorts `roots` per this project's persisted sort (see
  /// [_resolveSort]) so Trash's ticket order matches the ticket list's — see
  /// `AIO-2371` §4. Emits [TrashLoading] then [TrashLoaded] on success, or
  /// [TrashError] if the repository call throws.
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
          .where((t) => t.parentId == null || !trashedIds.contains(t.parentId))
          .toList();
      final sort = await _resolveSort();
      roots.sort(ticketSortComparator(sort));
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

  /// This project's persisted [TicketListSort] (via [_sortRepository]/
  /// [_projectId]), falling back to `createdAt` descending — Trash has no
  /// search query to score [TicketSortField.relevance] against, so a
  /// persisted `relevance` selection (made from the ticket list, where
  /// it's meaningful) resolves the same way `TicketsCubit`'s own implicit
  /// default does when no query is active. `null`/no-dependency (see the
  /// constructor's dartdoc) falls back the same way.
  Future<TicketListSort> _resolveSort() async {
    final repo = _sortRepository;
    final projectId = _projectId;
    const fallback = TicketListSort(
      field: TicketSortField.createdAt,
      direction: TicketSortDirection.descending,
    );
    if (repo == null || projectId == null) return fallback;
    final persisted = await repo.getSort(projectId);
    if (persisted == null || persisted.field == TicketSortField.relevance) {
      return fallback;
    }
    return persisted;
  }

  /// Counts every ticket reachable from [id] by walking [childrenByParent]
  /// (an adjacency map built once per [load] call from the full trashed
  /// set), recursively.
  int _countDescendants(String id, Map<String, List<Ticket>> childrenByParent) {
    var count = 0;
    for (final child in childrenByParent[id] ?? const []) {
      count += 1 + _countDescendants(child.id, childrenByParent);
    }
    return count;
  }

  /// Restores the ticket with internal id [id] via
  /// [TicketParentTrashService.restore] (which carries
  /// [TicketRepository.restoreTicket]'s ancestor/descendant-revival
  /// cascade write plus the same git-projection/rollup-recompute side
  /// effects this method used to trigger inline — see
  /// [_parentTrashService]), then reloads the trash list. Emits
  /// [TrashError] if the repository call throws.
  Future<void> restore(String id) async {
    try {
      await _parentTrashService.restore(id);
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

  /// Restores every ticket in [ids] via [TicketParentTrashService.restore]
  /// — looped once per id, not a batched repository call — then reloads
  /// the trash list. Looping is correctness-equivalent to a real batch
  /// call here: [TrashLoaded] only ever lists trashed *root* tickets (see
  /// its own dartdoc), so every id in [ids] already has a fully-live
  /// ancestor chain, meaning [restore]'s ancestor-revival step is always
  /// a no-op for these calls, and two selected roots' subtrees can never
  /// overlap. Restore is also non-destructive and safely retryable, so
  /// there is no atomicity requirement pushing this toward a single
  /// transaction the way [permanentlyDeleteTickets] needs one — see
  /// proposal.md's "Implementation split" section for the full rationale.
  /// Returns `true` on success, `false` (after emitting [TrashError]) on
  /// failure.
  Future<bool> restoreTickets(List<String> ids) async {
    try {
      for (final id in ids) {
        await _parentTrashService.restore(id);
      }
      await load();
      return true;
    } catch (e) {
      emit(TrashError(e.toString()));
      return false;
    }
  }

  /// Permanently deletes every ticket in [ids] — and each one's full
  /// structural subtree — via [TicketRepository.permanentlyDeleteTickets]
  /// (a single batched, transactional repository call — irreversible, so
  /// unlike [restoreTickets] this needs all-or-nothing atomicity rather
  /// than a loop over the single-ticket path), then reloads the trash
  /// list. Returns `true` on success, `false` (after emitting
  /// [TrashError]) on failure.
  Future<bool> permanentlyDeleteTickets(List<String> ids) async {
    try {
      await _repository.permanentlyDeleteTickets(ids);
      await load();
      return true;
    } catch (e) {
      emit(TrashError(e.toString()));
      return false;
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
}
