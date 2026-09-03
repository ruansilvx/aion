// domain/enums/ticket_sort_direction.dart — TicketSortDirection enum (domain layer).

/// The direction a [TicketSortField](ticket_sort_field.dart) orders by.
/// Applies to every field except
/// [TicketSortField.relevance](ticket_sort_field.dart), which ignores it (its
/// ordering is always bm25 ascending, ignoring the value stored here). See
/// `AIO-2371`.
enum TicketSortDirection {
  /// Lowest/earliest first (e.g. oldest `createdAt` first, or a field's
  /// enum-ordinal 0 first).
  ascending,

  /// Highest/latest first (e.g. newest `createdAt` first, or a field's
  /// highest enum-ordinal first).
  descending,
}
