// domain/enums/ticket_type.dart — TicketType enum (domain layer).

/// The kind of entity a [Ticket](../entities/ticket.dart) represents.
///
/// Every Aion entity (epic, story, task, resource, page, chat) is modelled
/// as a ticket variant distinguished by this field.
enum TicketType {
  /// A large body of work with no structural parent, decomposed into
  /// stories/tasks by its watcher. Never watcher-reviewed itself.
  epic,

  /// A user-facing unit of work, typically a child of an epic.
  story,

  /// A concrete unit of execution. A task whose `parentId` points to another
  /// task or story is the Aion subtask convention (no dedicated type).
  task,

  /// A reference or supporting artifact (link, file, note) attached to work.
  resource,

  /// A Notion-style freeform document ticket.
  page,

  /// An agent chat, optionally branching into subtickets.
  chat,
}
