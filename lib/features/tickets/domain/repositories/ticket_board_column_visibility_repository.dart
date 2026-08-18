// domain/repositories/ticket_board_column_visibility_repository.dart — TicketBoardColumnVisibilityRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket_board_column_visibility.dart';

/// Per-project persistence for the board's [TicketBoardColumnVisibility]
/// selection. Implemented by the data layer
/// ([SharedPrefsTicketBoardColumnVisibilityRepository]); UI and Cubit
/// code depend only on this interface, never on a concrete storage
/// mechanism.
///
/// A sibling of `TicketListFilterRepository` — plain reads/writes, no
/// validation, same shape as `ExecutionContextCapRepository`. See
/// `aion-arch/changes/list-board-view-and-column-visibility/design.md`
/// §2.4.
abstract interface class TicketBoardColumnVisibilityRepository {
  /// The persisted [TicketBoardColumnVisibility] for [projectId], or a
  /// default-empty one (nothing hidden) if nothing has been saved yet.
  Future<TicketBoardColumnVisibility> getHiddenColumns(String projectId);

  /// Persists [visibility] as [projectId]'s hidden-column selection,
  /// overwriting whatever was saved before.
  Future<void> setHiddenColumns(
    String projectId,
    TicketBoardColumnVisibility visibility,
  );
}
