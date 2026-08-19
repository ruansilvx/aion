// presentation/cubit/workflow_config_cubit.dart — WorkflowConfigCubit business logic (presentation layer).

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';
import 'package:aion/features/tickets/domain/repositories/sdd_stage_config_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/domain/repositories/workflow_status_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/workflow_config_state.dart';

/// Owns [WorkflowStatus] CRUD/reorder and the project's `SddStage`
/// settings, enforcing the invariants `TicketsCubit` itself never checks —
/// domain/invariant logic lives in Cubits, not repositories, per this
/// project's Cubit-vs-repository split. Backs `WorkflowStatusSettingsScreen`.
/// See `aion-arch/changes/configurable-ticket-workflow/design.md` §4.
///
/// Two enforced invariants, both applied within the shared-base scope
/// only (a per-type extension status never holds a role, so neither
/// invariant is ever checked against one):
/// - **Name uniqueness within scope** — a status's [WorkflowStatus.name]
///   must be unique among the shared-base set, and unique among its own
///   [WorkflowStatus.ticketType]'s extensions merged with the shared base
///   (the effective view a type scope actually renders). Violated by
///   [createStatus]/[updateStatus].
/// - **Every [WorkflowStatusRole] always resolves to exactly one
///   shared-base status.** Assigning a role to status B *moves* it off
///   whatever status A currently held it (silently, since a role is
///   single-holder by construction) — see [updateStatus]. What's
///   rejected is an update/delete that would leave a role with *no*
///   holder at all: [deleteStatus]ing the sole holder, or [updateStatus]
///   clearing the sole holder's own role to `null` without another
///   status simultaneously taking it over.
///
/// [deleteStatus] additionally rejects deleting a status any live ticket
/// currently sits at — Phase 1 has no migration story for reassigning a
/// deleted status's tickets (see proposal.md's Non-goals).
class WorkflowConfigCubit extends Cubit<WorkflowConfigState> {
  /// Creates a [WorkflowConfigCubit]. [_ticketRepository] is consulted
  /// only by [deleteStatus]'s in-use check — a live-ticket count query,
  /// not a write path — so it's a narrower dependency than
  /// `WorkflowStatusRepository`/`SddStageConfigRepository`.
  WorkflowConfigCubit(
    this._statusRepository,
    this._sddStageConfigRepository,
    this._ticketRepository,
  ) : super(const WorkflowConfigInitial());

  final WorkflowStatusRepository _statusRepository;
  final SddStageConfigRepository _sddStageConfigRepository;
  final TicketRepository _ticketRepository;

  /// Loads every configured [WorkflowStatus] plus the project's `SddStage`
  /// settings and emits [WorkflowConfigLoaded].
  Future<void> load() async {
    final statuses = await _statusRepository.getAll();
    final designStagesEnabled = await _sddStageConfigRepository
        .getDesignStagesEnabled();
    final overrides = await _loadStageDisplayNameOverrides();
    if (isClosed) return;
    emit(
      WorkflowConfigLoaded(
        statuses: statuses,
        designStagesEnabled: designStagesEnabled,
        stageDisplayNameOverrides: overrides,
      ),
    );
  }

  /// Creates [status]. Rejects (emits [WorkflowConfigError], preserving
  /// the current list) if [status.name] isn't unique in its scope. A
  /// non-`null` [status.role] moves that role off whichever other
  /// shared-base status currently holds it (see this class's dartdoc) —
  /// never rejected on create, since create only ever adds a holder, it
  /// can't empty one.
  Future<void> createStatus(WorkflowStatus status) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;

    if (!_isNameUniqueInScope(loaded.statuses, status)) {
      _emitDuplicateNameError(status, loaded);
      return;
    }

    await _statusRepository.create(status);
    if (status.role != null) {
      await _clearRoleFromOtherHolders(
        excludingId: status.id,
        role: status.role!,
        allStatuses: loaded.statuses,
      );
    }
    await load();
  }

  /// Updates [status] over its existing row (matched by
  /// [WorkflowStatus.id]). Rejects if [status.name] isn't unique in its
  /// scope, or if this update would clear the sole holder of a role to
  /// `null` (see this class's dartdoc for the "moves vs. empties"
  /// distinction) — the caller (`RoleDropdown`) keeps its prior value and
  /// [WorkflowConfigError.message] explains why.
  Future<void> updateStatus(WorkflowStatus status) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;

    final existing = loaded.statuses.where((s) => s.id == status.id).firstOrNull;
    if (existing == null) {
      _emitDuplicateNameError(status, loaded, message: 'That status no longer exists.');
      return;
    }

    if (!_isNameUniqueInScope(loaded.statuses, status)) {
      _emitDuplicateNameError(status, loaded);
      return;
    }

    if (existing.role != null && status.role != existing.role) {
      // This status is the sole holder of `existing.role` (role is always
      // single-holder). Clearing it to null, or away to a different role,
      // would leave `existing.role` with no holder at all.
      _emit(
        WorkflowConfigError(
          message:
              'Each Base role must always have exactly one holder. '
              'Assign the ${_roleLabel(existing.role!)} role to another '
              'status before removing this one.',
          previous: loaded,
        ),
      );
      return;
    }

    await _statusRepository.update(status);
    if (status.role != null && status.role != existing.role) {
      await _clearRoleFromOtherHolders(
        excludingId: status.id,
        role: status.role!,
        allStatuses: loaded.statuses,
      );
    }
    await load();
  }

  /// Deletes the status with id [id]. Rejects if it's the sole holder of
  /// a role, or if it's currently in use by ≥1 live ticket.
  Future<void> deleteStatus(String id) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;

    final existing = loaded.statuses.where((s) => s.id == id).firstOrNull;
    if (existing == null) return;

    if (existing.role != null) {
      _emit(
        WorkflowConfigError(
          message:
              'Each Base role must always have exactly one holder. '
              'Assign the ${_roleLabel(existing.role!)} role to another '
              'status before deleting this one.',
          previous: loaded,
        ),
      );
      return;
    }

    final inUseCount = await _countTicketsUsingStatus(existing.name);
    if (inUseCount > 0) {
      _emit(
        WorkflowConfigError(
          message:
              'In use by $inUseCount ${inUseCount == 1 ? 'ticket' : 'tickets'} '
              '— reassign them before deleting this status.',
          previous: loaded,
        ),
      );
      return;
    }

    await _statusRepository.delete(id);
    await load();
  }

  /// Persists a new [WorkflowStatus.sortOrder] for every id in
  /// [idsInOrder], assigning each its list index. Reorder can never
  /// violate either invariant (name/role are untouched), so it's never
  /// rejected.
  Future<void> reorderStatuses(List<String> idsInOrder) async {
    if (_requireLoaded() == null) return;
    await _statusRepository.reorder(idsInOrder);
    await load();
  }

  /// Persists [enabled] as the project's design-stages-required setting.
  /// Never rejected — toggling can't violate either invariant.
  Future<void> setDesignStagesEnabled(bool enabled) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;
    await _sddStageConfigRepository.setDesignStagesEnabled(enabled);
    await load();
  }

  /// Persists [name] as [stage]'s display-name override — `null` clears
  /// it, reverting to [stage]'s own hardcoded default name. Never
  /// rejected: a blank rename field falls back to the fixed stage name,
  /// so there is no invalid input (Component Spec §9).
  Future<void> setStageDisplayNameOverride(SddStage stage, String? name) async {
    final loaded = _requireLoaded();
    if (loaded == null) return;
    await _sddStageConfigRepository.setDisplayNameOverride(stage, name);
    await load();
  }

  /// Returns the current [WorkflowConfigLoaded] state, or `null` (after
  /// emitting a defensive [WorkflowConfigError]-free no-op) if [load]
  /// hasn't resolved yet or the last state was itself an error — every
  /// mutating method requires a known-good baseline to validate against.
  WorkflowConfigLoaded? _requireLoaded() {
    final current = state;
    return switch (current) {
      WorkflowConfigLoaded() => current,
      WorkflowConfigError(:final previous) => previous,
      WorkflowConfigInitial() => null,
    };
  }

  void _emit(WorkflowConfigState next) {
    if (isClosed) return;
    emit(next);
  }

  void _emitDuplicateNameError(
    WorkflowStatus status,
    WorkflowConfigLoaded loaded, {
    String? message,
  }) {
    _emit(
      WorkflowConfigError(
        message:
            message ??
            'A status named "${status.displayName}" already exists in this scope.',
        previous: loaded,
      ),
    );
  }

  /// Whether [candidate.name] is unique within its effective scope: the
  /// shared-base set, plus (when [candidate] is itself a per-type
  /// extension) that same [WorkflowStatus.ticketType]'s other extensions
  /// — the merged view a type scope actually renders, per this class's
  /// dartdoc.
  bool _isNameUniqueInScope(
    List<WorkflowStatus> allStatuses,
    WorkflowStatus candidate,
  ) {
    final scoped = allStatuses.where(
      (s) =>
          s.id != candidate.id &&
          (s.ticketType == null || s.ticketType == candidate.ticketType),
    );
    return !scoped.any((s) => s.name == candidate.name);
  }

  /// Clears [role] from whichever other shared-base status in
  /// [allStatuses] currently holds it (there is at most one, by
  /// invariant), so [excludingId] becomes its sole holder. A no-op if no
  /// other status currently holds [role].
  Future<void> _clearRoleFromOtherHolders({
    required String excludingId,
    required WorkflowStatusRole role,
    required List<WorkflowStatus> allStatuses,
  }) async {
    final previousHolder = allStatuses
        .where((s) => s.id != excludingId && s.role == role)
        .firstOrNull;
    if (previousHolder == null) return;
    await _statusRepository.update(
      previousHolder.copyWith(role: () => null),
    );
  }

  /// Counts live tickets currently at the status named [statusName].
  Future<int> _countTicketsUsingStatus(String statusName) async {
    final tickets = await _ticketRepository.getAllTickets();
    return tickets.where((t) => t.status == statusName).length;
  }

  /// Loads the persisted display-name override for every [SddStage],
  /// omitting stages with none set.
  Future<Map<SddStage, String>> _loadStageDisplayNameOverrides() async {
    final overrides = <SddStage, String>{};
    for (final stage in SddStage.values) {
      final override = await _sddStageConfigRepository.getDisplayNameOverride(
        stage,
      );
      if (override != null) overrides[stage] = override;
    }
    return overrides;
  }

  /// A human-readable label for [role], used in rejection messages.
  String _roleLabel(WorkflowStatusRole role) => switch (role) {
    WorkflowStatusRole.executionTrigger => 'Execution Trigger',
    WorkflowStatusRole.reviewReady => 'Review Ready',
    WorkflowStatusRole.done => 'Done',
  };
}
