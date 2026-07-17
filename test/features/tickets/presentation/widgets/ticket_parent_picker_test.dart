import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/presentation/widgets/ticket_parent_picker.dart';
import 'package:aion/features/tickets/tickets.dart';

void main() {
  final grandparent = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.epic,
    title: 'Grandparent',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final parent = Ticket(
    id: '2',
    ticketId: 'AIO-2',
    type: TicketType.story,
    title: 'Parent',
    status: TicketStatus.backlog,
    parentId: grandparent.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final child = Ticket(
    id: '3',
    ticketId: 'AIO-3',
    type: TicketType.task,
    title: 'Child',
    status: TicketStatus.backlog,
    parentId: parent.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final root = Ticket(
    id: '4',
    ticketId: 'AIO-4',
    type: TicketType.task,
    title: 'Root',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  group('ancestorBreadcrumb', () {
    test('returns null for a ticket with no parent', () {
      expect(ancestorBreadcrumb(root, {}), isNull);
    });

    test('returns the single ancestor for a one-level parent', () {
      final byId = {grandparent.id: grandparent, parent.id: parent};
      expect(ancestorBreadcrumb(parent, byId), 'Grandparent');
    });

    test('joins a multi-level chain root-most first', () {
      final byId = {
        grandparent.id: grandparent,
        parent.id: parent,
        child.id: child,
      };
      expect(ancestorBreadcrumb(child, byId), 'Grandparent  /  Parent');
    });

    test('breaks early when an ancestor is missing from the map', () {
      // parent is present but grandparent (its own parent) is not.
      final byId = {parent.id: parent, child.id: child};
      expect(ancestorBreadcrumb(child, byId), 'Parent');
    });

    test('stops after maxDepth hops', () {
      final byId = {
        grandparent.id: grandparent,
        parent.id: parent,
        child.id: child,
      };
      expect(ancestorBreadcrumb(child, byId, maxDepth: 1), 'Parent');
    });
  });
}
