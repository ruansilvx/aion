// data/services/ticket_repair_service.dart — TicketRepairService (data layer).

import 'dart:io';

import 'package:aion/core/markdown/ticket_markdown_linter.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sync_status.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

/// DB-aware repair actions for a `needsRepair` `resource`/`page` ticket.
/// Both actions are explicit, user- or agent-triggered — never run
/// automatically, per the "flag, don't silently fix" rule from
/// design.md's deep dive.
class TicketRepairService {
  /// Creates a [TicketRepairService] using [_repository] and [_serializer].
  TicketRepairService(this._repository, this._serializer);

  final TicketRepository _repository;
  final TicketMarkdownSerializer _serializer;

  /// Re-validates the current file for the ticket identified by
  /// human-readable [ticketId], applying whatever
  /// [lintTicketMarkdown] can safely fix. Returns whether the ticket is
  /// now [TicketSyncStatus.synced] — `false` means the content couldn't
  /// be confidently reformatted and [restoreFromLastKnownGood] is the
  /// remaining option.
  Future<bool> reformat(String ticketId, String rootPath) async {
    final file = File('$rootPath/tickets/$ticketId.md');
    if (!await file.exists()) return false;

    final reformatted = lintTicketMarkdown(
      await file.readAsString(),
      _serializer,
    );
    if (reformatted == null) return false;

    await file.writeAsString(reformatted);
    final ticket = await _findByTicketId(ticketId);
    if (ticket != null) {
      await _repository.updateSyncStatus(ticket.id, TicketSyncStatus.synced);
    }
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
