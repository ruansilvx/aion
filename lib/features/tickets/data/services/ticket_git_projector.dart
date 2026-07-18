// data/services/ticket_git_projector.dart — TicketGitProjector (data layer).

import 'dart:io';

import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// One-way DB -> file writer: serializes a [Ticket] to
/// `<rootPath>/tickets/<ticketId>.md` and commits it to the project's git
/// repository. The file this writes is a generated, read-only audit
/// trail — never read back into the database.
///
/// Callers are responsible for only invoking this for `epic`/`story`/
/// `task`/`chat` tickets (`resource`/`page` tickets also get an initial
/// projection this way, but subsequently gain a bidirectional watcher —
/// see `TicketMarkdownReconciler`); this class itself performs no
/// type check.
class TicketGitProjector {
  /// Creates a [TicketGitProjector] using [_serializer] and [_git].
  TicketGitProjector(this._serializer, this._git);

  final TicketMarkdownSerializer _serializer;
  final GitRepositoryClient _git;

  /// Writes [ticket]'s Markdown file under [rootPath] and commits it with
  /// a message describing [eventLabel] (e.g. `'created'`,
  /// `'status-changed'`, `'trashed'`, `'restored'`). Skips the commit
  /// (but still writes the file) if the write produced no git-visible
  /// change, avoiding empty commits.
  Future<void> project(
    Ticket ticket,
    String rootPath,
    String eventLabel,
  ) async {
    final relativePath = 'tickets/${ticket.ticketId}.md';
    final file = File('$rootPath/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsString(_serializer.serialize(ticket));

    await _git.add(rootPath, relativePath);
    if (!await _git.hasChanges(rootPath)) return;
    await _git.commit(rootPath, 'ticket: ${ticket.ticketId} $eventLabel');
  }
}
