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

  /// Something noticed but not yet resolved into work: a raw idea, a
  /// known gap, or an open question — not yet shaped into an [epic].
  /// Parentless; may parent a [chat] for exploration/discussion, nothing
  /// else. See [TicketTypeHierarchy.isAlwaysRoot].
  signal,

  /// A named release/milestone. Parentless; may parent a [chat] for
  /// release-planning discussion, nothing else. Relates to [epic]/
  /// [story]/[task] tickets via `TicketLinkType.relatesTo` (a cross-
  /// cutting link, not tree-parentage) — a ticket can belong to a
  /// release without that release being its structural parent. See
  /// [TicketTypeHierarchy.isAlwaysRoot].
  release,
}

/// Structural parent/child rules between [TicketType] values. A ticket's
/// type determines which other types it may structurally parent —
/// independent of the self-parent/cycle checks `TicketsCubit` already
/// performs, which apply regardless of type.
extension TicketTypeHierarchy on TicketType {
  /// This type's rank in the epic > story > task work-breakdown chain, or
  /// `null` for a type ([TicketType.resource], [TicketType.page],
  /// [TicketType.chat], [TicketType.signal], [TicketType.release]) with no
  /// rank in that chain. Note that `page`, `signal`, and `release` each
  /// still have their own nesting rule — see [canParent] — despite having
  /// no rank here.
  int? get _rank => switch (this) {
    TicketType.epic => 0,
    TicketType.story => 1,
    TicketType.task => 2,
    TicketType.resource ||
    TicketType.page ||
    TicketType.chat ||
    TicketType.signal ||
    TicketType.release => null,
  };

  /// Whether a ticket of this type may structurally parent a ticket of
  /// type [child].
  ///
  /// - [TicketType.page] may parent [TicketType.page] (Notion-style
  ///   sub-page nesting) or [TicketType.resource], and nothing else —
  ///   documentation tickets nest only under other documentation tickets,
  ///   never under a work item.
  /// - [TicketType.signal] and [TicketType.release] may each parent a
  ///   [TicketType.chat] only — neither is part of the epic→story→task
  ///   decomposition chain (a `signal` is promoted *into* an `epic` by a
  ///   separate mechanism, not parented by one).
  /// - A work type (epic/story/task) may parent another work type only if
  ///   strictly higher in the chain (epic > story > task, e.g. task cannot
  ///   parent story), and may still parent [TicketType.chat]
  ///   unconditionally. Work types can no longer parent
  ///   [TicketType.resource] or [TicketType.page] — those relocated under
  ///   the Documentation section and link back to work tickets via
  ///   `TicketLink` instead of `parentId`.
  /// - [TicketType.resource] and [TicketType.chat] remain full leaves and
  ///   can never parent anything, including each other.
  bool canParent(TicketType child) {
    if (this == TicketType.page) {
      return child == TicketType.page || child == TicketType.resource;
    }
    if (this == TicketType.signal || this == TicketType.release) {
      return child == TicketType.chat;
    }
    final parentRank = _rank;
    if (parentRank == null) return false;
    if (child == TicketType.chat) return true;
    final childRank = child._rank;
    if (childRank == null) return false;
    return parentRank < childRank;
  }

  /// Whether a ticket of this type can never receive a parent — always a
  /// subtree root. `true` for [TicketType.epic], [TicketType.signal], and
  /// [TicketType.release]; `false` for every other type.
  bool get isAlwaysRoot =>
      this == TicketType.epic ||
      this == TicketType.signal ||
      this == TicketType.release;
}
