// test/features/tickets/domain/utils/ticket_rollup_calculator_test.dart —
// computeRollups sum/null/recursion/cycle-guard tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/domain/utils/ticket_rollup_calculator.dart';

RollupNode _node(String id, {String? parentId, int? estimate, int? timeSpent}) =>
    (id: id, parentId: parentId, estimate: estimate, timeSpent: timeSpent);

void main() {
  group('computeRollups', () {
    test('a childless ticket produces no entry', () {
      final result = computeRollups([_node('a', estimate: 30)]);
      expect(result, isEmpty);
    });

    test('a single-level parent with 2 children sums correctly', () {
      final result = computeRollups([
        _node('parent'),
        _node('child1', parentId: 'parent', estimate: 10, timeSpent: 5),
        _node('child2', parentId: 'parent', estimate: 20, timeSpent: 15),
      ]);
      expect(result['parent']!.estimateRollup, 30);
      expect(result['parent']!.timeSpentRollup, 20);
      expect(result.containsKey('child1'), isFalse);
      expect(result.containsKey('child2'), isFalse);
    });

    test(
      "a 3-level chain recurses correctly (grandparent's rollup reflects "
      'grandchild values through the parent)',
      () {
        final result = computeRollups([
          _node('grandparent'),
          _node('parent', parentId: 'grandparent'),
          _node('child', parentId: 'parent', estimate: 5),
        ]);
        expect(result['parent']!.estimateRollup, 5);
        expect(result['grandparent']!.estimateRollup, 5);
      },
    );

    test('a subtree with every value null produces null, not 0', () {
      final result = computeRollups([
        _node('parent'),
        _node('child1', parentId: 'parent'),
        _node('child2', parentId: 'parent'),
      ]);
      expect(result['parent']!.estimateRollup, isNull);
      expect(result['parent']!.timeSpentRollup, isNull);
    });

    test('a mixed subtree sums only the set values', () {
      final result = computeRollups([
        _node('parent'),
        _node('child1', parentId: 'parent', estimate: 10),
        _node('child2', parentId: 'parent'),
        _node('child3', parentId: 'parent', estimate: 5),
      ]);
      expect(result['parent']!.estimateRollup, 15);
    });

    test(
      "a parent's own value plus children's values both contribute "
      '(Jira-style addition)',
      () {
        final result = computeRollups([
          _node('parent', estimate: 30),
          _node('child1', parentId: 'parent', estimate: 120),
          _node('child2', parentId: 'parent', estimate: 150),
        ]);
        expect(result['parent']!.estimateRollup, 300);
      },
    );

    test('estimateCount/timeSpentCount count contributing live tickets', () {
      final result = computeRollups([
        _node('parent', estimate: 10),
        _node('child1', parentId: 'parent', estimate: 20),
        _node('child2', parentId: 'parent'),
        _node('child3', parentId: 'parent', timeSpent: 5),
      ]);
      expect(result['parent']!.estimateCount, 2);
      expect(result['parent']!.timeSpentCount, 1);
    });

    test('a cycle-guard case (malformed input) does not hang', () {
      final result = computeRollups([
        _node('a', parentId: 'b', estimate: 1),
        _node('b', parentId: 'a', estimate: 2),
      ]);
      // Both nodes have a child (each other), so both are internal nodes
      // — the important assertion is simply that this terminates and
      // returns without throwing/looping forever.
      expect(result.keys, containsAll(['a', 'b']));
    });
  });
}
