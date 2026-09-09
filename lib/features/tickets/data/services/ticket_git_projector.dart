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
///
/// [project]/[projectBatch] calls are serialized through one internal
/// FIFO queue ([_enqueue]) rather than left free-running: multiple
/// tickets created in a tight loop (e.g.
/// `TicketsCubit._materializeParsedChildren`, backing SDD decomposition
/// — several `Ticket`s created back-to-back, each independently and
/// unawaited-ly projected by `GitProjectingTicketRepository`) would
/// otherwise fire concurrent `git add`/`git commit` subprocesses against
/// the same working tree. Git's own `.git/index.lock` turns a genuine
/// collision into a failed command rather than corrupted data, but a
/// failed command here is a *lost* projection with no retry — exactly
/// the class of drift this whole mechanism exists to close. Queuing
/// makes every call site's concurrency safe by construction, without
/// requiring `TicketsCubit`'s many independent call sites to coordinate
/// with each other.
class TicketGitProjector {
  /// Creates a [TicketGitProjector] using [_serializer] and [_git].
  TicketGitProjector(this._serializer, this._git);

  final TicketMarkdownSerializer _serializer;
  final GitRepositoryClient _git;

  /// Tail of the serialization queue — always resolves (successes and
  /// failures alike), so one queued call throwing never wedges the ones
  /// behind it. See [_enqueue].
  Future<void> _tail = Future<void>.value();

  /// Writes [ticket]'s Markdown file under [rootPath] and commits it with
  /// a message describing [eventLabel] (e.g. `'created'`,
  /// `'status-changed'`, `'trashed'`, `'restored'`). Skips the commit
  /// (but still writes the file) if the write produced no git-visible
  /// change, avoiding empty commits. Queued behind any earlier
  /// [project]/[projectBatch] call still in flight — see this class's
  /// own dartdoc.
  Future<void> project(
    Ticket ticket,
    String rootPath,
    String eventLabel,
  ) {
    return _enqueue(() => _project(ticket, rootPath, eventLabel));
  }

  Future<void> _project(
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

  /// Writes every ticket in [ancestors] to its own Markdown file (same
  /// serialization [project] uses) and stages each one, then makes
  /// **one** commit covering the whole batch — skipped if nothing
  /// actually changed (same `hasChanges` guard [project] uses). Used for
  /// a rollup recompute's cascading ancestor rewrites (where committing
  /// per-file would turn one estimate edit into a wall of near-identical
  /// commits) and for `GitProjectingTicketRepository`'s trash/restore
  /// cascade and `TicketsCubit`'s bulk-trash path (where the batch can
  /// include cascaded descendants, or — for restore — both ancestors
  /// and descendants at once, not only ancestors). No-ops (writes
  /// nothing, commits nothing) if [ancestors] is empty. Queued behind
  /// any earlier [project]/[projectBatch] call still in flight — see
  /// this class's own dartdoc.
  Future<void> projectBatch(
    List<Ticket> ancestors,
    String rootPath,
    String eventLabel,
  ) {
    return _enqueue(() => _projectBatch(ancestors, rootPath, eventLabel));
  }

  Future<void> _projectBatch(
    List<Ticket> ancestors,
    String rootPath,
    String eventLabel,
  ) async {
    if (ancestors.isEmpty) return;
    for (final ticket in ancestors) {
      final relativePath = 'tickets/${ticket.ticketId}.md';
      final file = File('$rootPath/$relativePath');
      await file.parent.create(recursive: true);
      await file.writeAsString(_serializer.serialize(ticket));
      await _git.add(rootPath, relativePath);
    }
    if (!await _git.hasChanges(rootPath)) return;
    final label = ancestors.length == 1
        ? '${ancestors.single.ticketId} $eventLabel'
        : '${ancestors.length} tickets $eventLabel';
    await _git.commit(rootPath, 'ticket: $label');
  }

  /// Chains [operation] onto [_tail] so it starts only after every
  /// previously-enqueued [project]/[projectBatch] call has finished
  /// (successfully or not), then advances [_tail] past it the same way —
  /// a plain async-mutex-via-Future-chaining pattern, not a real lock
  /// object, since Dart's single-threaded event loop makes that
  /// sufficient here. The caller's own returned [Future] still carries
  /// [operation]'s real result/error; only *when* [operation] starts
  /// running is serialized, not whether its outcome propagates.
  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
