// data/services/ticket_markdown_reconciler.dart — TicketMarkdownReconciler (data layer).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/markdown/ticket_markdown_parse_result.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/core/markdown/ticket_markdown_template.dart';
import 'package:aion/features/tickets/data/services/active_ticket_view_registry.dart';
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
class TicketMarkdownReconciler {
  /// Creates a [TicketMarkdownReconciler] wired to [_repository] (reads
  /// the current ticket, writes back reconciled fields),
  /// [_serializer] (parses the file), [_activeTicketViewRegistry]
  /// (decides blocking vs. background), and [_embeddingProvider] (the
  /// same regen trigger used by `TicketsCubit`, applied here too so the
  /// two content-change surfaces stay unified).
  TicketMarkdownReconciler(
    this._repository,
    this._serializer,
    this._activeTicketViewRegistry,
    this._embeddingProvider,
  );

  final TicketRepository _repository;
  final TicketMarkdownSerializer _serializer;
  final ActiveTicketViewRegistry _activeTicketViewRegistry;
  final EmbeddingProvider _embeddingProvider;

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
    await _apply(ticket, result);
    await _repository.updateSyncStatus(ticket.id, TicketSyncStatus.synced);
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
  Future<void> _apply(Ticket ticket, TicketMarkdownParseResult result) async {
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
        return; // unreachable — callers check this case before calling
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
  }
}
