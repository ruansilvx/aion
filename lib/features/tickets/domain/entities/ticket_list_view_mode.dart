// domain/entities/ticket_list_view_mode.dart — TicketListViewMode enum (domain layer).

/// Which rendering `TicketsListScreen` uses for its currently loaded ticket
/// list. Promoted from that screen's former private, widget-local
/// `_TicketViewMode` enum to a shared domain type, since the selection is
/// now read/written from three places (`TicketsCubit`,
/// `TicketListViewModeRepository`, and the screen itself) instead of one.
/// See `aion-arch/changes/list-board-view-and-column-visibility/design.md`
/// §2.1.
enum TicketListViewMode {
  /// The flat, chronologically-sortable `ListView` of every ticket.
  list,

  /// `TicketBoardView`, grouped by status and filtered to task/story
  /// tickets.
  board,
}
