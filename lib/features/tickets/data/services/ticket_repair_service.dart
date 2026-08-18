// data/services/ticket_repair_service.dart — TicketRepairService (data layer).

import 'dart:io';

import 'package:aion/core/markdown/ticket_markdown_linter.dart';
import 'package:aion/core/markdown/ticket_markdown_parse_result.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/features/tickets/data/services/ticket_parent_trash_service.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

/// DB-aware repair actions for a `needsRepair` `resource`/`page` ticket.
/// Both actions are explicit, user- or agent-triggered — never run
/// automatically, per the "flag, don't silently fix" rule from
/// design.md's deep dive.
class TicketRepairService {
  /// Creates a [TicketRepairService] using [_repository], [_serializer],
  /// and [_parentTrashService] — the last shared with
  /// `TicketMarkdownReconciler` so [reformat] applies the identical
  /// `parentId`/`deletedAt` semantics (see [reformat]'s dartdoc for why
  /// this is required, not optional).
  TicketRepairService(
    this._repository,
    this._serializer,
    this._parentTrashService,
  );

  final TicketRepository _repository;
  final TicketMarkdownSerializer _serializer;
  final TicketParentTrashService _parentTrashService;

  /// Re-validates the current file for the ticket identified by
  /// human-readable [ticketId], applying whatever [lintTicketMarkdown]
  /// can safely fix, then re-running [TicketParentTrashService
  /// .applyFromParsedFields] against the (possibly still-changed)
  /// `parentId`/`deletedAt`. The latter step exists because
  /// `needsRepair` now has two causes: `Unparseable` content, for which
  /// "does the trimmed file re-parse" was always a sufficient success
  /// check, and a syntactically-valid-but-rejected `parentId`/
  /// `deletedAt` (see `TicketMarkdownReconciler`), for which a file that
  /// re-parses fine can still be wrong — without this second check,
  /// [reformat] would mark such a ticket [TicketSyncStatus.synced]
  /// without the file's value ever actually matching the database.
  /// Returns whether the ticket is now `synced` — `false` means the
  /// content couldn't be confidently reformatted (or the reformatted
  /// content's `parentId`/`deletedAt` was still rejected) and
  /// [restoreFromLastKnownGood] is the remaining option.
  Future<bool> reformat(String ticketId, String rootPath) async {
    final file = File('$rootPath/tickets/$ticketId.md');
    if (!await file.exists()) return false;

    final reformatted = lintTicketMarkdown(
      await file.readAsString(),
      _serializer,
    );
    if (reformatted == null) return false;

    final ticket = await _findByTicketId(ticketId);
    if (ticket == null) return false;

    final result = _serializer.parse(reformatted);
    final fields = switch (result) {
      ParsedOk(fields: final f) => f,
      ParsedPartial(validFields: final f) => f,
      Unparseable() => null,
    };
    if (fields != null &&
        !await _parentTrashService.applyFromParsedFields(ticket, fields)) {
      return false;
    }

    await file.writeAsString(reformatted);
    await _repository.updateSyncStatus(ticket.id, TicketSyncStatus.synced);
    return true;
  }

  /// Overwrites the file for the ticket identified by human-readable
  /// [ticketId] with a fresh serialization of its current database row
  /// — the "last known good" state, since a failed reconcile never
  /// touches the database. Always resolves to
  /// [TicketSyncStatus.synced].
  Future<void> restoreFromLastKnownGood(
    String ticketId,
    String rootPath,
  ) async {
    final ticket = await _findByTicketId(ticketId);
    if (ticket == null) return;

    final file = File('$rootPath/tickets/$ticketId.md');
    await file.parent.create(recursive: true);
    await file.writeAsString(_serializer.serialize(ticket));
    await _repository.updateSyncStatus(ticket.id, TicketSyncStatus.synced);
  }

  Future<Ticket?> _findByTicketId(String ticketId) async {
    final all = await _repository.getAllTickets();
    for (final ticket in all) {
      if (ticket.ticketId == ticketId) return ticket;
    }
    return null;
  }
}
