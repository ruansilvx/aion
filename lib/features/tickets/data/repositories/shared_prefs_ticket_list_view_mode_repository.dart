// data/repositories/shared_prefs_ticket_list_view_mode_repository.dart — SharedPrefsTicketListViewModeRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/domain/entities/ticket_list_view_mode.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_view_mode_repository.dart';

/// `shared_preferences`-backed implementation of
/// [TicketListViewModeRepository]. Stores a project's
/// [TicketListViewMode] as one project-id-prefixed string key
/// (`ticket_list_view_mode.<projectId>`), the selected enum value's
/// `.name` — a view mode has no second dimension the way
/// `SharedPrefsTicketListSortRepository`'s sort selection has
/// field+direction, so a single key suffices.
class SharedPrefsTicketListViewModeRepository
    implements TicketListViewModeRepository {
  String _key(String projectId) => 'ticket_list_view_mode.$projectId';

  @override
  Future<TicketListViewMode?> getViewMode(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key(projectId));
    if (name == null) return null;
    return TicketListViewMode.values
        .where((v) => v.name == name)
        .firstOrNull;
  }

  @override
  Future<void> setViewMode(String projectId, TicketListViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(projectId), mode.name);
  }
}
