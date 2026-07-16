// presentation/cubit/ticket_selection_cubit.dart — TicketSelectionCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/tickets/presentation/cubit/ticket_selection_state.dart';

/// Drives `TicketsListScreen`'s selection-mode UI. Screen-scoped — a
/// fresh instance is created per visit to `/tickets` (provided via
/// `BlocProvider` in `app_router.dart`, not at the app root), so
/// selection never persists across navigating away and back. Plain
/// id-set toggling only — no relationship/invariant-checking logic, since
/// trashing a selection always cascades to structural children
/// unconditionally (see `TicketsCubit.trashTickets`), so there is nothing
/// a selection could be "invalid" for.
class TicketSelectionCubit extends Cubit<TicketSelectionState> {
  /// Creates a [TicketSelectionCubit], starting inactive with nothing
  /// selected.
  TicketSelectionCubit() : super(const TicketSelectionState.initial());

  /// Enters selection mode with nothing selected yet.
  void enter() {
    emit(const TicketSelectionState(isActive: true, selectedIds: {}));
  }

  /// Exits selection mode and clears the selection. Called both by the
  /// selection bar's Cancel action and after a bulk trash completes.
  void clear() {
    emit(const TicketSelectionState.initial());
  }

  /// Toggles whether [id] is selected. No-ops if selection mode isn't
  /// active.
  void toggle(String id) {
    if (!state.isActive) return;
    final next = {...state.selectedIds};
    if (!next.remove(id)) next.add(id);
    emit(TicketSelectionState(isActive: true, selectedIds: next));
  }

  /// Selects every id in [ids] (the caller's currently visible/filtered
  /// ticket list) if not all of them are already selected; otherwise
  /// deselects everything. Powers the selection bar's "Select all" /
  /// "Deselect all" toggle button.
  void selectAll(List<String> ids) {
    final allSelected = ids.isNotEmpty && ids.every(state.selectedIds.contains);
    emit(
      TicketSelectionState(
        isActive: true,
        selectedIds: allSelected ? const {} : ids.toSet(),
      ),
    );
  }
}
