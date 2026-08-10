// data/repositories/shared_prefs_ticket_list_filter_repository.dart — SharedPrefsTicketListFilterRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/domain/entities/ticket_list_filters.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_filter_repository.dart';

/// `shared_preferences`-backed implementation of
/// [TicketListFilterRepository]. Stores each field of a project's
/// [TicketListFilters] as its own project-id-prefixed string-list key
/// (`ticket_list_filters.<projectId>.statuses`/`.types`/`.priorities`),
/// each entry the selected enum value's `.name`. A project with no
/// persisted keys yet reads back as a default-empty [TicketListFilters].
class SharedPrefsTicketListFilterRepository
    implements TicketListFilterRepository {
  String _statusesKey(String projectId) =>
      'ticket_list_filters.$projectId.statuses';

  String _typesKey(String projectId) => 'ticket_list_filters.$projectId.types';

  String _prioritiesKey(String projectId) =>
      'ticket_list_filters.$projectId.priorities';

  @override
  Future<TicketListFilters> getFilters(String projectId) async {
    final prefs = await SharedPreferences.getInstance();

    final statusNames = prefs.getStringList(_statusesKey(projectId)) ?? [];
    final typeNames = prefs.getStringList(_typesKey(projectId)) ?? [];
    final priorityNames =
        prefs.getStringList(_prioritiesKey(projectId)) ?? [];

    return TicketListFilters(
      statuses: statusNames
          .map(
            (name) => TicketStatus.values.where((v) => v.name == name),
          )
          .expand((matches) => matches)
          .toSet(),
      types: typeNames
          .map((name) => TicketType.values.where((v) => v.name == name))
          .expand((matches) => matches)
          .toSet(),
      priorities: priorityNames
          .map(
            (name) => TicketPriority.values.where((v) => v.name == name),
          )
          .expand((matches) => matches)
          .toSet(),
    );
  }

  @override
  Future<void> setFilters(String projectId, TicketListFilters filters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _statusesKey(projectId),
      filters.statuses.map((v) => v.name).toList(),
    );
    await prefs.setStringList(
      _typesKey(projectId),
      filters.types.map((v) => v.name).toList(),
    );
    await prefs.setStringList(
      _prioritiesKey(projectId),
      filters.priorities.map((v) => v.name).toList(),
    );
  }
}
