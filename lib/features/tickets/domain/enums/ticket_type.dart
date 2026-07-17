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

  /// A concrete unit of execution. A task whose `parentId` points to a
  /// story is the Aion subtask convention (no dedicated type);
  /// task-under-task is not permitted — see [TicketTypeHierarchy.canParent].
  task,

  /// A reference or supporting artifact (link, file, note) attached to work.
  resource,

  /// A Notion-style freeform document ticket.
  page,

  /// An agent chat, optionally branching into subtickets.
  chat,
}

/// Structural parent/child rules between [TicketType] values. A ticket's
/// type determines which other types it may structurally parent —
/// independent of the self-parent/cycle checks `TicketsCubit` already
/// performs, which apply regardless of type.
extension TicketTypeHierarchy on TicketType {
  /// This type's rank in the epic > story > task work-breakdown chain, or
  /// `null` for a leaf type ([TicketType.resource], [TicketType.page],
  /// [TicketType.chat]) that has no rank and can never parent anything.
  int? get _rank => switch (this) {
    TicketType.epic => 0,
    TicketType.story => 1,
    TicketType.task => 2,
    TicketType.resource || TicketType.page || TicketType.chat => null,
  };

  /// Whether a ticket of this type may structurally parent a ticket of
  /// type [child]. Leaf types (resource/page/chat) can never parent
  /// anything. A work type (epic/story/task) may parent another work
  /// type only if strictly higher in the chain (epic > story > task,
  /// e.g. task cannot parent story), and may parent any leaf type
  /// unconditionally. Same-type nesting is always rejected — a
  /// consequence of the strict-rank comparison, not a special case.
  bool canParent(TicketType child) {
    final parentRank = _rank;
    if (parentRank == null) return false;
    final childRank = child._rank;
    if (childRank == null) return true;
    return parentRank < childRank;
  }
}
