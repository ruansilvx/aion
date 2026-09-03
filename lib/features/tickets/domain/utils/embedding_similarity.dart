// domain/utils/embedding_similarity.dart — shared cosine-similarity utility (domain layer).

import 'dart:math' as math;
import 'dart:typed_data';

/// Cosine similarity between two embedding vectors serialized as raw
/// `Float32List` bytes (the format `EmbeddingProvider.embed` produces).
/// Returns `0.0` for a zero-length vector or a zero vector, rather than
/// dividing by zero.
///
/// Shared by `TicketDocumentSearchService` (page/resource documentation
/// search) and `TicketEstimationSuggester` (complexity/estimate
/// calibration) — the only piece of similarity-scan logic the two features
/// genuinely share. See
/// `AIO-75`
/// §1.3.
double cosineSimilarity(Uint8List a, Uint8List b) {
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
