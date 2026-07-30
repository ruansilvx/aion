// domain/enums/inbox_purpose.dart — InboxPurpose enum (domain layer).

/// Which of the Inbox's four purpose-specific chats spawned a
/// [Ticket](../entities/ticket.dart) of type `chat`. Set exactly once, at
/// creation, on `Ticket.inboxPurpose` — `null` for every ticket not spawned
/// by the Inbox, including every other `chat`. See
/// `aion-arch/changes/new-project-onboarding-inbox/design.md` §1.3.
enum InboxPurpose {
  /// Classifies pasted/typed raw notes into one or more `signal` tickets,
  /// each tagged with a suggested promotion type (epic or bug).
  brainDump,

  /// Advisory guidance on what to work on next, ported from the CLI
  /// `/what-next` skill's priority order. Never creates or modifies a
  /// ticket itself.
  whatNextGuidance,

  /// Converses about which tickets belong in an upcoming release, then
  /// materializes a `release` ticket plus `relatesTo` links once the
  /// conversation concludes.
  releasePlanning,

  /// General read-only Q&A over tickets, docs, and source code.
  qa,
}
