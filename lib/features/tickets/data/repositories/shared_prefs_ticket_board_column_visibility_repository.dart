// data/repositories/shared_prefs_ticket_board_column_visibility_repository.dart — SharedPrefsTicketBoardColumnVisibilityRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/domain/entities/ticket_board_column_visibility.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_board_column_visibility_repository.dart';

/// `shared_preferences`-backed implementation of
/// [TicketBoardColumnVisibilityRepository]. Stores a project's
/// [TicketBoardColumnVisibility] as one project-id-prefixed string-list
/// key (`ticket_board_column_visibility.<projectId>.hiddenStatuses`),
/// each entry the hidden status's `.name` — mirrors
/// `SharedPrefsTicketListFilterRepository`'s string-list convention. A
/// stale stored name (e.g. an enum member later removed) is silently
/// dropped on read, not surfaced as an error.
class SharedPrefsTicketBoardColumnVisibilityRepository
    implements TicketBoardColumnVisibilityRepository {
  String _key(String projectId) =>
      'ticket_board_column_visibility.$projectId.hiddenStatuses';

  @override
  Future<TicketBoardColumnVisibility> getHiddenColumns(
    String projectId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_key(projectId)) ?? const [];
    final hidden = names
        .map((n) => TicketStatus.values.where((v) => v.name == n))
        .expand((matches) => matches)
        .toSet();
    return TicketBoardColumnVisibility(hiddenStatuses: hidden);
  }

  @override
  Future<void> setHiddenColumns(
    String projectId,
    TicketBoardColumnVisibility visibility,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key(projectId),
      visibility.hiddenStatuses.map((s) => s.name).toList(),
    );
  }
}
