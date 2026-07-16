// presentation/cubit/ticket_selection_state.dart — TicketSelectionState (presentation layer).

import 'package:equatable/equatable.dart';

/// Selection-mode state for `TicketsListScreen`'s bulk-delete flow.
/// `isActive == false` means the list/board renders normally (no
/// checkboxes, rows navigate on tap); `isActive == true` means checkboxes
/// are shown and [selectedIds] tracks which tickets are checked.
class TicketSelectionState extends Equatable {
  /// Creates a [TicketSelectionState].
  const TicketSelectionState({required this.isActive, required this.selectedIds});

  /// The inactive, no-selection starting state.
  const TicketSelectionState.initial() : isActive = false, selectedIds = const {};

  /// Whether selection mode is currently active.
  final bool isActive;

  /// Ids of the currently selected tickets. Always empty when [isActive]
  /// is `false`.
  final Set<String> selectedIds;

  @override
  List<Object?> get props => [isActive, selectedIds];
}
