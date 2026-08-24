// test/features/tickets/presentation/widgets/status_dot_test.dart — status_dot.dart unit tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';
import 'package:aion/features/tickets/presentation/widgets/status_dot.dart';

// Pure-logic tests for statusDotColor/isStatusTerminal/statusDotColorForName
// — design.md §2.1's decision table, the "one new design decision" this
// change (aion-arch/changes/v1-release-readiness) is built around. Added
// as a post-/verify fix (T19): the first /apply pass wired these
// functions into six widgets but left the functions themselves with no
// direct coverage. `arctic` is used as the fixed [AionColors] instance
// throughout — the rule's logic doesn't depend on which theme is active,
// only on which token field is returned.
void main() {
  const backlog = WorkflowStatus(
    id: 'id-backlog',
    name: 'backlog',
    displayName: 'Backlog',
    sortOrder: 0,
  );
  const inProgress = WorkflowStatus(
    id: 'id-in-progress',
    name: 'inProgress',
    displayName: 'In Progress',
    sortOrder: 1,
    role: WorkflowStatusRole.executionTrigger,
  );
  const inReview = WorkflowStatus(
    id: 'id-in-review',
    name: 'inReview',
    displayName: 'In Review',
    sortOrder: 2,
    role: WorkflowStatusRole.reviewReady,
  );
  const done = WorkflowStatus(
    id: 'id-done',
    name: 'done',
    displayName: 'Done',
    sortOrder: 3,
    role: WorkflowStatusRole.done,
  );
  const cancelled = WorkflowStatus(
    id: 'id-cancelled',
    name: 'cancelled',
    displayName: 'Cancelled',
    sortOrder: 4,
  );
  final scope = [backlog, inProgress, inReview, done, cancelled];

  group('statusDotColor', () {
    test('executionTrigger role resolves to c.primary', () {
      expect(
        statusDotColor(arctic, inProgress, terminal: false),
        arctic.primary,
      );
    });

    test('reviewReady role resolves to c.warning', () {
      expect(statusDotColor(arctic, inReview, terminal: false), arctic.warning);
    });

    test('done role resolves to c.success', () {
      expect(statusDotColor(arctic, done, terminal: false), arctic.success);
    });

    test('role-less, not terminal resolves to c.textSecondary', () {
      expect(
        statusDotColor(arctic, backlog, terminal: false),
        arctic.textSecondary,
      );
    });

    test('role-less, terminal resolves to c.textMuted', () {
      expect(
        statusDotColor(arctic, cancelled, terminal: true),
        arctic.textMuted,
      );
    });

    test('a role always wins over terminal — terminal is ignored when a role is set', () {
      // done itself is never terminal by construction (§2.1: terminal is
      // defined relative to the done-role status), but this asserts the
      // role branch is checked first regardless of what terminal is
      // passed, matching the switch's declaration order.
      expect(statusDotColor(arctic, done, terminal: true), arctic.success);
    });
  });

  group('isStatusTerminal', () {
    test('a status ordered after the done-role status is terminal', () {
      expect(isStatusTerminal(cancelled, scope), isTrue);
    });

    test('a status ordered before the done-role status is not terminal', () {
      expect(isStatusTerminal(backlog, scope), isFalse);
      expect(isStatusTerminal(inProgress, scope), isFalse);
    });

    test('the done-role status itself is not terminal (not strictly after itself)', () {
      expect(isStatusTerminal(done, scope), isFalse);
    });

    test('defaults to false when no status in scope holds the done role', () {
      final noDoneScope = [backlog, inProgress, inReview, cancelled];
      expect(isStatusTerminal(cancelled, noDoneScope), isFalse);
    });
  });

  group('statusDotColorForName', () {
    test('a known name resolves through statusDotColor', () {
      expect(
        statusDotColorForName(arctic, scope, 'inReview'),
        arctic.warning,
      );
      expect(
        statusDotColorForName(arctic, scope, 'cancelled'),
        arctic.textMuted,
      );
    });

    test('an unknown name (renamed/removed status) falls back to c.textMuted', () {
      expect(
        statusDotColorForName(arctic, scope, 'noLongerExists'),
        arctic.textMuted,
      );
    });

    test('an empty scope always falls back to c.textMuted', () {
      expect(statusDotColorForName(arctic, const [], 'backlog'), arctic.textMuted);
    });
  });
}
