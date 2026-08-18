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

    // `copyWith` has no `estimateRollup`/`timeSpentRollup` parameters at
    // all — a compile-time guarantee (calling
    // `baseTicket.copyWith(estimateRollup: 1)` is a build error, not a
    // runtime one), so there is no "explicitly clears" or "replaces via a
    // setter" case to test here, unlike every other nullable field above.
    // What *is* runtime-testable is that both fields pass through
    // unaffected by every other `copyWith` call — see below.
    test(
      'estimateRollup/timeSpentRollup pass through unchanged on every '
      'copyWith call, since neither is a settable parameter',
      () {
        final withRollup = Ticket(
          id: baseTicket.id,
          ticketId: baseTicket.ticketId,
          type: baseTicket.type,
          title: baseTicket.title,
          description: baseTicket.description,
          status: baseTicket.status,
          priority: baseTicket.priority,
          estimate: baseTicket.estimate,
          timeSpent: baseTicket.timeSpent,
          createdAt: baseTicket.createdAt,
          updatedAt: baseTicket.updatedAt,
          estimateRollup: 45,
          timeSpentRollup: 20,
        );

        final result = withRollup.copyWith(
          title: 'Changed',
          priority: TicketPriority.high,
          estimate: () => 999,
        );

        expect(result.estimateRollup, 45);
        expect(result.timeSpentRollup, 20);
      },
    );

    // Same shape as the estimateRollup/timeSpentRollup test above —
    // complexitySource/estimateSource have no copyWith parameter either,
    // so the only runtime-testable property is that they pass through
    // unaffected by every other copyWith call.
    test(
      'complexitySource/estimateSource pass through unchanged on every '
      'copyWith call, since neither is a settable parameter',
      () {
        final withSources = Ticket(
          id: baseTicket.id,
          ticketId: baseTicket.ticketId,
          type: baseTicket.type,
          title: baseTicket.title,
          description: baseTicket.description,
          status: baseTicket.status,
          priority: baseTicket.priority,
          estimate: baseTicket.estimate,
          timeSpent: baseTicket.timeSpent,
          createdAt: baseTicket.createdAt,
          updatedAt: baseTicket.updatedAt,
          complexity: TicketComplexity.medium,
          complexitySource: TicketEstimationSource.aiSuggested,
          estimateSource: TicketEstimationSource.aiSuggestedLowConfidence,
        );

        final result = withSources.copyWith(
          title: 'Changed',
          priority: TicketPriority.high,
          estimate: () => 999,
        );

        expect(result.complexitySource, TicketEstimationSource.aiSuggested);
        expect(
          result.estimateSource,
          TicketEstimationSource.aiSuggestedLowConfidence,
        );
      },
    );

    // Same shape as the estimateRollup/timeSpentRollup and
    // complexitySource/estimateSource tests above —
    // predictedExecutionTokensLow/High have no copyWith parameter either
    // (see design.md's citation of `ticket-copywith-drops-deletedat` as
    // the failure mode this exclusion avoids), so the only
    // runtime-testable property is that they pass through unaffected by
    // every other copyWith call.
    test(
      'predictedExecutionTokensLow/High pass through unchanged on every '
      'copyWith call, since neither is a settable parameter',
      () {
        final withPrediction = Ticket(
          id: baseTicket.id,
          ticketId: baseTicket.ticketId,
          type: baseTicket.type,
          title: baseTicket.title,
          description: baseTicket.description,
          status: baseTicket.status,
          priority: baseTicket.priority,
          estimate: baseTicket.estimate,
          timeSpent: baseTicket.timeSpent,
          createdAt: baseTicket.createdAt,
          updatedAt: baseTicket.updatedAt,
          predictedExecutionTokensLow: 12000,
          predictedExecutionTokensHigh: 34000,
        );

        final result = withPrediction.copyWith(
          title: 'Changed',
          priority: TicketPriority.high,
          estimate: () => 999,
        );

        expect(result.predictedExecutionTokensLow, 12000);
        expect(result.predictedExecutionTokensHigh, 34000);
      },
    );

    // Same shape as the three tests above — deletedAt has no copyWith
    // parameter either, so the only runtime-testable property is that it
    // passes through unaffected by every other copyWith call. Regression
    // test for `aion-arch/ideas/ticket-copywith-drops-deletedat.md`: this
    // used to silently reset to null on every copyWith call instead of
    // being preserved.
    test(
      'deletedAt passes through unchanged on every copyWith call, since '
      "it isn't a settable parameter",
      () {
        final trashedAt = DateTime(2026, 3, 1);
        final trashed = Ticket(
          id: baseTicket.id,
          ticketId: baseTicket.ticketId,
          type: baseTicket.type,
          title: baseTicket.title,
          description: baseTicket.description,
          status: baseTicket.status,
          priority: baseTicket.priority,
          estimate: baseTicket.estimate,
          timeSpent: baseTicket.timeSpent,
          createdAt: baseTicket.createdAt,
          updatedAt: baseTicket.updatedAt,
          deletedAt: trashedAt,
        );

        final result = trashed.copyWith(
          title: 'Changed',
          priority: TicketPriority.high,
          estimate: () => 999,
        );

        expect(result.deletedAt, trashedAt);
      },
    );
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

    test(
      'two otherwise-identical tickets differing only by estimateRollup/'
      'timeSpentRollup are not equal',
      () {
        final a = Ticket(
          id: baseTicket.id,
          ticketId: baseTicket.ticketId,
          type: baseTicket.type,
          title: baseTicket.title,
          status: baseTicket.status,
          createdAt: baseTicket.createdAt,
          updatedAt: baseTicket.updatedAt,
          estimateRollup: 45,
        );
        final b = Ticket(
          id: baseTicket.id,
          ticketId: baseTicket.ticketId,
          type: baseTicket.type,
          title: baseTicket.title,
          status: baseTicket.status,
          createdAt: baseTicket.createdAt,
          updatedAt: baseTicket.updatedAt,
          estimateRollup: 90,
        );
        expect(a, isNot(equals(b)));
      },
    );
  });
}
