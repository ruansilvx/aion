// data/repositories/shared_prefs_ticket_list_filter_repository.dart — SharedPrefsTicketListFilterRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/tickets/domain/entities/ticket_list_filters.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_list_filter_repository.dart';

/// `shared_preferences`-backed implementation of
/// [TicketListFilterRepository]. Stores each field of a project's
/// [TicketListFilters] as its own project-id-prefixed string-list key
/// (`ticket_list_filters.<projectId>.statuses`/`.types`/`.priorities`).
/// `types`/`priorities` entries are the selected enum value's `.name`,
/// validated against that enum's live `.values` on read (a stale stored
/// name is silently dropped). `statuses` entries are a project-defined
/// `WorkflowStatus.name` and round-trip unvalidated — there's no fixed
/// enum left to validate against; a stale stored status name (deleted or
/// renamed since) is naturally never matched by any caller that checks it
/// against the project's live configured status list, and is dropped the
/// next time a fresh selection is persisted. A project with no persisted
/// keys yet reads back as a default-empty [TicketListFilters].
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
      statuses: statusNames.toSet(),
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
      filters.statuses.toList(),
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
