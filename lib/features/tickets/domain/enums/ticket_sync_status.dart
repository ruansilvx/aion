// domain/enums/ticket_sync_status.dart — TicketSyncStatus enum (domain layer).

/// How a [Ticket](../entities/ticket.dart)'s database record relates to its
/// projected Markdown file, if it has one.
///
/// Only `resource`/`page` tickets ever leave [synced] — every other
/// [TicketType](ticket_type.dart) has a one-way, generated file with no
/// external input to fall out of sync with.
enum TicketSyncStatus {
  /// DB and file (if applicable) agree. Default for every ticket type;
  /// the only state work-item types (epic/story/task/chat) ever have,
  /// since they have no file to fall out of sync with.
  synced,

  /// A resource/page ticket has a reconcile in flight (background,
  /// non-blocking) — surfaced as a subtle indicator, not a blocker.
  pendingReconcile,

  /// A resource/page ticket's file failed to parse on reconcile.
  /// Neither the DB nor the file was overwritten. Requires a manual
  /// reformat or restore-from-last-known-good action.
  needsRepair,
}
