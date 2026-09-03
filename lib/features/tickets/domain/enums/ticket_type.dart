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
  /// task-under-task is not permitted — see [TicketTypeHierarchy.canParent];
  /// a [bug] ticket occupies the same rank and is likewise unparentable
  /// by a task.
  task,

  /// A reference or supporting artifact (link, file, note) attached to work.
  resource,

  /// A Notion-style freeform document ticket.
  page,

  /// An agent chat, optionally branching into subtickets. A [chat] may now
  /// parent exactly one further [chat] — a mid-task/issue branch — per
  /// [TicketTypeHierarchy.canParent]'s one-level exception; a branch chat
  /// cannot itself be branched again, a depth cap `TicketsCubit._canBranch`
  /// enforces at the instance level (this type-level rule alone permits
  /// unbounded nesting, since it can't see a specific ticket's own parent
  /// chain). See `AIO-1118` §5.
  chat,

  /// A raw idea noticed but not yet resolved into work — not yet shaped into
  /// an [epic]. Freestanding: no required target, always a subtree root,
  /// promotable into an [epic] or a [bug] via `TicketsCubit.promoteIdea`.
  /// Parentless; may parent a [chat] for exploration/discussion, nothing else.
  /// See [TicketTypeHierarchy.isAlwaysRoot]. Was `signal` prior to `AIO-934`,
  /// which split its three meanings (idea / known gap / open question) into
  /// distinct types — `idea` inherits `signal`'s exact prior behavior.
  idea,

  /// An acknowledged hole in a target ticket's coverage — never freestanding.
  /// Must be created already linked (`TicketLinkType.relatesTo`) to an
  /// existing target ticket via `TicketsCubit.createGapOrQuestion` or
  /// `TicketsCubit.reclassifyIdea`; never reachable from the generic New
  /// Ticket flow. Parentless; may parent a [chat] for exploration/discussion,
  /// nothing else. See [TicketTypeHierarchy.isAlwaysRoot]. Added for
  /// `AIO-934`.
  knownGap,

  /// A raised, unresolved point about a target ticket — never freestanding.
  /// Must be created already linked (`TicketLinkType.relatesTo`) to an
  /// existing target ticket via `TicketsCubit.createGapOrQuestion` or
  /// `TicketsCubit.reclassifyIdea`; never reachable from the generic New
  /// Ticket flow. Parentless; may parent a [chat] for exploration/discussion,
  /// nothing else. See [TicketTypeHierarchy.isAlwaysRoot]. Added for
  /// `AIO-934`.
  openQuestion,

  /// A named release/milestone. Parentless; may parent a [chat] for
  /// release-planning discussion, nothing else. Relates to [epic]/
  /// [story]/[task] tickets via `TicketLinkType.relatesTo` (a cross-
  /// cutting link, not tree-parentage) — a ticket can belong to a
  /// release without that release being its structural parent. See
  /// [TicketTypeHierarchy.isAlwaysRoot].
  release,

  /// A defect: something existing that doesn't work as intended. Ranked
  /// like [task] in the epic→story→task chain (see
  /// [TicketTypeHierarchy]) — a bug is fundamentally a unit of execution,
  /// with extra diagnostic fields ([Ticket.severity],
  /// [Ticket.stepsToReproduce], [Ticket.expectedBehavior],
  /// [Ticket.actualBehavior]) a plain [task] has no use for. Its affected
  /// version/environment is expressed via a `TicketLinkType.relatesTo`
  /// link to a [release] ticket, not a dedicated field — the same
  /// mechanism [release] already has with [epic]/[story]/[task].
  bug,

  /// Aion's own record of a capability's current-state behavior — the
  /// ticket-native replacement for `aion-arch/specs/*.md`. Created
  /// automatically, once, when an [epic]'s `SddStage` reaches
  /// `SddStage.archived` (`TicketsCubit._createEpicSpec`, called from
  /// `TicketsCubit.advanceSddStage`), or manually via the ordinary New Ticket
  /// flow (used for the one-off "architecture spec" ticket that plays
  /// `project.md`'s role — see `AIO-63`). Parentless; may parent a [chat] for
  /// discussion, nothing else. Once created, its content is an ordinary
  /// editable document — see `PagesCubit`, which also serves this type — with
  /// no cycle of its own; corrections and resolved-bug links are plain edits.
  /// See [TicketTypeHierarchy.isAlwaysRoot]. Added for `AIO-1998`.
  spec,
}

/// Structural parent/child rules between [TicketType] values. A ticket's
/// type determines which other types it may structurally parent —
/// independent of the self-parent/cycle checks `TicketsCubit` already
/// performs, which apply regardless of type.
extension TicketTypeHierarchy on TicketType {
  /// This type's rank in the epic > story > task/bug work-breakdown
  /// chain, or `null` for a type ([TicketType.resource],
  /// [TicketType.page], [TicketType.chat], [TicketType.idea],
  /// [TicketType.knownGap], [TicketType.openQuestion],
  /// [TicketType.release], [TicketType.spec]) with no rank in that chain.
  /// Note that `page`, `idea`/`knownGap`/`openQuestion`/`release`/`spec`,
  /// each still have their own nesting rule — see [canParent] — despite
  /// having no rank here. [TicketType.task] and [TicketType.bug] share
  /// the same literal rank value, which is what makes them siblings:
  /// neither can parent the other, exactly like every other same-rank
  /// pair.
  int? get _rank => switch (this) {
    TicketType.epic => 0,
    TicketType.story => 1,
    TicketType.task || TicketType.bug => 2,
    TicketType.resource ||
    TicketType.page ||
    TicketType.chat ||
    TicketType.idea ||
    TicketType.knownGap ||
    TicketType.openQuestion ||
    TicketType.release ||
    TicketType.spec => null,
  };

  /// Whether a ticket of this type may structurally parent a ticket of
  /// type [child].
  ///
  /// - [TicketType.page] may parent [TicketType.page] (Notion-style
  ///   sub-page nesting) or [TicketType.resource], and nothing else —
  ///   documentation tickets nest only under other documentation tickets,
  ///   never under a work item.
  /// - [TicketType.idea], [TicketType.knownGap], [TicketType.openQuestion],
  ///   [TicketType.release], and [TicketType.spec] may each parent a
  ///   [TicketType.chat] only — none is part of the epic→story→task
  ///   decomposition chain (an `idea` is promoted *into* an `epic`/`bug`
  ///   by a separate mechanism, not parented by one; `knownGap`/
  ///   `openQuestion`/`spec` are never promoted at all).
  /// - A work type (epic/story/task/bug) may parent another work type
  ///   only if strictly higher in the chain (epic > story > task/bug,
  ///   e.g. task cannot parent story), and may still parent
  ///   [TicketType.chat] unconditionally. [TicketType.task] and
  ///   [TicketType.bug] share the same rank, so neither can parent the
  ///   other — same-rank nesting is always rejected. Work types can no
  ///   longer parent [TicketType.resource] or [TicketType.page] — those
  ///   relocated under the Documentation section and link back to work
  ///   tickets via `TicketLink` instead of `parentId`.
  /// - [TicketType.resource] remains a full leaf and can never parent
  ///   anything, including itself.
  /// - [TicketType.chat] is a leaf for every other type but may now parent
  ///   exactly one further [chat] — a mid-task/issue branch (see
  ///   [TicketType.chat]'s own dartdoc). This type-level rule only says *a*
  ///   chat may parent *a* chat; it doesn't cap nesting depth at one level —
  ///   that instance-level invariant (a chat already parented by another chat
  ///   cannot itself be branched) lives in `TicketsCubit._canBranch`,
  ///   consistent with this project's "type-level rules live in the enum
  ///   extension, instance-level invariants live in the Cubit" split. Added
  ///   for `AIO-1118`; see its linked Documentation page, §5.
  bool canParent(TicketType child) {
    if (this == TicketType.page) {
      return child == TicketType.page || child == TicketType.resource;
    }
    if (this == TicketType.idea ||
        this == TicketType.knownGap ||
        this == TicketType.openQuestion ||
        this == TicketType.release ||
        this == TicketType.spec) {
      return child == TicketType.chat;
    }
    if (this == TicketType.chat) {
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
  /// subtree root. `true` for [TicketType.epic], [TicketType.idea],
  /// [TicketType.knownGap], [TicketType.openQuestion],
  /// [TicketType.release], and [TicketType.spec]; `false` for every other
  /// type. The "always root" property is about *structural* parentage
  /// (`parentId`) — `knownGap`/`openQuestion`'s mandatory target
  /// relationship is a `TicketLink`, a completely separate mechanism, so
  /// this stays `true` for both exactly as it was for `signal`.
  bool get isAlwaysRoot =>
      this == TicketType.epic ||
      this == TicketType.idea ||
      this == TicketType.knownGap ||
      this == TicketType.openQuestion ||
      this == TicketType.release ||
      this == TicketType.spec;

  /// The [TicketType] values whose move to `TicketStatus.inProgress`
  /// triggers a real coding-execution run — see
  /// `TicketsCubit._interceptTaskExecutionTrigger`. [TicketType.bug] was
  /// added here for full execution parity with [TicketType.task];
  /// anywhere a Story's rank-2 children are gathered for
  /// design-review-gate or SDD-readiness purposes should use this list
  /// instead of a `task`-only literal.
  static const List<TicketType> executableTypes = [
    TicketType.task,
    TicketType.bug,
  ];

  /// Whether this type's move to `TicketStatus.inProgress` triggers
  /// coding-execution. See [executableTypes].
  bool get isExecutable => executableTypes.contains(this);
}
