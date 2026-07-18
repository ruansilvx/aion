// data/services/ticket_db_reconstruction_service.dart — TicketDbReconstructionService (data layer).

import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/markdown/ticket_markdown_parse_result.dart';
import 'package:aion/core/markdown/ticket_markdown_serializer.dart';
import 'package:aion/core/markdown/ticket_markdown_template.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

/// Report produced by [TicketDbReconstructionService.reconstruct]:
/// how many `tickets/*.md` files were successfully imported vs. skipped
/// as unparseable, so a caller can surface an accurate summary.
class TicketReconstructionReport {
  /// Creates a [TicketReconstructionReport].
  const TicketReconstructionReport({
    required this.importedCount,
    required this.skippedPaths,
  });

  /// Number of files successfully parsed and upserted.
  final int importedCount;

  /// File paths that were skipped because they failed to parse, in the
  /// same order they were encountered.
  final List<String> skippedPaths;
}

/// Rebuilds a project's database from its git-tracked `tickets/*.md`
/// files — the recovery mechanism that makes the database "fully
/// disposable and reconstructable," per design.md's relationship-
/// between-the-three-layers section.
///
/// Built and unit-tested standalone. **Not wired into any UI flow** —
/// there is no "open/clone an existing project" onboarding flow yet for
/// it to be called from (see proposal.md's Non-goals). The natural
/// future caller is whatever that flow ends up being.
///
/// **Known limitation**: [TicketRepository.createTicket] always
/// generates a fresh sequential `ticketId` and ignores whatever's on the
/// passed [Ticket] (see its own dartdoc) — so importing a `.md` file
/// whose `ticketId` has no matching existing row (the genuine
/// second-machine case, not just re-running against an already-imported
/// DB) currently gets assigned a *new* `ticketId` rather than preserving
/// the one the file is named after. That breaks the file/DB naming
/// correspondence this whole sync mechanism depends on. Fixing this
/// needs a repository-level change (an insert path that preserves a
/// caller-supplied `ticketId`) out of scope for this task list; flagged
/// here rather than silently shipped as if it round-trips correctly.
class TicketDbReconstructionService {
  /// Creates a [TicketDbReconstructionService] using [_repository],
  /// [_serializer], and [_embeddingProvider] (for the post-import bulk
  /// backfill).
  TicketDbReconstructionService(
    this._repository,
    this._serializer,
    this._embeddingProvider,
  );

  final TicketRepository _repository;
  final TicketMarkdownSerializer _serializer;
  final EmbeddingProvider _embeddingProvider;

  /// Reads every `tickets/*.md` file under [rootPath], parses each, and
  /// inserts/upserts the corresponding row via [_repository].
  /// Unparseable files are skipped and reported, not fatal to the run.
  /// After import, triggers [_embeddingProvider] in bulk for every
  /// imported ticket lacking a local embedding.
  Future<TicketReconstructionReport> reconstruct(String rootPath) async {
    final ticketsDir = Directory('$rootPath/tickets');
    if (!await ticketsDir.exists()) {
      return const TicketReconstructionReport(
        importedCount: 0,
        skippedPaths: [],
      );
    }

    final existing = await _repository.getAllTickets();
    final existingByTicketId = {for (final t in existing) t.ticketId: t};

    var importedCount = 0;
    final skippedPaths = <String>[];
    final imported = <Ticket>[];

    await for (final entity in ticketsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;

      final result = _serializer.parse(await entity.readAsString());
      final ticket = _buildTicket(result, existingByTicketId);
      if (ticket == null) {
        skippedPaths.add(entity.path);
        continue;
      }

      if (existingByTicketId.containsKey(ticket.ticketId)) {
        await _repository.updateTicket(ticket);
      } else {
        await _repository.createTicket(ticket);
      }
      imported.add(ticket);
      importedCount++;
    }

    for (final ticket in imported) {
      if (ticket.embedding != null) continue;
      final bytes = await _embeddingProvider.embed(
        '${ticket.title}\n\n${ticket.description ?? ''}',
      );
      await _repository.updateEmbedding(ticket.id, bytes);
    }

    return TicketReconstructionReport(
      importedCount: importedCount,
      skippedPaths: skippedPaths,
    );
  }

  /// Builds a [Ticket] from a parse [result], reusing the existing row's
  /// internal `id` when [existingByTicketId] already has one for this
  /// `ticketId` (an update), or generating a fresh UUID (a new insert —
  /// covers the second-machine case where the local DB has no row yet).
  /// Returns `null` for [Unparseable] or any result missing a usable
  /// `ticketId`/`type`/`status` (the fields with no safe default).
  Ticket? _buildTicket(
    TicketMarkdownParseResult result,
    Map<String, Ticket> existingByTicketId,
  ) {
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
        return null;
    }

    final ticketId = fields[TicketMarkdownTemplate.ticketId] as String?;
    final type = fields[TicketMarkdownTemplate.type] as TicketType?;
    final status = fields[TicketMarkdownTemplate.status] as TicketStatus?;
    if (ticketId == null || type == null || status == null) return null;

    final existing = existingByTicketId[ticketId];
    final createdAt =
        fields[TicketMarkdownTemplate.createdAt] as DateTime? ??
        existing?.createdAt ??
        DateTime.now();
    final updatedAt =
        fields[TicketMarkdownTemplate.updatedAt] as DateTime? ?? DateTime.now();

    return Ticket(
      id: existing?.id ?? const Uuid().v4(),
      ticketId: ticketId,
      type: type,
      title: title.isEmpty ? (existing?.title ?? ticketId) : title,
      description: body.isEmpty ? null : body,
      status: status,
      priority:
          fields[TicketMarkdownTemplate.priority] as TicketPriority? ??
          existing?.priority ??
          TicketPriority.none,
      parentId: fields.containsKey(TicketMarkdownTemplate.parentId)
          ? fields[TicketMarkdownTemplate.parentId] as String?
          : existing?.parentId,
      embedding: existing?.embedding,
      estimate: fields.containsKey(TicketMarkdownTemplate.estimate)
          ? fields[TicketMarkdownTemplate.estimate] as int?
          : existing?.estimate,
      timeSpent: fields.containsKey(TicketMarkdownTemplate.timeSpent)
          ? fields[TicketMarkdownTemplate.timeSpent] as int?
          : existing?.timeSpent,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
