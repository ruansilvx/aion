# Bundled embedding model — NOT YET SOURCED

`BundledEmbeddingProvider` (`lib/core/embeddings/bundled_embedding_provider.dart`)
expects three files in this directory, none of which exist yet:

- `minilm-l6-v2-int8.onnx` — desktop/mobile native runtime, int8-quantized
  all-MiniLM-L6-v2.
- `minilm-l6-v2.wasm` (or equivalent web export of the same weights) — web
  runtime.
- `minilm-l6-v2-vocab.txt` — the WordPiece tokenizer vocabulary, shared by
  both runtimes so tokenization (and therefore the resulting embedding
  vectors) is identical regardless of platform.

This is `tasks.md` T10 in `aion-arch/changes/storage-embedding-git-sync/`,
left undone by `/apply`: sourcing and verifying real quantized model
weights isn't something an agent should fabricate — a placeholder/fake
binary would fail silently and confusingly at runtime rather than loudly,
which is worse than leaving this documented as a blocker. Someone with a
real ONNX export pipeline (or a verified pre-converted community model)
needs to source and drop these files in, then register them under
`flutter.assets` in `pubspec.yaml` and remove this README.

Until then, `BundledEmbeddingProvider.embed()` throws `UnimplementedError`
with a message pointing back here — see that file.
