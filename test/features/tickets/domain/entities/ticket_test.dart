import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/tickets.dart';

void main() {
  final baseTicket = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Original title',
    description: 'Original description',
    status: TicketStatus.backlog,
    priority: TicketPriority.low,
    estimate: 60,
    timeSpent: 30,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  group('Ticket.copyWith', () {
    test('replaces title independently', () {
      final result = baseTicket.copyWith(title: 'New title');
      expect(result.title, 'New title');
      expect(result.description, baseTicket.description);
      expect(result.priority, baseTicket.priority);
      expect(result.type, baseTicket.type);
      expect(result.status, baseTicket.status);
    });

    test('replaces priority independently', () {
      final result = baseTicket.copyWith(priority: TicketPriority.critical);
      expect(result.priority, TicketPriority.critical);
      expect(result.title, baseTicket.title);
    });

    test('replaces type independently', () {
      final result = baseTicket.copyWith(type: TicketType.story);
      expect(result.type, TicketType.story);
      expect(result.title, baseTicket.title);
    });

    test('replaces status independently', () {
      final result = baseTicket.copyWith(status: TicketStatus.done);
      expect(result.status, TicketStatus.done);
      expect(result.title, baseTicket.title);
    });

    test('replaces updatedAt independently', () {
      final newDate = DateTime(2026, 6, 1);
      final result = baseTicket.copyWith(updatedAt: newDate);
      expect(result.updatedAt, newDate);
      expect(result.title, baseTicket.title);
    });

    test('replaces description via a setter', () {
      final result = baseTicket.copyWith(description: () => 'New description');
      expect(result.description, 'New description');
    });

    test('replaces estimate via a setter', () {
      final result = baseTicket.copyWith(estimate: () => 90);
      expect(result.estimate, 90);
    });

    test('replaces timeSpent via a setter', () {
      final result = baseTicket.copyWith(timeSpent: () => 45);
      expect(result.timeSpent, 45);
    });

    test('explicitly clears description to null via () => null', () {
      final result = baseTicket.copyWith(description: () => null);
      expect(result.description, isNull);
    });

    test('explicitly clears estimate to null via () => null', () {
      final result = baseTicket.copyWith(estimate: () => null);
      expect(result.estimate, isNull);
    });

    test('explicitly clears timeSpent to null via () => null', () {
      final result = baseTicket.copyWith(timeSpent: () => null);
      expect(result.timeSpent, isNull);
    });

    test('leaves all fields unchanged when nothing is passed', () {
      final result = baseTicket.copyWith();
      expect(result, baseTicket);
    });

    test('never mutates id, ticketId, parentId, embedding, or createdAt', () {
      final result = baseTicket.copyWith(
        title: 'Changed',
        description: () => 'Changed',
        priority: TicketPriority.high,
        type: TicketType.story,
        estimate: () => 999,
        timeSpent: () => 999,
      );
      expect(result.id, baseTicket.id);
      expect(result.ticketId, baseTicket.ticketId);
      expect(result.parentId, baseTicket.parentId);
      expect(result.embedding, baseTicket.embedding);
      expect(result.createdAt, baseTicket.createdAt);
    });

    test('replaces suggestedType via a setter', () {
      final result = baseTicket.copyWith(
        suggestedType: () => TicketType.epic,
      );
      expect(result.suggestedType, TicketType.epic);
    });

    test('explicitly clears suggestedType to null via () => null', () {
      final withSuggestion = baseTicket.copyWith(
        suggestedType: () => TicketType.bug,
      );
      final result = withSuggestion.copyWith(suggestedType: () => null);
      expect(result.suggestedType, isNull);
    });

    test('replaces inboxPurpose via a setter', () {
      final result = baseTicket.copyWith(
        inboxPurpose: () => InboxPurpose.brainDump,
      );
      expect(result.inboxPurpose, InboxPurpose.brainDump);
    });

    test('explicitly clears inboxPurpose to null via () => null', () {
      final withPurpose = baseTicket.copyWith(
        inboxPurpose: () => InboxPurpose.qa,
      );
      final result = withPurpose.copyWith(inboxPurpose: () => null);
      expect(result.inboxPurpose, isNull);
    });

    test('suggestedType and inboxPurpose default to null and are left '
        'unchanged when nothing is passed', () {
      final result = baseTicket.copyWith();
      expect(result.suggestedType, isNull);
      expect(result.inboxPurpose, isNull);
    });
  });

  group('Ticket equality (props)', () {
    test('two otherwise-identical tickets differing only by suggestedType '
        'are not equal', () {
      final a = baseTicket.copyWith(suggestedType: () => TicketType.epic);
      final b = baseTicket.copyWith(suggestedType: () => TicketType.bug);
      expect(a, isNot(equals(b)));
    });

    test('two otherwise-identical tickets differing only by inboxPurpose '
        'are not equal', () {
      final a = baseTicket.copyWith(inboxPurpose: () => InboxPurpose.qa);
      final b = baseTicket.copyWith(
        inboxPurpose: () => InboxPurpose.brainDump,
      );
      expect(a, isNot(equals(b)));
    });
  });
}
