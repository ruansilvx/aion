import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/tickets.dart';

void main() {
  group('TicketTypeHierarchy.canParent', () {
    // Full 6x6 matrix (including same-type pairs), per
    // aion-arch/changes/documentation-section/design.md (MODIFIED from
    // define-type-compatibility-matrix): epic(0) > story(1) > task(2) in
    // a strict rank chain, and still parent `chat` unconditionally, but
    // can no longer parent `resource`/`page` — those relocated to the
    // Documentation section, where `page` alone can parent `page`/
    // `resource` (Notion-style nesting). `resource`/`chat` remain full
    // leaves that can never parent anything.
    const expected = <(TicketType, TicketType), bool>{
      (TicketType.epic, TicketType.epic): false,
      (TicketType.epic, TicketType.story): true,
      (TicketType.epic, TicketType.task): true,
      (TicketType.epic, TicketType.resource): false,
      (TicketType.epic, TicketType.page): false,
      (TicketType.epic, TicketType.chat): true,

      (TicketType.story, TicketType.epic): false,
      (TicketType.story, TicketType.story): false,
      (TicketType.story, TicketType.task): true,
      (TicketType.story, TicketType.resource): false,
      (TicketType.story, TicketType.page): false,
      (TicketType.story, TicketType.chat): true,

      (TicketType.task, TicketType.epic): false,
      (TicketType.task, TicketType.story): false,
      (TicketType.task, TicketType.task): false,
      (TicketType.task, TicketType.resource): false,
      (TicketType.task, TicketType.page): false,
      (TicketType.task, TicketType.chat): true,

      (TicketType.resource, TicketType.epic): false,
      (TicketType.resource, TicketType.story): false,
      (TicketType.resource, TicketType.task): false,
      (TicketType.resource, TicketType.resource): false,
      (TicketType.resource, TicketType.page): false,
      (TicketType.resource, TicketType.chat): false,

      (TicketType.page, TicketType.epic): false,
      (TicketType.page, TicketType.story): false,
      (TicketType.page, TicketType.task): false,
      (TicketType.page, TicketType.resource): true,
      (TicketType.page, TicketType.page): true,
      (TicketType.page, TicketType.chat): false,

      (TicketType.chat, TicketType.epic): false,
      (TicketType.chat, TicketType.story): false,
      (TicketType.chat, TicketType.task): false,
      (TicketType.chat, TicketType.resource): false,
      (TicketType.chat, TicketType.page): false,
      (TicketType.chat, TicketType.chat): false,
    };

    for (final entry in expected.entries) {
      final (parent, child) = entry.key;
      final allowed = entry.value;
      test(
        '$parent ${allowed ? 'can' : 'cannot'} parent $child',
        () => expect(parent.canParent(child), allowed),
      );
    }

    test('covers every TicketType pair exactly once', () {
      expect(
        expected.length,
        TicketType.values.length * TicketType.values.length,
      );
    });
  });
}
