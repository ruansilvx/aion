// test/features/tickets/domain/utils/ticket_sort_comparator_test.dart —
// ticketSortComparator ordinal/direction/relevance-fallback tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_priority.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/utils/ticket_sort_comparator.dart';

void main() {
  // Fixture tickets spanning every field this comparator sorts by, each
  // with a distinct value so sorted order is unambiguous.
  final low = Ticket(
    id: 'low',
    ticketId: 'AIO-1',
    type: TicketType.epic,
    title: 'Low',
    status: 'backlog',
    priority: TicketPriority.low,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 3),
  );
  final medium = Ticket(
    id: 'medium',
    ticketId: 'AIO-2',
    type: TicketType.story,
    title: 'Medium',
    status: 'inProgress',
    priority: TicketPriority.medium,
    createdAt: DateTime(2026, 1, 2),
    updatedAt: DateTime(2026, 1, 2),
  );
  final critical = Ticket(
    id: 'critical',
    ticketId: 'AIO-3',
    type: TicketType.task,
    title: 'Critical',
    status: 'done',
    priority: TicketPriority.critical,
    createdAt: DateTime(2026, 1, 3),
    updatedAt: DateTime(2026, 1, 1),
  );

  List<String> sortedIds(TicketListSort sort, {List<String> statusOrder = const []}) {
    final tickets = [medium, critical, low]
      ..sort(ticketSortComparator(sort, statusOrder: statusOrder));
    return tickets.map((t) => t.id).toList();
  }

  // The default baseline preset's own order — reproduces the exact
  // ordering the old `TicketStatus.values` declaration order gave. See
  // `ticket_sort_comparator.dart`'s dartdoc: status ordinal position now
  // comes from a caller-supplied `statusOrder`, not a fixed enum.
  const defaultStatusOrder = [
    'backlog',
    'todo',
    'inProgress',
    'inReview',
    'done',
    'cancelled',
  ];

  group('ticketSortComparator', () {
    test('priority ascending orders by declaration order (critical first)', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.priority,
            direction: TicketSortDirection.ascending,
          ),
        ),
        ['critical', 'medium', 'low'],
      );
    });

    test('priority descending reverses declaration order', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.priority,
            direction: TicketSortDirection.descending,
          ),
        ),
        ['low', 'medium', 'critical'],
      );
    });

    test('status ascending orders by the given statusOrder (backlog first)', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.status,
            direction: TicketSortDirection.ascending,
          ),
          statusOrder: defaultStatusOrder,
        ),
        ['low', 'medium', 'critical'],
      );
    });

    test('status descending reverses the given statusOrder', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.status,
            direction: TicketSortDirection.descending,
          ),
          statusOrder: defaultStatusOrder,
        ),
        ['critical', 'medium', 'low'],
      );
    });

    test(
      'status with no statusOrder supplied treats every ticket as tied '
      '(stable sort leaves relative order unchanged)',
      () {
        expect(
          sortedIds(
            const TicketListSort(
              field: TicketSortField.status,
              direction: TicketSortDirection.ascending,
            ),
          ),
          // No statusOrder -> every ticket's ordinal is 0 (not found in
          // an empty list) -> Dart's stable sort preserves the input
          // order ([medium, critical, low]) unchanged.
          ['medium', 'critical', 'low'],
        );
      },
    );

    test('type ascending orders by declaration order (epic first)', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.type,
            direction: TicketSortDirection.ascending,
          ),
        ),
        ['low', 'medium', 'critical'],
      );
    });

    test('type descending reverses declaration order', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.type,
            direction: TicketSortDirection.descending,
          ),
        ),
        ['critical', 'medium', 'low'],
      );
    });

    test('createdAt ascending orders oldest first', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.createdAt,
            direction: TicketSortDirection.ascending,
          ),
        ),
        ['low', 'medium', 'critical'],
      );
    });

    test('createdAt descending orders newest first', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.createdAt,
            direction: TicketSortDirection.descending,
          ),
        ),
        ['critical', 'medium', 'low'],
      );
    });

    test('updatedAt ascending orders least-recently-touched first', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.updatedAt,
            direction: TicketSortDirection.ascending,
          ),
        ),
        ['critical', 'medium', 'low'],
      );
    });

    test('updatedAt descending orders most-recently-touched first', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.updatedAt,
            direction: TicketSortDirection.descending,
          ),
        ),
        ['low', 'medium', 'critical'],
      );
    });

    test('relevance falls back to createdAt descending — no query to score '
        'against in a pure in-memory comparator', () {
      expect(
        sortedIds(
          const TicketListSort(
            field: TicketSortField.relevance,
            direction: TicketSortDirection.descending,
          ),
        ),
        ['critical', 'medium', 'low'],
      );
    });
  });
}
