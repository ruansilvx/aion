// domain/repositories/ticket_list_view_mode_repository.dart — TicketListViewModeRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket_list_view_mode.dart';

/// Per-project persistence for the ticket list's [TicketListViewMode]
/// selection. Implemented by the data layer
/// ([SharedPrefsTicketListViewModeRepository]); UI and Cubit code depend
/// only on this interface, never on a concrete storage mechanism.
///
/// A sibling of `TicketListSortRepository`, same "unset means no explicit
/// choice yet" semantics: an unset value means the fixed
/// [TicketListViewMode.board] starting default still applies, not `null`
/// treated as an arbitrary fallback. See
/// `aion-arch/changes/list-board-view-and-column-visibility/design.md`
/// §2.3.
abstract interface class TicketListViewModeRepository {
  /// The persisted explicit view mode for [projectId], or `null` if the
  /// user has never explicitly switched away from the fixed
  /// [TicketListViewMode.board] starting default in this project.
  Future<TicketListViewMode?> getViewMode(String projectId);

  /// Persists [mode] as [projectId]'s explicit choice, overwriting
  /// whatever was saved before.
  Future<void> setViewMode(String projectId, TicketListViewMode mode);
}
