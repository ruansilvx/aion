// test/features/tickets/domain/utils/sibling_cluster_test.dart — clusterSiblingsAdjacently tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/utils/sibling_cluster.dart';

Ticket _ticket(String id, {String? parentId}) => Ticket(
  id: id,
  ticketId: 'AIO-$id',
  type: TicketType.task,
  title: id,
  status: 'inProgress',
  parentId: parentId,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// Builds a flat one-level `topmostAncestorId` map for [tickets] — each
/// ticket's own `parentId` stands in directly as its topmost ancestor (or
/// its own id, if it has none), the shape every pre-existing single-level
/// test below already assumes. `TicketsCubit.topmostAncestorIds`'s own
/// multi-hop walk is exercised separately, in the "shared topmost
/// ancestor" group below.
Map<String, String> _flatAncestorMap(List<Ticket> tickets) => {
  for (final t in tickets) t.id: t.parentId ?? t.id,
};

void main() {
  group('clusterSiblingsAdjacently', () {
    test('is a no-op on an empty list', () {
      expect(clusterSiblingsAdjacently(const [], const {}), isEmpty);
    });

    test('is a no-op when no ticket shares a parent with another', () {
      final tickets = [
        _ticket('a', parentId: 'p1'),
        _ticket('b', parentId: 'p2'),
        _ticket('c'),
      ];

      expect(
        clusterSiblingsAdjacently(
          tickets,
          _flatAncestorMap(tickets),
        ).map((t) => t.id),
        ['a', 'b', 'c'],
      );
    });

    test('pulls a non-adjacent sibling up next to its earliest member', () {
      final tickets = [
        _ticket('a', parentId: 'p1'),
        _ticket('b', parentId: 'p2'),
        _ticket('c', parentId: 'p1'),
      ];

      expect(
        clusterSiblingsAdjacently(
          tickets,
          _flatAncestorMap(tickets),
        ).map((t) => t.id),
        ['a', 'c', 'b'],
      );
    });

    test('handles multiple distinct sibling groups', () {
      final tickets = [
        _ticket('a', parentId: 'p1'),
        _ticket('x', parentId: 'p2'),
        _ticket('b', parentId: 'p1'),
        _ticket('y', parentId: 'p2'),
        _ticket('lone'),
      ];

      expect(
        clusterSiblingsAdjacently(
          tickets,
          _flatAncestorMap(tickets),
        ).map((t) => t.id),
        ['a', 'b', 'x', 'y', 'lone'],
      );
    });

    test(
      'is stable: members within a group keep their original relative '
      'order',
      () {
        final tickets = [
          _ticket('a', parentId: 'p1'),
          _ticket('lone'),
          _ticket('c', parentId: 'p1'),
          _ticket('b', parentId: 'p1'),
        ];

        expect(
          clusterSiblingsAdjacently(
            tickets,
            _flatAncestorMap(tickets),
          ).map((t) => t.id),
          ['a', 'c', 'b', 'lone'],
        );
      },
    );

    test('never groups tickets with a null parentId together', () {
      final tickets = [_ticket('a'), _ticket('b'), _ticket('c')];

      expect(
        clusterSiblingsAdjacently(
          tickets,
          _flatAncestorMap(tickets),
        ).map((t) => t.id),
        ['a', 'b', 'c'],
      );
    });
  });

  group('clusterSiblingsAdjacently — shared topmost ancestor', () {
    // Added for
    // aion-arch/changes/dependency-caching-and-ancestor-sibling-conflict:
    // `topmostAncestorId` (as `TicketsCubit.topmostAncestorIds` would
    // build it) replaces direct `parentId` equality, so two Tasks under
    // different Stories of the same Epic cluster together too.
    test(
      'groups two Tasks under different Stories of the same Epic',
      () {
        // story-1 and story-2 both roll up to epic-1.
        final a = _ticket('a', parentId: 'story-1');
        final b = _ticket('b', parentId: 'story-2');
        final lone = _ticket('lone', parentId: 'story-3');
        final tickets = [a, lone, b];
        final topmostAncestorId = {
          'a': 'epic-1',
          'b': 'epic-1',
          'lone': 'epic-9',
        };

        expect(
          clusterSiblingsAdjacently(
            tickets,
            topmostAncestorId,
          ).map((t) => t.id),
          ['a', 'b', 'lone'],
        );
      },
    );

    test('direct same-parent siblings still cluster (regression guard)', () {
      final a = _ticket('a', parentId: 'story-1');
      final b = _ticket('b', parentId: 'story-1');
      final lone = _ticket('lone', parentId: 'story-2');
      final tickets = [a, lone, b];
      final topmostAncestorId = {
        'a': 'epic-1',
        'b': 'epic-1',
        'lone': 'epic-2',
      };

      expect(
        clusterSiblingsAdjacently(tickets, topmostAncestorId).map(
          (t) => t.id,
        ),
        ['a', 'b', 'lone'],
      );
    });

    test('a ticket absent from the map is never grouped with anything', () {
      final a = _ticket('a', parentId: 'story-1');
      final b = _ticket('b', parentId: 'story-1');
      final tickets = [a, b];

      // Neither id present — mirrors a Board column reading a stale/empty
      // topmostAncestorId (e.g. a non-Hybrid session, where the map is
      // always `{}`).
      expect(
        clusterSiblingsAdjacently(tickets, const {}).map((t) => t.id),
        ['a', 'b'],
      );
    });

    test(
      'a ticket mapped to its own id is never grouped with anything — '
      'preserves the null-parentId convention',
      () {
        final a = _ticket('a');
        final b = _ticket('b');
        final tickets = [a, b];
        final topmostAncestorId = {'a': 'a', 'b': 'b'};

        expect(
          clusterSiblingsAdjacently(
            tickets,
            topmostAncestorId,
          ).map((t) => t.id),
          ['a', 'b'],
        );
      },
    );
  });
}
