// domain/entities/notification.dart — NotificationKind enum + Notification entity (domain layer).

import 'package:equatable/equatable.dart';

/// What kind of outcome a [Notification] records. Mirrors the terminal
/// states `TicketsCubit._runCodingExecution`/`_runStageChatTurn` already
/// post system comments for — a notification is written alongside each
/// comment, not derived from it later. See
/// `aion-arch/changes/pr-metadata-and-notification-center/design.md` §2.1.
enum NotificationKind {
  /// A coding-execution run finished with a confirmed, opened PR.
  executionPrOpened,

  /// A coding-execution run's verify gate failed — no PR opened.
  executionVerificationFailed,

  /// A coding-execution run failed for an infra/setup reason (worktree,
  /// push, PR-open failure) before verification was even reached.
  executionFailed,

  /// An Epic/Story SDD-stage-chat turn completed successfully.
  stageAdvanceCompleted,

  /// An Epic/Story SDD-stage-chat turn failed.
  stageAdvanceFailed,
}

/// A persisted record of a coding-execution or SDD-stage-chat terminal
/// outcome, surfaced via the notification-center dropdown
/// (`WorkspaceNavShell`'s `_NotificationBellTrigger`) so a human who
/// wasn't looking at the right ticket at the right moment can still
/// catch up. See `aion-arch/changes/pr-metadata-and-notification-center/design.md`
/// §2-§3.
///
/// Named `Notification`, not e.g. `AionNotification` — matches
/// `aion-arch/changes/pr-metadata-and-notification-center/design.md`
/// §2.1's exact naming. This collides with `package:flutter/widgets.dart`'s
/// own `Notification` class, so any file importing both must `hide
/// Notification` on the Flutter import (see `notification_dropdown.dart`,
/// `notification_bell_trigger.dart`, and any other widget file that
/// imports this entity alongside Flutter widgets).
class Notification extends Equatable {
  /// Creates a [Notification].
  const Notification({
    required this.id,
    required this.ticketId,
    required this.ticketTitle,
    required this.kind,
    required this.message,
    required this.createdAt,
    this.readAt,
  });

  /// UUID v4 primary key.
  final String id;

  /// The Task/Bug/Epic/Story ticket this notification concerns — not
  /// the spawned chat ticket, so tapping a row always navigates to the
  /// ticket a human would actually want to act on.
  final String ticketId;

  /// [ticketId]'s title, snapshotted at write time. Deliberately
  /// denormalized: the dropdown can open from any `/workspace/*` route,
  /// not only the Board (where the full ticket list is already loaded),
  /// so resolving titles via N individual `getTicketById` lookups every
  /// time the dropdown opens would mean an extra DB round-trip per row.
  /// Can go stale if the ticket is later renamed — treated as an
  /// acceptable, deliberate tradeoff (a notification is a historical
  /// record of "what happened," same as a git commit or PR title
  /// freezing at creation time).
  final String ticketTitle;

  /// What kind of outcome this row records.
  final NotificationKind kind;

  /// Precomputed, already-formatted display text (e.g. "PR #42 opened
  /// · 5 files changed", "Advanced to Design"). Formatted once at
  /// write time, not re-derived at render time.
  final String message;

  /// Unix milliseconds.
  final DateTime createdAt;

  /// `null` while unread; set to the moment a human read/tapped this
  /// row. Nullable-timestamp read/unread, mirroring `Ticket.deletedAt`'s
  /// existing nullable-timestamp convention for a two-state flag rather
  /// than introducing a separate bool column.
  final DateTime? readAt;

  /// Whether this notification has not yet been read.
  bool get isUnread => readAt == null;

  @override
  List<Object?> get props =>
      [id, ticketId, ticketTitle, kind, message, createdAt, readAt];
}
