// domain/entities/ticket_board_column_visibility.dart — TicketBoardColumnVisibility entity (domain layer).

import 'package:equatable/equatable.dart';

/// The board's per-project column visibility selection: which project-defined
/// status columns the user has hidden. A plain value holder, mirroring
/// [TicketListFilters](ticket_list_filters.dart) — exists so
/// `TicketBoardColumnVisibilityRepository` has one type to read/write instead
/// of a bare `Set<String>`, and so `TicketsCubit` has one type to pass to/from
/// it. See `AIO-1069` §2.2.
class TicketBoardColumnVisibility extends Equatable {
  /// Creates a [TicketBoardColumnVisibility]. [hiddenStatuses] defaults to
  /// an empty set, meaning nothing hidden — every configured column
  /// visible.
  const TicketBoardColumnVisibility({this.hiddenStatuses = const {}});

  /// Status names whose board column is currently hidden. An empty set (the
  /// default) means "nothing hidden — every column visible," the same "empty =
  /// no constraint" convention [TicketListFilters](ticket_list_filters.dart)
  /// already uses for its three fields. Was `Set<TicketStatus>` before
  /// `AIO-549` — a status is now a project-defined name, not a fixed enum.
  final Set<String> hiddenStatuses;

  @override
  List<Object?> get props => [hiddenStatuses];
}
