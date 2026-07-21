import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/tickets.dart';

void main() {
  group('TicketTypeHierarchy.canParent', () {
    // Full 8x8 matrix (including same-type pairs), per
    // aion-arch/changes/sdd-ticket-foundation/design.md (MODIFIED from
    // documentation-section): epic(0) > story(1) > task(2) in a strict
    // rank chain, and still parent `chat` unconditionally, but can no
    // longer parent `resource`/`page` — those relocated to the
    // Documentation section, where `page` alone can parent `page`/
    // `resource` (Notion-style nesting). `resource`/`chat` remain full
    // leaves that can never parent anything. `signal`/`release` are each
    // a third kind of special case: parentless like `epic` (see
    // `isAlwaysRoot`) and can parent `chat` only, never a work type or
    // each other.
    const expected = <(TicketType, TicketType), bool>{
      (TicketType.epic, TicketType.epic): false,
      (TicketType.epic, TicketType.story): true,
      (TicketType.epic, TicketType.task): true,
      (TicketType.epic, TicketType.resource): false,
      (TicketType.epic, TicketType.page): false,
      (TicketType.epic, TicketType.chat): true,
      (TicketType.epic, TicketType.signal): false,
      (TicketType.epic, TicketType.release): false,

      (TicketType.story, TicketType.epic): false,
      (TicketType.story, TicketType.story): false,
      (TicketType.story, TicketType.task): true,
      (TicketType.story, TicketType.resource): false,
      (TicketType.story, TicketType.page): false,
      (TicketType.story, TicketType.chat): true,
      (TicketType.story, TicketType.signal): false,
      (TicketType.story, TicketType.release): false,

      (TicketType.task, TicketType.epic): false,
      (TicketType.task, TicketType.story): false,
      (TicketType.task, TicketType.task): false,
      (TicketType.task, TicketType.resource): false,
      (TicketType.task, TicketType.page): false,
      (TicketType.task, TicketType.chat): true,
      (TicketType.task, TicketType.signal): false,
      (TicketType.task, TicketType.release): false,

      (TicketType.resource, TicketType.epic): false,
      (TicketType.resource, TicketType.story): false,
      (TicketType.resource, TicketType.task): false,
      (TicketType.resource, TicketType.resource): false,
      (TicketType.resource, TicketType.page): false,
      (TicketType.resource, TicketType.chat): false,
      (TicketType.resource, TicketType.signal): false,
      (TicketType.resource, TicketType.release): false,

      (TicketType.page, TicketType.epic): false,
      (TicketType.page, TicketType.story): false,
      (TicketType.page, TicketType.task): false,
      (TicketType.page, TicketType.resource): true,
      (TicketType.page, TicketType.page): true,
      (TicketType.page, TicketType.chat): false,
      (TicketType.page, TicketType.signal): false,
      (TicketType.page, TicketType.release): false,

      (TicketType.chat, TicketType.epic): false,
      (TicketType.chat, TicketType.story): false,
      (TicketType.chat, TicketType.task): false,
      (TicketType.chat, TicketType.resource): false,
      (TicketType.chat, TicketType.page): false,
      (TicketType.chat, TicketType.chat): false,
      (TicketType.chat, TicketType.signal): false,
      (TicketType.chat, TicketType.release): false,

      (TicketType.signal, TicketType.epic): false,
      (TicketType.signal, TicketType.story): false,
      (TicketType.signal, TicketType.task): false,
      (TicketType.signal, TicketType.resource): false,
      (TicketType.signal, TicketType.page): false,
      (TicketType.signal, TicketType.chat): true,
      (TicketType.signal, TicketType.signal): false,
      (TicketType.signal, TicketType.release): false,

      (TicketType.release, TicketType.epic): false,
      (TicketType.release, TicketType.story): false,
      (TicketType.release, TicketType.task): false,
      (TicketType.release, TicketType.resource): false,
      (TicketType.release, TicketType.page): false,
      (TicketType.release, TicketType.chat): true,
      (TicketType.release, TicketType.signal): false,
      (TicketType.release, TicketType.release): false,
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
