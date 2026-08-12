import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/domain/utils/embedding_similarity.dart';

/// Builds a raw `Float32List` embedding of [values], serialized the same
/// way `EmbeddingProvider.embed` does.
Uint8List _vector(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

void main() {
  test('identical vectors have similarity 1.0', () {
    final v = _vector([1.0, 2.0, 3.0]);
    expect(cosineSimilarity(v, v), closeTo(1.0, 1e-6));
  });

  test('orthogonal vectors have similarity 0.0', () {
    expect(
      cosineSimilarity(_vector([1.0, 0.0]), _vector([0.0, 1.0])),
      closeTo(0.0, 1e-6),
    );
  });

  test('opposite vectors have similarity -1.0', () {
    expect(
      cosineSimilarity(_vector([1.0, 0.0]), _vector([-1.0, 0.0])),
      closeTo(-1.0, 1e-6),
    );
  });

  test('a zero-length vector returns 0.0 rather than dividing by zero', () {
    expect(cosineSimilarity(_vector([]), _vector([])), 0.0);
  });

  test('a zero vector returns 0.0 rather than dividing by zero', () {
    expect(
      cosineSimilarity(_vector([0.0, 0.0]), _vector([1.0, 0.0])),
      0.0,
    );
  });

  test('mismatched lengths compare only over the shorter length', () {
    // Both share [1.0, 0.0] over the first two dimensions — the third
    // dimension on the longer vector is ignored.
    final result = cosineSimilarity(
      _vector([1.0, 0.0]),
      _vector([1.0, 0.0, 99.0]),
    );
    expect(result, closeTo(1.0, 1e-6));
  });
}
