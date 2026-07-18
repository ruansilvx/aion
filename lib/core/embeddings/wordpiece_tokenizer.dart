// core/embeddings/wordpiece_tokenizer.dart — WordPiece tokenizer (core layer).

/// A minimal WordPiece tokenizer, matching the tokenization scheme used by
/// BERT-family models (including all-MiniLM-L6-v2). Pure Dart, no Flutter
/// dependency, so it stays importable from `bin/ticket_lint.dart` if a
/// future change needs tokenization outside the app — though today only
/// [BundledEmbeddingProvider] uses it.
///
/// This is a from-scratch, dependency-free implementation (no maintained
/// pure-Dart WordPiece package exists on pub.dev at the time of writing),
/// so it deliberately handles only the common case: lowercase, whitespace
/// and basic-punctuation splitting, greedy longest-match-first subword
/// matching against [vocab]. It has not been cross-checked token-for-token
/// against a reference (e.g. HuggingFace `tokenizers`) implementation —
/// verify against known-good output before relying on embedding quality.
class WordPieceTokenizer {
  /// Creates a tokenizer backed by [vocab] (token string -> id). [unkToken]
  /// and [maxInputCharsPerWord] follow the standard BERT WordPiece
  /// defaults.
  const WordPieceTokenizer({
    required this.vocab,
    this.unkToken = '[UNK]',
    this.clsToken = '[CLS]',
    this.sepToken = '[SEP]',
    this.maxInputCharsPerWord = 200,
  });

  /// Token string -> vocabulary id, as loaded from the model's vocab file.
  final Map<String, int> vocab;

  /// Token substituted for any word that can't be decomposed into known
  /// subwords.
  final String unkToken;

  /// Sequence-start token id, prepended to every tokenized input.
  final String clsToken;

  /// Sequence-end token id, appended to every tokenized input.
  final String sepToken;

  /// Words longer than this many characters are tokenized directly as
  /// [unkToken] without attempting subword decomposition (matches standard
  /// WordPiece behavior — avoids pathological backtracking on garbage
  /// input).
  final int maxInputCharsPerWord;

  /// Tokenizes [text] into vocabulary ids, including leading [clsToken]
  /// and trailing [sepToken].
  List<int> encode(String text) {
    final ids = <int>[?vocab[clsToken]];
    for (final word in _basicSplit(text)) {
      ids.addAll(_wordPieceTokenize(word));
    }
    if (vocab[sepToken] case final id?) ids.add(id);
    return ids;
  }

  /// Lowercases and splits on whitespace and basic ASCII punctuation,
  /// keeping punctuation characters as their own tokens (standard BERT
  /// "basic tokenizer" behavior, simplified — no accent stripping or
  /// CJK-specific character splitting).
  List<String> _basicSplit(String text) {
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    final words = <String>[];
    void flush() {
      if (buffer.isNotEmpty) {
        words.add(buffer.toString());
        buffer.clear();
      }
    }

    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'\s').hasMatch(char)) {
        flush();
      } else if (RegExp(r'[!-/:-@\[-`{-~]').hasMatch(char)) {
        flush();
        words.add(char);
      } else {
        buffer.write(char);
      }
    }
    flush();
    return words;
  }

  /// Greedy longest-match-first subword decomposition of a single [word],
  /// continuation subwords prefixed `##` per the WordPiece convention.
  List<int> _wordPieceTokenize(String word) {
    if (word.length > maxInputCharsPerWord) {
      return [?vocab[unkToken]];
    }

    final subTokenIds = <int>[];
    var start = 0;
    while (start < word.length) {
      var end = word.length;
      String? matched;
      while (start < end) {
        var candidate = word.substring(start, end);
        if (start > 0) candidate = '##$candidate';
        if (vocab.containsKey(candidate)) {
          matched = candidate;
          break;
        }
        end--;
      }
      if (matched == null) {
        return [?vocab[unkToken]];
      }
      subTokenIds.add(vocab[matched]!);
      start = end;
    }
    return subTokenIds;
  }
}
