// core/embeddings/bundled_embedding_provider.dart — BundledEmbeddingProvider implementation (core layer).

import 'dart:convert';
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
/// **Not yet functional**: the model and tokenizer-vocab assets this class
/// loads (`assets/models/minilm-l6-v2-int8.onnx`,
/// `assets/models/minilm-l6-v2-vocab.txt`) have not been sourced — see
/// `assets/models/README.md`. [embed] throws [UnimplementedError] until
/// they're added and registered in `pubspec.yaml`.
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

  Future<String> _loadVocabText() async {
    try {
      return await rootBundle.loadString(_vocabAssetPath);
    } catch (e) {
      throw UnimplementedError(
        'BundledEmbeddingProvider: model/tokenizer assets are not yet '
        'sourced (see assets/models/README.md). Original error: $e',
      );
    }
  }

  @override
  Future<Uint8List> embed(String text) async {
    final (session, tokenizer) = await _ensureLoaded();

    var ids = tokenizer.encode(text);
    if (ids.length > _maxSequenceLength) {
      ids = ids.sublist(0, _maxSequenceLength);
    }
    final attentionMask = List<int>.filled(ids.length, 1);
    while (ids.length < _maxSequenceLength) {
      ids.add(0);
      attentionMask.add(0);
    }

    final shape = [1, _maxSequenceLength];
    final inputs = {
      'input_ids': await OrtValue.fromList(ids, shape),
      'attention_mask': await OrtValue.fromList(attentionMask, shape),
    };

    final outputs = await session.run(inputs);
    final embeddingValue =
        outputs['sentence_embedding'] ?? outputs.values.first;
    final flat = (await embeddingValue.asFlattenedList()).cast<double>();

    final bytes = Float32List.fromList(flat);
    return bytes.buffer.asUint8List();
  }
}
