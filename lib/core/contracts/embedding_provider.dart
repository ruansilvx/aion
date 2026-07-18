// core/contracts/embedding_provider.dart — EmbeddingProvider abstract interface (core layer).

import 'dart:typed_data';

/// Cross-feature contract for generating a semantic embedding vector from
/// text, entirely on-device — no external server, no cloud call.
///
/// Per `project.md`'s Pattern 1 (dependency inversion via `core`), any
/// feature needing embeddings (today, only `tickets`) depends only on this
/// interface, never on the bundled implementation directly. Implemented by
/// `BundledEmbeddingProvider` (`core/embeddings/bundled_embedding_provider.dart`)
/// and provided once at the app root. See
/// `aion-arch/changes/storage-embedding-git-sync/design.md`.
abstract interface class EmbeddingProvider {
  /// Generates an embedding vector for [text], serialized as raw bytes
  /// suitable for storage in a BLOB column. Never committed to git, not
  /// even as a hash — see the design doc's storage-model reasoning.
  Future<Uint8List> embed(String text);
}
