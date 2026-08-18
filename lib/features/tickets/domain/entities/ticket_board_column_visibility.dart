// domain/entities/ticket_board_column_visibility.dart — TicketBoardColumnVisibility entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/enums/ticket_status.dart';

/// The board's per-project column visibility selection: which
/// [TicketStatus] columns the user has hidden. A plain value holder,
/// mirroring [TicketListFilters](ticket_list_filters.dart) — exists so
/// `TicketBoardColumnVisibilityRepository` has one type to read/write
/// instead of a bare `Set<TicketStatus>`, and so `TicketsCubit` has one
/// type to pass to/from it. See
/// `aion-arch/changes/list-board-view-and-column-visibility/design.md`
/// §2.2.
class TicketBoardColumnVisibility extends Equatable {
  /// Creates a [TicketBoardColumnVisibility]. [hiddenStatuses] defaults to
  /// an empty set, meaning nothing hidden — all six columns visible.
  const TicketBoardColumnVisibility({this.hiddenStatuses = const {}});

  /// Statuses whose board column is currently hidden. An empty set (the
  /// default) means "nothing hidden — all six columns visible," the same
  /// "empty = no constraint" convention
  /// [TicketListFilters](ticket_list_filters.dart) already uses for its
  /// three fields.
  final Set<TicketStatus> hiddenStatuses;

  @override
  List<Object?> get props => [hiddenStatuses];
}
