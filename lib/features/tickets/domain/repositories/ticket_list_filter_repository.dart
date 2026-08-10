// domain/repositories/ticket_list_filter_repository.dart — TicketListFilterRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket_list_filters.dart';

/// Per-project persistence for the ticket list's [TicketListFilters]
/// selection. Implemented by the data layer
/// ([SharedPrefsTicketListFilterRepository]); UI and Cubit code depend
/// only on this interface, never on a concrete storage mechanism.
abstract interface class TicketListFilterRepository {
  /// Returns the persisted [TicketListFilters] for [projectId], or a
  /// default-empty [TicketListFilters] if nothing has been saved for that
  /// project yet.
  Future<TicketListFilters> getFilters(String projectId);

  /// Persists [filters] as the current selection for [projectId],
  /// overwriting whatever was previously saved for that project.
  Future<void> setFilters(String projectId, TicketListFilters filters);
}
