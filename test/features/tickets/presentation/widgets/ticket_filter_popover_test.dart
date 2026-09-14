// test/features/tickets/presentation/widgets/ticket_filter_popover_test.dart — TicketFilterPopover.typeOptions coverage tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/presentation/widgets/ticket_filter_popover.dart';
import 'package:aion/features/tickets/tickets.dart';

void main() {
  group('TicketFilterPopover.typeOptions (AIO-2887)', () {
    test(
      'includes release and spec — real board/list tickets that were '
      'simply missing, not deliberately excluded',
      () {
        expect(TicketFilterPopover.typeOptions, contains(TicketType.release));
        expect(TicketFilterPopover.typeOptions, contains(TicketType.spec));
      },
    );

    test(
      'still excludes idea/knownGap/openQuestion — AIO-934 explicitly '
      'scoped these out of the Board/list entirely, not just this filter',
      () {
        expect(
          TicketFilterPopover.typeOptions,
          isNot(contains(TicketType.idea)),
        );
        expect(
          TicketFilterPopover.typeOptions,
          isNot(contains(TicketType.knownGap)),
        );
        expect(
          TicketFilterPopover.typeOptions,
          isNot(contains(TicketType.openQuestion)),
        );
      },
    );

    test(
      'still excludes page/resource — moved to the Documentation section',
      () {
        expect(
          TicketFilterPopover.typeOptions,
          isNot(contains(TicketType.page)),
        );
        expect(
          TicketFilterPopover.typeOptions,
          isNot(contains(TicketType.resource)),
        );
      },
    );

    test('covers every TicketType value exactly once, one way or the other', () {
      const excludedDeliberately = {
        TicketType.page,
        TicketType.resource,
        TicketType.idea,
        TicketType.knownGap,
        TicketType.openQuestion,
      };
      for (final type in TicketType.values) {
        final inOptions = TicketFilterPopover.typeOptions.contains(type);
        final excluded = excludedDeliberately.contains(type);
        expect(
          inOptions ^ excluded,
          isTrue,
          reason:
              '$type should be in exactly one of typeOptions or '
              'excludedDeliberately — a new TicketType value needs an '
              'explicit decision here, not a silent default.',
        );
      }
    });
  });
}
