// core/embeddings/bundled_embedding_provider.dart — BundledEmbeddingProvider implementation (core layer).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/core/embeddings/wordpiece_tokenizer.dart';

/// On-device, no-external-dependency [EmbeddingProvider] backed by a
/// bundled, int8-quantized all-MiniLM-L6-v2 ONNX model.
///
/// Uses `flutter_onnxruntime`'s single cross-platform API
/// (`OnnxRuntime.createSessionFromAsset`) rather than a manual native/web
/// conditional split — the plugin already abstracts that internally
/// (native wrappers on desktop/mobile, WASM on web), unlike
/// `AppDatabase`'s `_openConnection()` split, which exists because
/// `drift`/`sqlite3` genuinely need different backing implementations per
/// platform. See design.md's Embedding pipeline section for the fuller
/// rationale; this class corrects that doc's assumption of a manual split.
///
/// The bundled ONNX graph (`sentence-transformers/all-MiniLM-L6-v2`,
/// int8-quantized) only exposes `last_hidden_state` — a per-token
/// hidden-state tensor, not a pre-pooled sentence vector — so [embed]
/// performs the model's standard mean-pooling-over-`attention_mask` plus
/// L2-normalization itself, matching the reference sentence-transformers
/// pipeline for this model.
class BundledEmbeddingProvider implements EmbeddingProvider {
  /// Bundled asset path for the quantized ONNX model.
  static const _modelAssetPath = 'assets/models/minilm-l6-v2-int8.onnx';

  /// Bundled asset path for the WordPiece vocabulary, one token per line
  /// (line number == vocabulary id), matching the standard BERT vocab.txt
  /// format.
  static const _vocabAssetPath = 'assets/models/minilm-l6-v2-vocab.txt';

  /// Fixed sequence length the model was exported for. Longer inputs are
  /// truncated, shorter ones padded with the `[PAD]` token (id `0` in the
  /// standard BERT vocab layout).
  static const _maxSequenceLength = 256;

  /// Hidden-state width of `last_hidden_state`, fixed by the exported
  /// all-MiniLM-L6-v2 graph.
  static const _hiddenSize = 384;

  OrtSession? _session;
  WordPieceTokenizer? _tokenizer;

  /// Loads the ONNX session and tokenizer vocabulary on first use. Cheap
  /// to call repeatedly — subsequent calls reuse the already-loaded
  /// session/tokenizer.
  Future<(OrtSession, WordPieceTokenizer)> _ensureLoaded() async {
    final existingSession = _session;
    final existingTokenizer = _tokenizer;
    if (existingSession != null && existingTokenizer != null) {
      return (existingSession, existingTokenizer);
    }

    final vocabText = await _loadVocabText();
    final vocab = <String, int>{
      for (final (i, line) in const LineSplitter().convert(vocabText).indexed)
        line: i,
    };
    final tokenizer = WordPieceTokenizer(vocab: vocab);

    final ort = OnnxRuntime();
    final session = await ort.createSessionFromAsset(_modelAssetPath);

    _tokenizer = tokenizer;
    _session = session;
    return (session, tokenizer);
  }

  Future<String> _loadVocabText() => rootBundle.loadString(_vocabAssetPath);

  @override
  Future<Uint8List> embed(String text) async {
    final (session, tokenizer) = await _ensureLoaded();

    var ids = tokenizer.encode(text);
    if (ids.length > _maxSequenceLength) {
      ids = ids.sublist(0, _maxSequenceLength);
    }
    final validTokenCount = ids.length;
    final paddedIds = Int64List.fromList(
      List<int>.generate(
        _maxSequenceLength,
        (i) => i < validTokenCount ? ids[i] : 0,
      ),
    );
    final attentionMaskInts = List<int>.generate(
      _maxSequenceLength,
      (i) => i < validTokenCount ? 1 : 0,
    );
    final attentionMask = Int64List.fromList(attentionMaskInts);
    final tokenTypeIds = Int64List(_maxSequenceLength);

    // flutter_onnxruntime's OrtValue.fromList infers int32 from a plain
    // List<int> (only promoting to int64 if a value exceeds int32 range) —
    // this model's exported graph requires int64 inputs regardless of
    // value range, so the typed Int64List must be passed explicitly.
    final shape = [1, _maxSequenceLength];
    final inputs = {
      'input_ids': await OrtValue.fromList(paddedIds, shape),
      'attention_mask': await OrtValue.fromList(attentionMask, shape),
      'token_type_ids': await OrtValue.fromList(tokenTypeIds, shape),
    };

    final outputs = await session.run(inputs);
    final hiddenStates =
        (await outputs['last_hidden_state']!.asFlattenedList())
            .cast<double>();

    return _meanPoolAndNormalize(hiddenStates, attentionMask);
  }

  /// Mean-pools `last_hidden_state` over non-padding positions (per
  /// `attentionMask`) and L2-normalizes the result — the standard
  /// sentence-transformers pooling head for all-MiniLM-L6-v2, which this
  /// exported graph omits.
  Uint8List _meanPoolAndNormalize(
    List<double> hiddenStates,
    List<int> attentionMask,
  ) {
    final pooled = Float64List(_hiddenSize);
    var validTokenCount = 0;
    for (var pos = 0; pos < _maxSequenceLength; pos++) {
      if (attentionMask[pos] == 0) continue;
      validTokenCount++;
      final offset = pos * _hiddenSize;
      for (var d = 0; d < _hiddenSize; d++) {
        pooled[d] += hiddenStates[offset + d];
      }
    }
    final divisor = validTokenCount == 0 ? 1 : validTokenCount;
    for (var d = 0; d < _hiddenSize; d++) {
      pooled[d] /= divisor;
    }

    var normSquared = 0.0;
    for (final value in pooled) {
      normSquared += value * value;
    }
    final norm = math.sqrt(normSquared);

    final normalized = Float32List(_hiddenSize);
    for (var d = 0; d < _hiddenSize; d++) {
      normalized[d] = norm > 0 ? pooled[d] / norm : 0.0;
    }
    return normalized.buffer.asUint8List();
  }
}
