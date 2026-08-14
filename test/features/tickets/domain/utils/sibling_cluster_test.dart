// test/features/tickets/domain/utils/sibling_cluster_test.dart — clusterSiblingsAdjacently tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_status.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/utils/sibling_cluster.dart';

Ticket _ticket(String id, {String? parentId}) => Ticket(
  id: id,
  ticketId: 'AIO-$id',
  type: TicketType.task,
  title: id,
  status: TicketStatus.inProgress,
  parentId: parentId,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  group('clusterSiblingsAdjacently', () {
    test('is a no-op on an empty list', () {
      expect(clusterSiblingsAdjacently(const []), isEmpty);
    });

    test('is a no-op when no ticket shares a parent with another', () {
      final tickets = [
        _ticket('a', parentId: 'p1'),
        _ticket('b', parentId: 'p2'),
        _ticket('c'),
      ];

      expect(
        clusterSiblingsAdjacently(tickets).map((t) => t.id),
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
        clusterSiblingsAdjacently(tickets).map((t) => t.id),
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
        clusterSiblingsAdjacently(tickets).map((t) => t.id),
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
          clusterSiblingsAdjacently(tickets).map((t) => t.id),
          ['a', 'c', 'b', 'lone'],
        );
      },
    );

    test('never groups tickets with a null parentId together', () {
      final tickets = [_ticket('a'), _ticket('b'), _ticket('c')];

      expect(
        clusterSiblingsAdjacently(tickets).map((t) => t.id),
        ['a', 'b', 'c'],
      );
    });
  });
}
