import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/tickets.dart';

void main() {
  group('TicketTypeHierarchy.canParent', () {
    // Full 11x11 matrix (including same-type pairs), per
    // aion-arch/changes/sdd-ticket-foundation/design.md (MODIFIED from
    // documentation-section), aion-arch/changes/bug-ticket-type/design.md
    // (ADDED `bug`), aion-arch/changes/mid-task-chat-branching/design.md
    // (MODIFIED chat.canParent(chat)), and
    // aion-arch/changes/idea-gap-question-ticket-types/design.md (`signal`
    // split into `idea`/`knownGap`/`openQuestion`, each inheriting
    // `signal`'s exact prior row): epic(0) > story(1) > task/bug(2) in a
    // strict rank chain, and still parent `chat` unconditionally, but can no
    // longer parent `resource`/`page` — those relocated to the Documentation
    // section, where `page` alone can parent `page`/`resource`
    // (Notion-style nesting). `resource` remains a full leaf that can never
    // parent anything, including itself. `chat` is a leaf for every other
    // type but may now parent exactly one further `chat` — a mid-task/issue
    // branch (the depth cap beyond that one level is an instance-level
    // invariant enforced by `TicketsCubit._canBranch`, not by this
    // type-level rule). `idea`/`knownGap`/`openQuestion`/`release` are each
    // a third kind of special case: parentless like `epic` (see
    // `isAlwaysRoot`) and can parent `chat` only, never a work type or each
    // other. `bug` shares `task`'s literal rank, so neither can parent the
    // other — same-rank nesting is always rejected.
    const expected = <(TicketType, TicketType), bool>{
      (TicketType.epic, TicketType.epic): false,
      (TicketType.epic, TicketType.story): true,
      (TicketType.epic, TicketType.task): true,
      (TicketType.epic, TicketType.resource): false,
      (TicketType.epic, TicketType.page): false,
      (TicketType.epic, TicketType.chat): true,
      (TicketType.epic, TicketType.idea): false,
      (TicketType.epic, TicketType.knownGap): false,
      (TicketType.epic, TicketType.openQuestion): false,
      (TicketType.epic, TicketType.release): false,
      (TicketType.epic, TicketType.bug): true,

      (TicketType.story, TicketType.epic): false,
      (TicketType.story, TicketType.story): false,
      (TicketType.story, TicketType.task): true,
      (TicketType.story, TicketType.resource): false,
      (TicketType.story, TicketType.page): false,
      (TicketType.story, TicketType.chat): true,
      (TicketType.story, TicketType.idea): false,
      (TicketType.story, TicketType.knownGap): false,
      (TicketType.story, TicketType.openQuestion): false,
      (TicketType.story, TicketType.release): false,
      (TicketType.story, TicketType.bug): true,

      (TicketType.task, TicketType.epic): false,
      (TicketType.task, TicketType.story): false,
      (TicketType.task, TicketType.task): false,
      (TicketType.task, TicketType.resource): false,
      (TicketType.task, TicketType.page): false,
      (TicketType.task, TicketType.chat): true,
      (TicketType.task, TicketType.idea): false,
      (TicketType.task, TicketType.knownGap): false,
      (TicketType.task, TicketType.openQuestion): false,
      (TicketType.task, TicketType.release): false,
      (TicketType.task, TicketType.bug): false,

      (TicketType.resource, TicketType.epic): false,
      (TicketType.resource, TicketType.story): false,
      (TicketType.resource, TicketType.task): false,
      (TicketType.resource, TicketType.resource): false,
      (TicketType.resource, TicketType.page): false,
      (TicketType.resource, TicketType.chat): false,
      (TicketType.resource, TicketType.idea): false,
      (TicketType.resource, TicketType.knownGap): false,
      (TicketType.resource, TicketType.openQuestion): false,
      (TicketType.resource, TicketType.release): false,
      (TicketType.resource, TicketType.bug): false,

      (TicketType.page, TicketType.epic): false,
      (TicketType.page, TicketType.story): false,
      (TicketType.page, TicketType.task): false,
      (TicketType.page, TicketType.resource): true,
      (TicketType.page, TicketType.page): true,
      (TicketType.page, TicketType.chat): false,
      (TicketType.page, TicketType.idea): false,
      (TicketType.page, TicketType.knownGap): false,
      (TicketType.page, TicketType.openQuestion): false,
      (TicketType.page, TicketType.release): false,
      (TicketType.page, TicketType.bug): false,

      (TicketType.chat, TicketType.epic): false,
      (TicketType.chat, TicketType.story): false,
      (TicketType.chat, TicketType.task): false,
      (TicketType.chat, TicketType.resource): false,
      (TicketType.chat, TicketType.page): false,
      (TicketType.chat, TicketType.chat): true,
      (TicketType.chat, TicketType.idea): false,
      (TicketType.chat, TicketType.knownGap): false,
      (TicketType.chat, TicketType.openQuestion): false,
      (TicketType.chat, TicketType.release): false,
      (TicketType.chat, TicketType.bug): false,

      (TicketType.idea, TicketType.epic): false,
      (TicketType.idea, TicketType.story): false,
      (TicketType.idea, TicketType.task): false,
      (TicketType.idea, TicketType.resource): false,
      (TicketType.idea, TicketType.page): false,
      (TicketType.idea, TicketType.chat): true,
      (TicketType.idea, TicketType.idea): false,
      (TicketType.idea, TicketType.knownGap): false,
      (TicketType.idea, TicketType.openQuestion): false,
      (TicketType.idea, TicketType.release): false,
      (TicketType.idea, TicketType.bug): false,

      (TicketType.knownGap, TicketType.epic): false,
      (TicketType.knownGap, TicketType.story): false,
      (TicketType.knownGap, TicketType.task): false,
      (TicketType.knownGap, TicketType.resource): false,
      (TicketType.knownGap, TicketType.page): false,
      (TicketType.knownGap, TicketType.chat): true,
      (TicketType.knownGap, TicketType.idea): false,
      (TicketType.knownGap, TicketType.knownGap): false,
      (TicketType.knownGap, TicketType.openQuestion): false,
      (TicketType.knownGap, TicketType.release): false,
      (TicketType.knownGap, TicketType.bug): false,

      (TicketType.openQuestion, TicketType.epic): false,
      (TicketType.openQuestion, TicketType.story): false,
      (TicketType.openQuestion, TicketType.task): false,
      (TicketType.openQuestion, TicketType.resource): false,
      (TicketType.openQuestion, TicketType.page): false,
      (TicketType.openQuestion, TicketType.chat): true,
      (TicketType.openQuestion, TicketType.idea): false,
      (TicketType.openQuestion, TicketType.knownGap): false,
      (TicketType.openQuestion, TicketType.openQuestion): false,
      (TicketType.openQuestion, TicketType.release): false,
      (TicketType.openQuestion, TicketType.bug): false,

      (TicketType.release, TicketType.epic): false,
      (TicketType.release, TicketType.story): false,
      (TicketType.release, TicketType.task): false,
      (TicketType.release, TicketType.resource): false,
      (TicketType.release, TicketType.page): false,
      (TicketType.release, TicketType.chat): true,
      (TicketType.release, TicketType.idea): false,
      (TicketType.release, TicketType.knownGap): false,
      (TicketType.release, TicketType.openQuestion): false,
      (TicketType.release, TicketType.release): false,
      (TicketType.release, TicketType.bug): false,

      (TicketType.bug, TicketType.epic): false,
      (TicketType.bug, TicketType.story): false,
      (TicketType.bug, TicketType.task): false,
      (TicketType.bug, TicketType.resource): false,
      (TicketType.bug, TicketType.page): false,
      (TicketType.bug, TicketType.chat): true,
      (TicketType.bug, TicketType.idea): false,
      (TicketType.bug, TicketType.knownGap): false,
      (TicketType.bug, TicketType.openQuestion): false,
      (TicketType.bug, TicketType.release): false,
      (TicketType.bug, TicketType.bug): false,
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

  group('TicketTypeHierarchy.isAlwaysRoot', () {
    // epic/idea/knownGap/openQuestion/release are always a subtree root;
    // every other type is not. Per
    // aion-arch/changes/idea-gap-question-ticket-types/design.md §1.1 —
    // `idea`/`knownGap`/`openQuestion` all inherit `signal`'s exact prior
    // `isAlwaysRoot` treatment.
    const alwaysRoot = {
      TicketType.epic,
      TicketType.idea,
      TicketType.knownGap,
      TicketType.openQuestion,
      TicketType.release,
    };

    for (final type in TicketType.values) {
      final expectedValue = alwaysRoot.contains(type);
      test(
        '$type.isAlwaysRoot is $expectedValue',
        () => expect(type.isAlwaysRoot, expectedValue),
      );
    }
  });

  group('TicketTypeHierarchy.isExecutable', () {
    test('task and bug are executable', () {
      expect(TicketType.task.isExecutable, isTrue);
      expect(TicketType.bug.isExecutable, isTrue);
    });

    test('every other type is not executable', () {
      for (final type in TicketType.values) {
        if (type == TicketType.task || type == TicketType.bug) continue;
        expect(type.isExecutable, isFalse, reason: '$type');
      }
    });

    test('executableTypes contains exactly task and bug', () {
      expect(TicketTypeHierarchy.executableTypes, [
        TicketType.task,
        TicketType.bug,
      ]);
    });
  });
}
