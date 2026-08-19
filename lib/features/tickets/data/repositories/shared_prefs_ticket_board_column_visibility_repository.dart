// data/repositories/shared_prefs_ticket_board_column_visibility_repository.dart — SharedPrefsTicketBoardColumnVisibilityRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/domain/entities/ticket_board_column_visibility.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_board_column_visibility_repository.dart';

/// `shared_preferences`-backed implementation of
/// [TicketBoardColumnVisibilityRepository]. Stores a project's
/// [TicketBoardColumnVisibility] as one project-id-prefixed string-list
/// key (`ticket_board_column_visibility.<projectId>.hiddenStatuses`),
/// each entry a project-defined `WorkflowStatus.name` — mirrors
/// `SharedPrefsTicketListFilterRepository`'s string-list convention. A
/// stale stored name (a status the project has since deleted or renamed)
/// round-trips through this repository unchanged; it's the caller
/// (`TicketsCubit`/`TicketBoardView`, which only ever render checkboxes
/// for the project's currently-configured statuses) that naturally never
/// matches it against anything live, so it's dropped the next time a
/// fresh selection is persisted rather than validated here — this
/// repository performs no validation at all, per this project's
/// Cubit-vs-repository split (was a `TicketStatus.values.where(...)`
/// enum round-trip before
/// `aion-arch/changes/configurable-ticket-workflow`).
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
    return TicketBoardColumnVisibility(hiddenStatuses: names.toSet());
  }

  @override
  Future<void> setHiddenColumns(
    String projectId,
    TicketBoardColumnVisibility visibility,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key(projectId),
      visibility.hiddenStatuses.toList(),
    );
  }
}
