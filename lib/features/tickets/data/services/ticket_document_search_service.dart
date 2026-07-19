// data/services/ticket_document_search_service.dart — TicketDocumentSearchService (data layer).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';

/// Embedding-based search over `page`/`resource` tickets for the
/// Documentation section.
///
/// The app only ever *writes* ticket embeddings today (on create/edit, via
/// [EmbeddingProvider], see `TicketsCubit._triggerEmbeddingRegen`) — there
/// is no existing similarity query to reuse. This service is the new
/// query-side piece: a brute-force cosine-similarity scan over every
/// page/resource ticket's already-populated `embedding` column, consistent
/// with `project.md`'s Foundational Decision #1 ("brute-force cosine
/// similarity... sufficient at personal scale").
class TicketDocumentSearchService {
  /// Creates a [TicketDocumentSearchService] backed by [_embeddingProvider]
  /// (to embed the query text) and [_repository] (to fetch candidate
  /// tickets).
  TicketDocumentSearchService(this._embeddingProvider, this._repository);

  final EmbeddingProvider _embeddingProvider;
  final TicketRepository _repository;

  /// Types eligible for documentation search — the Documentation section's
  /// scope, never board tickets.
  static const _documentTypes = [TicketType.page, TicketType.resource];

  /// Returns `page`/`resource` tickets ranked by cosine similarity to
  /// [query], highest similarity first, capped at [limit] results.
  /// Tickets with no embedding yet (e.g. never regenerated) are excluded,
  /// since they have nothing to compare against.
  Future<List<Ticket>> search(String query, {int limit = 20}) async {
    final queryVector = await _embeddingProvider.embed(query);
    final candidates = await _repository.getAllTicketsByType(_documentTypes);

    final scored = <(Ticket, double)>[];
    for (final ticket in candidates) {
      final embedding = ticket.embedding;
      if (embedding == null) continue;
      scored.add((ticket, _cosineSimilarity(queryVector, embedding)));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    return scored.take(limit).map((entry) => entry.$1).toList();
  }

  /// Cosine similarity between two embedding vectors serialized as raw
  /// `Float32List` bytes (the format [EmbeddingProvider.embed] produces).
  /// Returns `0.0` for a zero-length vector or a zero vector, rather than
  /// dividing by zero.
  double _cosineSimilarity(Uint8List a, Uint8List b) {
    final vecA = a.buffer.asFloat32List(a.offsetInBytes, a.lengthInBytes ~/ 4);
    final vecB = b.buffer.asFloat32List(b.offsetInBytes, b.lengthInBytes ~/ 4);
    final length = vecA.length < vecB.length ? vecA.length : vecB.length;
    if (length == 0) return 0.0;

    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < length; i++) {
      dot += vecA[i] * vecB[i];
      normA += vecA[i] * vecA[i];
      normB += vecB[i] * vecB[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }
}
