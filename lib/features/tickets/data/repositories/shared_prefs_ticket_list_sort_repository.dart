// data/repositories/shared_prefs_ticket_list_sort_repository.dart — SharedPrefsTicketListSortRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_sort_repository.dart';

/// `shared_preferences`-backed implementation of
/// [TicketListSortRepository]. Stores a project's [TicketListSort] as two
/// project-id-prefixed string keys (`ticket_list_sort.<projectId>.field`/
/// `.direction`, each the selected enum value's `.name`) — a sort
/// selection is one value, not a set, unlike
/// `SharedPrefsTicketListFilterRepository`'s string-list keys. A project
/// with no persisted keys yet (or a value that fails to parse against
/// the current enums) reads back as `null`, meaning "no explicit choice
/// yet" — see [TicketListSortRepository.getSort].
class SharedPrefsTicketListSortRepository implements TicketListSortRepository {
  /// The `shared_preferences` key storing [projectId]'s sort field.
  String _fieldKey(String projectId) => 'ticket_list_sort.$projectId.field';

  /// The `shared_preferences` key storing [projectId]'s sort direction.
  String _directionKey(String projectId) =>
      'ticket_list_sort.$projectId.direction';

  @override
  Future<TicketListSort?> getSort(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final fieldName = prefs.getString(_fieldKey(projectId));
    final directionName = prefs.getString(_directionKey(projectId));
    if (fieldName == null || directionName == null) return null;

    final field = TicketSortField.values
        .where((v) => v.name == fieldName)
        .firstOrNull;
    final direction = TicketSortDirection.values
        .where((v) => v.name == directionName)
        .firstOrNull;
    if (field == null || direction == null) return null;

    return TicketListSort(field: field, direction: direction);
  }

  @override
  Future<void> setSort(String projectId, TicketListSort sort) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fieldKey(projectId), sort.field.name);
    await prefs.setString(_directionKey(projectId), sort.direction.name);
  }
}
