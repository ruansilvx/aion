// presentation/cubit/ticket_context_enricher.dart — TicketContextEnricher orchestrator (presentation layer).

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_link_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_link_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/domain/utils/embedding_similarity.dart';
import 'package:aion/features/tickets/domain/utils/ticket_link_direction.dart';

/// Assembles a `## Related tickets` Markdown section for a spawned chat's
/// opening context, combining a structured walk of a [Ticket]'s ancestor chain
/// and direct [TicketLinkRepository] links with an embedding-similarity scan
/// over every other live ticket. Placed alongside
/// `TicketRollupRecomputer`/`TicketEstimationSuggester` — the two existing
/// orchestrator classes `TicketsCubit` constructs once and delegates a
/// self-contained walk to — because this is judgment logic (what counts as
/// "related enough") rather than a pure data-access concern, per
/// `project.md`'s Cubit-owns-domain-logic convention. Consumed by both
/// `TicketsCubit._assembleExecutionContext` and
/// `TicketsCubit._assembleStageContext` (the latter also covers
/// `retryDesignSync`'s re-assembly, since it calls `_assembleStageContext`
/// directly). See `AIO-2229` §1.
class TicketContextEnricher {
  /// Creates a [TicketContextEnricher] backed by [_repository].
  /// [linkRepository]/[embeddingProvider] are optional — when
  /// [linkRepository] is `null`, [relatedTicketsSection] skips the direct-
  /// links pass; when [embeddingProvider] is `null`, it skips the
  /// embedding-similarity pass. Mirrors
  /// `TicketEstimationSuggester`'s constructor shape (required repository,
  /// optional collaborators via named parameters, `late final` backing
  /// fields) so the two orchestrator classes read as the same family.
  TicketContextEnricher(
    this._repository, {
    TicketLinkRepository? linkRepository,
    EmbeddingProvider? embeddingProvider,
  }) {
    _linkRepository = linkRepository;
    _embeddingProvider = embeddingProvider;
  }

  final TicketRepository _repository;
  late final TicketLinkRepository? _linkRepository;
  late final EmbeddingProvider? _embeddingProvider;

  /// Minimum cosine similarity for an embedding-scan match to be included.
  static const _similarityThreshold = 0.75;

  /// Safety cap on how many embedding-similarity matches are included,
  /// applied after [_similarityThreshold] filtering — not a fixed quota
  /// that always fires.
  static const _maxSimilarTickets = 5;

  /// Maximum characters of a related ticket's description rendered as its
  /// bullet snippet, bounding how much any single related ticket can
  /// inflate the assembled prompt.
  static const _descriptionSnippetLength = 400;

  /// Returns a `## Related tickets` Markdown block for [ticket], or `''`
  /// if there is nothing to add — every call site checks for an empty
  /// return and skips appending the section header entirely, so a ticket
  /// with no parent, no links, and no embedding provider configured
  /// produces exactly today's output, unchanged.
  ///
  /// Combines, in this fixed order: [ticket]'s ancestor chain (nearest
  /// first, walking `parentId` upward), every direct [TicketLinkRepository]
  /// link (skipped entirely if this was constructed without one), and an
  /// embedding-similarity scan over every other live ticket's `embedding`
  /// column (skipped entirely if constructed without an
  /// [EmbeddingProvider]) — excluding [ticket] itself and anything the
  /// structured walk already surfaced.
  Future<String> relatedTicketsSection(Ticket ticket) async {
    final all = await _repository.getAllTickets();
    final byId = {for (final t in all) t.id: t};

    final structuredIds = <String>{};

    final ancestors = <Ticket>[];
    var current = ticket.parentId == null ? null : byId[ticket.parentId];
    while (current != null && structuredIds.add(current.id)) {
      ancestors.add(current);
      final parentId = current.parentId;
      current = parentId == null ? null : byId[parentId];
    }

    final links = <(Ticket, TicketLinkType)>[];
    final linkRepo = _linkRepository;
    if (linkRepo != null) {
      final rows = await linkRepo.getLinksForTicket(ticket.id);
      for (final row in rows) {
        final otherId = row.sourceTicketId == ticket.id
            ? row.targetTicketId
            : row.sourceTicketId;
        final other = byId[otherId];
        if (other == null) continue;
        final type = relativeLinkType(row, ticket.id);
        links.add((other, type));
        structuredIds.add(other.id);
      }
    }

    final similar = <Ticket>[];
    final embeddingProvider = _embeddingProvider;
    if (embeddingProvider != null) {
      final queryVector = await embeddingProvider.embed(
        '${ticket.title}\n\n${ticket.description ?? ''}',
      );
      final scored = <(Ticket, double)>[
        for (final other in byId.values)
          if (other.id != ticket.id &&
              !structuredIds.contains(other.id) &&
              other.embedding != null)
            (other, cosineSimilarity(queryVector, other.embedding!)),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      similar.addAll(
        scored
            .where((entry) => entry.$2 >= _similarityThreshold)
            .take(_maxSimilarTickets)
            .map((entry) => entry.$1),
      );
    }

    if (ancestors.isEmpty && links.isEmpty && similar.isEmpty) return '';

    final buffer = StringBuffer()..writeln('## Related tickets');
    for (final ancestor in ancestors) {
      buffer.writeln(
        '- ${_typeLabel(ancestor.type.name)} — "${ancestor.title}": '
        '${_snippet(ancestor.description)}',
      );
    }
    for (final (other, type) in links) {
      buffer.writeln(
        '- ${type.name} — "${other.title}": ${_snippet(other.description)}',
      );
    }
    for (final other in similar) {
      buffer.writeln(
        '- similar — "${other.title}": ${_snippet(other.description)}',
      );
    }
    return buffer.toString().trim();
  }

  /// Capitalizes [typeName] (e.g. `'epic'` → `'Epic'`) for use as an
  /// ancestor bullet's relationship label — matches how
  /// `TicketsCubit._assembleStageContext`'s existing `verifying`/
  /// `archived` branch already labels children by type name.
  String _typeLabel(String typeName) => typeName.isEmpty
      ? typeName
      : typeName[0].toUpperCase() + typeName.substring(1);

  /// [description] truncated to [_descriptionSnippetLength] characters
  /// (with a trailing `…` when longer), or the literal `(no description)`
  /// when [description] is `null` or empty.
  String _snippet(String? description) {
    if (description == null || description.isEmpty) return '(no description)';
    if (description.length <= _descriptionSnippetLength) return description;
    return '${description.substring(0, _descriptionSnippetLength)}…';
  }
}
