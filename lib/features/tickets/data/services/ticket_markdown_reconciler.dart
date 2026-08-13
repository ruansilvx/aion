// data/services/ticket_markdown_reconciler.dart — TicketMarkdownReconciler (data layer).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/markdown/ticket_markdown_parse_result.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/core/markdown/ticket_markdown_template.dart';
import 'package:aion/features/tickets/data/services/active_ticket_view_registry.dart';
import 'package:aion/features/tickets/data/services/page_wikilink_indexer.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

/// Reconciles an externally-edited `resource`/`page` Markdown file back
/// into the database — the bidirectional half of ticket <-> Markdown
/// sync. Only ever called for `resource`/`page` tickets (see
/// `TicketMarkdownWatcherService`); a no-op for any other type.
///
/// **Known limitation**: does not apply a `parentId` change from a
/// hand-edited file, even though `parentId` round-trips through
/// [TicketMarkdownSerializer]'s frontmatter. Reparenting's cycle-
/// prevention logic lives in `TicketsCubit` (`project.md`'s Cubit-holds-
/// domain-logic convention), not the repository — applying a bare
/// `TicketRepository.updateTicketParent` from this background service
/// would bypass that check entirely. Left out rather than risk a
/// corrupted parent graph; revisit if hand-edited reparenting becomes a
/// real need.
///
/// **Known limitation**: does not apply a `deletedAt` change from a
/// hand-edited file either, for the same reason as `parentId` above —
/// `TicketRepository.trashTicket`/`.restoreTicket` carry cascade logic
/// (trashing cascades to descendants; restoring revives trashed
/// ancestors/descendants too) that a bare field write from this
/// background service would bypass, risking a corrupted trash state.
/// `deletedAt` round-trips through [TicketMarkdownSerializer] (needed by
/// `TicketDbReconstructionService`, which builds a fresh [Ticket] with
/// no existing row to protect), but [_apply] below has no case for it
/// and none is planned.
///
/// **Known limitation**: does not apply `estimateRollup`/
/// `timeSpentRollup` from a hand-edited file either — but unlike the two
/// limitations above, this one can never actually be exercised. Both
/// fields round-trip through [TicketMarkdownSerializer] for parse
/// completeness, and [Ticket.copyWith] has no parameters for them for
/// [_apply] to pass even if it tried, so they're structurally inert
/// here. More fundamentally: this reconciler only ever runs for
/// `resource`/`page` tickets, and `estimateRollup`/`timeSpentRollup` are
/// only ever meaningful on `epic`/`story`/`task`/`bug`/`chat` tickets —
/// per the Structural type-compatibility table in
/// `aion-arch/specs/tickets.md`, `resource`/`page` can never structurally
/// parent, or be parented by, a ranked type, so a rollup-relevant value
/// could never reach a hand-editable file's frontmatter in the first
/// place.
class TicketMarkdownReconciler {
  /// Creates a [TicketMarkdownReconciler] wired to [_repository] (reads
  /// the current ticket, writes back reconciled fields),
  /// [_serializer] (parses the file), [_activeTicketViewRegistry]
  /// (decides blocking vs. background), and [_embeddingProvider] (the
  /// same regen trigger used by `TicketsCubit`, applied here too so the
  /// two content-change surfaces stay unified). [_wikilinkIndexer] is
  /// optional (`null` in every construction site except
  /// `app_router.dart`, and in this class's own existing tests) — when
  /// supplied, a successfully-reconciled `page` ticket whose title or
  /// description actually changed also runs the same inline-`[[wikilink]]`
  /// reindex/rename-cascade `TicketsCubit.updateTicket` triggers for an
  /// in-app edit (same content-changed gate as that trigger), through the
  /// same shared [PageWikilinkIndexer] rather than a second, duplicated
  /// implementation — see `aion-arch/changes/inline-wikilink-backlinks
  /// /design.md`.
  TicketMarkdownReconciler(
    this._repository,
    this._serializer,
    this._activeTicketViewRegistry,
    this._embeddingProvider, [
    this._wikilinkIndexer,
  ]);

  final TicketRepository _repository;
  final TicketMarkdownSerializer _serializer;
  final ActiveTicketViewRegistry _activeTicketViewRegistry;
  final EmbeddingProvider _embeddingProvider;
  final PageWikilinkIndexer? _wikilinkIndexer;

  /// Reconciles the ticket identified by human-readable [ticketId] (e.g.
  /// `"AIO-42"`) against its file under `<rootPath>/tickets/`.
  Future<void> reconcile(String ticketId, String rootPath) async {
    final ticket = await _findByTicketId(ticketId);
    if (ticket == null) return;
    if (ticket.type != TicketType.resource && ticket.type != TicketType.page) {
      return;
    }

    final file = File('$rootPath/tickets/$ticketId.md');
    if (!await file.exists()) return;
    final result = _serializer.parse(await file.readAsString());

    if (result is Unparseable) {
      await _repository.updateSyncStatus(
        ticket.id,
        TicketSyncStatus.needsRepair,
      );
      return;
    }

    if (_activeTicketViewRegistry.activeTicketId.value == ticketId) {
      _deferUntilViewChanges(ticketId, rootPath);
      return;
    }

    await _repository.updateSyncStatus(
      ticket.id,
      TicketSyncStatus.pendingReconcile,
    );
    final updated = await _apply(ticket, result);
    await _repository.updateSyncStatus(ticket.id, TicketSyncStatus.synced);

    final indexer = _wikilinkIndexer;
    if (indexer != null &&
        updated != null &&
        ticket.type == TicketType.page &&
        (ticket.title != updated.title ||
            ticket.description != updated.description)) {
      unawaited(
        indexer.reindexAndCascade(
          oldTicket: ticket,
          newTicket: updated,
          applyRewrittenReferrer: _applyWikilinkRewrite,
        ),
      );
    }
  }

  /// Persists a rename-triggered wikilink rewrite of [referrer]'s
  /// content, then fires the same embedding-regen trigger [_apply] does
  /// for any other content change. Has no cubit to recurse
  /// [TicketsCubit.updateTicket] through (unlike `TicketsCubit`'s own
  /// version of this callback), so it writes directly through
  /// [_repository] instead — the [PageWikilinkIndexer] this is passed to
  /// never calls it again for the same referrer within one
  /// [PageWikilinkIndexer.reindexAndCascade] pass, so there's no
  /// recursive-regen risk here either.
  Future<void> _applyWikilinkRewrite(
    Ticket referrer,
    String rewrittenDescription,
  ) async {
    final updated = referrer.copyWith(description: () => rewrittenDescription);
    await _repository.updateTicket(updated);
    unawaited(
      _embeddingProvider
          .embed('${updated.title}\n\n$rewrittenDescription')
          .then((bytes) => _repository.updateEmbedding(updated.id, bytes)),
    );
  }

  /// Re-attempts [reconcile] once [_activeTicketViewRegistry] moves away
  /// from [ticketId] — the user finished viewing (and potentially
  /// editing) this ticket, so it's now safe to apply the external edit.
  void _deferUntilViewChanges(String ticketId, String rootPath) {
    late final VoidCallback listener;
    listener = () {
      if (_activeTicketViewRegistry.activeTicketId.value != ticketId) {
        _activeTicketViewRegistry.activeTicketId.removeListener(listener);
        unawaited(reconcile(ticketId, rootPath));
      }
    };
    _activeTicketViewRegistry.activeTicketId.addListener(listener);
  }

  Future<Ticket?> _findByTicketId(String ticketId) async {
    final all = await _repository.getAllTickets();
    for (final ticket in all) {
      if (ticket.ticketId == ticketId) return ticket;
    }
    return null;
  }

  /// Applies a successful (or partially-successful) parse [result] to
  /// [ticket] in the database, then fires the same async embedding-
  /// regen trigger `TicketsCubit` uses for any other content edit.
  /// Returns the updated [Ticket] (the same post-apply title/description
  /// [reconcile] needs to drive its own wikilink reindex/cascade step),
  /// or `null` for the unreachable [Unparseable] case (callers already
  /// check this before calling).
  Future<Ticket?> _apply(Ticket ticket, TicketMarkdownParseResult result) async {
    final Map<String, Object?> fields;
    final String title;
    final String body;
    switch (result) {
      case ParsedOk(fields: final f, title: final t, body: final b):
        fields = f;
        title = t;
        body = b;
      case ParsedPartial(validFields: final f, title: final t, body: final b):
        fields = f;
        title = t;
        body = b;
      case Unparseable():
        return null; // unreachable — callers check this case before calling
    }

    // `fields[key]` alone can't distinguish "field absent (invalid, keep
    // DB value)" from "field present but legitimately null (clear it)" —
    // both read as `null` from the map. Only pass a setter when the key
    // is actually present, so `copyWith`'s "omit = leave unchanged"
    // semantics apply correctly to an invalid/absent field.
    final resolvedTitle = title.isEmpty ? ticket.title : title;
    final updated = ticket.copyWith(
      title: resolvedTitle,
      description: () => body,
      priority: fields[TicketMarkdownTemplate.priority] as TicketPriority?,
      type: fields[TicketMarkdownTemplate.type] as TicketType?,
      estimate: fields.containsKey(TicketMarkdownTemplate.estimate)
          ? () => fields[TicketMarkdownTemplate.estimate] as int?
          : null,
      timeSpent: fields.containsKey(TicketMarkdownTemplate.timeSpent)
          ? () => fields[TicketMarkdownTemplate.timeSpent] as int?
          : null,
    );
    // No `estimateEdited: true` here — [TicketMarkdownSerializer.serialize]
    // always writes an `estimate:` frontmatter line (even `null`), so
    // `fields.containsKey(TicketMarkdownTemplate.estimate)` is `true` for
    // every successfully parsed file regardless of whether this specific
    // reconcile pass actually changed the value, and can't be used as an
    // edited signal the way [TicketRepository.updateTicket] needs. Leaving
    // both flags at their `false` default means a reconcile triggered by
    // some other field (title, priority, ...) changing never relocks an
    // `aiSuggested` estimate it didn't touch — strictly safer than this
    // call unconditionally stamping `manual` on every reconcile, which is
    // what happened before `estimateSource` existed to get it wrong.
    await _repository.updateTicket(updated);

    final status = fields[TicketMarkdownTemplate.status] as TicketStatus?;
    if (status != null && status != ticket.status) {
      await _repository.updateTicketStatus(ticket.id, status);
    }

    if (resolvedTitle != ticket.title || body != (ticket.description ?? '')) {
      unawaited(
        _embeddingProvider
            .embed('$resolvedTitle\n\n$body')
            .then((bytes) => _repository.updateEmbedding(ticket.id, bytes)),
      );
    }

    return updated;
  }
}
