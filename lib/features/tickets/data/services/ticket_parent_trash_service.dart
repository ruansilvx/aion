// data/services/ticket_parent_trash_service.dart — TicketParentTrashService (data layer).

import 'dart:async';

import 'package:aion/core/markdown/ticket_markdown_template.dart';
import 'package:aion/features/tickets/data/services/ticket_git_projector.dart';
import 'package:aion/features/tickets/data/services/ticket_parent_change_result.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_rollup_recomputer.dart';

/// Shared parentId-reparent and trash/restore domain logic — cycle-
/// prevention and type-compatibility validation for reparenting, and the
/// git-projection + rollup-recompute side effects that accompany a
/// trash/restore — used by both `TicketsCubit`/`TrashCubit` (in-app
/// edits, which wrap this in their own UI-state emission) and
/// `TicketMarkdownReconciler`/`TicketRepairService` (external file edits
/// and repair, which have no UI state to emit). Follows the same shared-
/// plain-service pattern as `PageWikilinkIndexer` for the identical
/// dual-caller shape, rather than pushing this logic down into
/// `TicketRepository` — see
/// `aion-arch/ideas/reconciler-applies-hand-edited-parentid-deletedat.md`.
class TicketParentTrashService {
  /// Creates a [TicketParentTrashService] backed by [_repository].
  /// [gitProjector]/[projectRootPath] are optional, matching
  /// `TicketRollupRecomputer`'s identical optional-dependency pattern —
  /// `null` for either simply no-ops the git-projection side effect.
  TicketParentTrashService(
    this._repository, {
    TicketGitProjector? gitProjector,
    String? projectRootPath,
  }) {
    _gitProjector = gitProjector;
    _projectRootPath = projectRootPath;
    _rollupRecomputer = TicketRollupRecomputer(
      _repository,
      gitProjector: gitProjector,
      projectRootPath: projectRootPath,
    );
  }

  final TicketRepository _repository;
  late final TicketGitProjector? _gitProjector;
  late final String? _projectRootPath;

  /// Shared estimate/timeSpent rollup-recompute walk — see
  /// [TicketRollupRecomputer]. Wired to the same [_repository]/
  /// [_gitProjector]/[_projectRootPath] this service already holds.
  late final TicketRollupRecomputer _rollupRecomputer;

  /// Reassigns [ticket]'s parent to [newParentId] (`null` clears it).
  /// Validation is the same set of checks `TicketsCubit
  /// .updateTicketParent` used to perform inline before delegating here:
  /// self-parenting, always-root types
  /// ([TicketTypeHierarchy.isAlwaysRoot]), an Inbox-spawned chat (a
  /// [TicketType.chat] with non-null [Ticket.inboxPurpose]), a cycle
  /// (walking [ticket]'s descendants), and structural type-compatibility
  /// ([TicketTypeHierarchy.canParent]). On success, persists via
  /// [TicketRepository.updateTicketParent], fires a fire-and-forget
  /// [TicketRollupRecomputer.recompute] seeded from
  /// `{ticket.id, ?oldParentId}` (mirroring `TicketsCubit
  /// .updateTicketParent`'s pre-existing rollup trigger), and returns
  /// [ParentChangeSuccess] with the refreshed ticket. On any rejection,
  /// returns [ParentChangeRejected] without writing anything.
  Future<ParentChangeResult> changeParent(
    Ticket ticket,
    String? newParentId,
  ) async {
    final oldParentId = ticket.parentId;
    if (newParentId != null) {
      if (newParentId == ticket.id) return const ParentChangeRejected();
      if (ticket.type.isAlwaysRoot) return const ParentChangeRejected();
      if (ticket.type == TicketType.chat && ticket.inboxPurpose != null) {
        return const ParentChangeRejected();
      }
      final all = await _repository.getAllTickets();
      if (_descendantIds(ticket.id, all).contains(newParentId)) {
        return const ParentChangeRejected();
      }
      final candidateParent = await _repository.getTicketById(newParentId);
      if (candidateParent == null ||
          !candidateParent.type.canParent(ticket.type)) {
        return const ParentChangeRejected();
      }
    }

    await _repository.updateTicketParent(ticket.id, newParentId);
    final refreshed = await _repository.getTicketById(ticket.id);
    // The rollup recompute fires regardless of whether [refreshed] came
    // back non-null, matching `TicketsCubit.updateTicketParent`'s
    // original unconditional trigger — the write itself already
    // succeeded above, so the ancestor chain still needs recomputing
    // even in the near-impossible case where an immediate re-fetch of
    // the ticket that was just written finds nothing.
    unawaited(
      _rollupRecomputer.recompute(
        {ticket.id, ?oldParentId},
        'rollup updated',
      ),
    );
    if (refreshed == null) return const ParentChangeRejected();
    return ParentChangeSuccess(refreshed);
  }

  /// Trashes the ticket with internal id [id] via
  /// [TicketRepository.trashTicket] — which already carries the full
  /// descendant-cascade logic, so no validation happens here beyond what
  /// the repository itself already guards (throwing if [id] doesn't
  /// exist — propagated to the caller, same as before this logic was
  /// factored out). Mirrors `TicketsCubit`'s previous
  /// `_trashGitSideEffects`: projects the trashed ticket to git
  /// (`'trashed'`) and fires a rollup recompute seeded from the ticket's
  /// pre-trash `parentId`. Returns the trashed [Ticket], or `null` only
  /// in the (essentially unreachable) case where the post-write re-fetch
  /// itself returns nothing.
  Future<Ticket?> trash(String id) async {
    final preTrash = await _repository.getTicketById(id);
    await _repository.trashTicket(id);
    final trashed = await _repository.getTicketById(id);
    if (trashed != null) await _triggerGitProjection(trashed, 'trashed');
    unawaited(
      _rollupRecomputer.recompute({?preTrash?.parentId}, 'rollup updated'),
    );
    return trashed;
  }

  /// Restores the ticket with internal id [id] via
  /// [TicketRepository.restoreTicket] — which already revives trashed
  /// ancestors/descendants (and, like [trash], throws if [id] doesn't
  /// exist — propagated to the caller). Mirrors `TrashCubit`'s previous
  /// `_restoreGitSideEffects`: projects the restored ticket to git
  /// (`'restored'`) and fires a rollup recompute seeded from its
  /// (now-restored) `parentId`. Returns the restored [Ticket], or `null`
  /// only in the (essentially unreachable) case where the post-write
  /// re-fetch itself returns nothing.
  Future<Ticket?> restore(String id) async {
    final existing = await _repository.getTicketById(id);
    await _repository.restoreTicket(id);
    final restored = await _repository.getTicketById(id);
    if (restored != null) await _triggerGitProjection(restored, 'restored');
    unawaited(
      _rollupRecomputer.recompute({?existing?.parentId}, 'rollup updated'),
    );
    return restored;
  }

  /// Applies any `parentId`/`deletedAt` transition present in [fields]
  /// (a `TicketMarkdownParseResult.ParsedOk.fields`/`ParsedPartial
  /// .validFields` map, keyed by [TicketMarkdownTemplate] field name)
  /// against [ticket] — the single entry point shared by
  /// `TicketMarkdownReconciler` (the live watcher path) and
  /// `TicketRepairService.reformat` (the explicit repair action), so
  /// both apply identical parentId/deletedAt semantics instead of each
  /// re-deriving the field-presence/transition-direction logic
  /// separately. A key absent from [fields], or present but equal to
  /// [ticket]'s current value, is a no-op for that field. A changed but
  /// still non-null `deletedAt` (re-trashing an already-trashed ticket
  /// with a different timestamp) has no corresponding domain operation
  /// and is also a no-op. Returns `false` if a present, *changed*
  /// `parentId` or `deletedAt` was rejected — `true` otherwise
  /// (including when neither field has a relevant transition at all).
  Future<bool> applyFromParsedFields(
    Ticket ticket,
    Map<String, Object?> fields,
  ) async {
    var ok = true;
    if (fields.containsKey(TicketMarkdownTemplate.parentId)) {
      final newParentId = fields[TicketMarkdownTemplate.parentId] as String?;
      if (newParentId != ticket.parentId) {
        final result = await changeParent(ticket, newParentId);
        if (result is ParentChangeRejected) ok = false;
      }
    }
    if (fields.containsKey(TicketMarkdownTemplate.deletedAt)) {
      final newDeletedAt =
          fields[TicketMarkdownTemplate.deletedAt] as DateTime?;
      if (newDeletedAt != null && ticket.deletedAt == null) {
        if (await trash(ticket.id) == null) ok = false;
      } else if (newDeletedAt == null && ticket.deletedAt != null) {
        if (await restore(ticket.id) == null) ok = false;
      }
    }
    return ok;
  }

  /// Projects [ticket] to its Markdown file under the active project's
  /// git repository, labelling the commit [eventLabel] — a no-op when
  /// either [_gitProjector] or [_projectRootPath] is `null` (mobile/web,
  /// or no resolved project directory).
  Future<void> _triggerGitProjection(Ticket ticket, String eventLabel) async {
    final projector = _gitProjector;
    final rootPath = _projectRootPath;
    if (projector == null || rootPath == null) return;
    await projector.project(ticket, rootPath, eventLabel);
  }

  /// Same descendant-walk as `TicketsCubit._descendantIds` — duplicated
  /// rather than shared, since `TicketsCubit`'s copy also backs
  /// `getValidParentCandidates` (a picker-list query untouched by this
  /// change) and extracting a shared helper for one small pure function
  /// isn't worth the indirection.
  Set<String> _descendantIds(String rootId, List<Ticket> all) {
    final childrenByParent = <String, List<Ticket>>{};
    for (final t in all) {
      final p = t.parentId;
      if (p != null) childrenByParent.putIfAbsent(p, () => []).add(t);
    }
    final result = <String>{};
    void walk(String id) {
      for (final child in childrenByParent[id] ?? const []) {
        if (result.add(child.id)) walk(child.id);
      }
    }

    walk(rootId);
    return result;
  }
}
