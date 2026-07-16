// presentation/cubit/trash_cubit.dart — TrashCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/trash_state.dart';

/// Loads and mutates the trash (`/tickets/trash`) via [TicketRepository].
/// Screen-scoped — provided per visit to the Trash screen, not at the app
/// root.
class TrashCubit extends Cubit<TrashState> {
  /// Creates a [TrashCubit] backed by [_repository].
  TrashCubit(this._repository) : super(const TrashLoading());

  final TicketRepository _repository;

  /// Fetches every currently trashed ticket, then reduces the flat list
  /// to roots + per-root descendant counts (see [TrashLoaded]'s dartdoc)
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

      emit(TrashLoaded(roots, descendantCounts));
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
  /// [TicketRepository.restoreTicket], then reloads the trash list.
  /// Emits [TrashError] if the repository call throws.
  Future<void> restore(String id) async {
    try {
      await _repository.restoreTicket(id);
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
}
