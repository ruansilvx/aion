// domain/repositories/ticket_list_sort_repository.dart — TicketListSortRepository interface (domain layer).

import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';

/// Per-project persistence for the ticket list's [TicketListSort]
/// selection. Implemented by the data layer
/// ([SharedPrefsTicketListSortRepository]); UI and Cubit code depend
/// only on this interface, never on a concrete storage mechanism.
///
/// A sibling of `TicketListFilterRepository`, not an extension of it — sort
/// and filters are independent selections with different "unset" semantics: an
/// unset filter field is an empty `Set`, meaning "no constraint"; an unset
/// sort is `null`, meaning "no explicit choice yet, use the implicit
/// query-aware default" (see `TicketsCubit._implicitSort`). See `AIO-2371`.
abstract interface class TicketListSortRepository {
  /// The persisted explicit sort for [projectId], or `null` if the user
  /// has never explicitly chosen one for this project — the implicit
  /// query-aware default applies in that case (see
  /// `TicketsCubit._implicitSort`), not an arbitrary fallback value
  /// returned here.
  Future<TicketListSort?> getSort(String projectId);

  /// Persists [sort] as [projectId]'s explicit selection, overwriting
  /// whatever was previously saved.
  Future<void> setSort(String projectId, TicketListSort sort);
}
