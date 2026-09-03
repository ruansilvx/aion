// domain/enums/ticket_sort_field.dart — TicketSortField enum (domain layer).

/// The field the ticket list's Sort control orders by. See
/// `AIO-2371`.
///
/// Exactly one value is active at a time (see
/// `TicketListSort`) — this is a single-active-key sort, never a
/// compound/stacked one.
enum TicketSortField {
  /// BM25 match score against an active search query — "best match
  /// first". Only ever the *implicit* default (see
  /// `TicketsCubit._implicitSort`), and only meaningful while a query is
  /// active; has no direction toggle of its own — its ordering is always
  /// SQLite's `bm25()` ascending (more-negative score = better match).
  relevance,

  /// [TicketPriority](../enums/ticket_priority.dart)'s own declaration
  /// order (`critical` is index 0) — already semantically meaningful,
  /// not alphabetical by name.
  priority,

  /// Each ticket's resolved `WorkflowStatus.sortOrder` — a project's own
  /// configured status ordering (`backlog` at index 0 by default), not a
  /// fixed enum declaration order. Was `TicketStatus`'s own declaration
  /// order before `AIO-549`.
  status,

  /// [TicketType](../enums/ticket_type.dart)'s own declaration order
  /// (`epic` is index 0) — already semantically meaningful, not
  /// alphabetical by name.
  type,

  /// The literal `createdAt` timestamp column.
  createdAt,

  /// The literal `updatedAt` timestamp column.
  updatedAt,
}
