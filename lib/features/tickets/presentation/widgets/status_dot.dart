// presentation/widgets/status_dot.dart — Shared workflow-status dot color rule + widget (presentation layer).

import 'package:flutter/widgets.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/workflow_status.dart';
import 'package:aion/features/tickets/domain/enums/workflow_status_role.dart';

/// The role-keyed status-dot color rule — see
/// `aion-arch/changes/v1-release-readiness/design.md` §2.1. Replaces the
/// three independent name-matching implementations this change removes
/// (`ticket_selection_bar.dart`'s former `_statusDotColor`, and
/// `ticket_columns_popover.dart`'s/`ticket_filter_popover.dart`'s former
/// private `_StatusAccentDot`), and backs the genuinely new dot added to
/// `BoardColumn`'s header and `MoveToStatusMenu`'s rows
/// (`tickets_board_view.dart`), which had none before this change.
///
/// [terminal] is `true` when [status]'s `sortOrder` places it after
/// whichever status in the same scope holds [WorkflowStatusRole.done] —
/// see [isStatusTerminal].
Color statusDotColor(
  AionColors c,
  WorkflowStatus status, {
  required bool terminal,
}) {
  return switch (status.role) {
    WorkflowStatusRole.executionTrigger => c.primary,
    WorkflowStatusRole.reviewReady => c.warning,
    WorkflowStatusRole.done => c.success,
    null => terminal ? c.textMuted : c.textSecondary,
  };
}

/// Whether [status]'s `sortOrder` places it after whichever status in
/// [scope] holds [WorkflowStatusRole.done] — `false` (including when no
/// status in [scope] holds that role). [scope] must be the same status
/// list [status] was resolved from (e.g.
/// `WorkflowConfigLoaded.sharedBaseStatuses`/`effectiveStatusesForType`),
/// so `sortOrder` comparisons are meaningful.
bool isStatusTerminal(WorkflowStatus status, List<WorkflowStatus> scope) {
  WorkflowStatus? doneStatus;
  for (final s in scope) {
    if (s.role == WorkflowStatusRole.done) {
      doneStatus = s;
      break;
    }
  }
  if (doneStatus == null) return false;
  return status.sortOrder > doneStatus.sortOrder;
}

/// Resolves the dot color for [statusName] within [scope] — the "unknown
/// status" fallback ([AionColors.textMuted], design.md §2.3) when
/// [statusName] doesn't match any entry in [scope], e.g. a ticket
/// referencing a status that has since been renamed or removed.
Color statusDotColorForName(
  AionColors c,
  List<WorkflowStatus> scope,
  String statusName,
) {
  for (final s in scope) {
    if (s.name == statusName) {
      return statusDotColor(c, s, terminal: isStatusTerminal(s, scope));
    }
  }
  return c.textMuted;
}

/// A small filled circle rendering [color] — the shared geometry every
/// status-dot call site uses, sized by [size] square (`7` on
/// `BoardColumn`'s header per design.md §2.2, `8` everywhere else).
/// Decorative — wrapped in [ExcludeSemantics], since the status name
/// itself carries the accessible label at every call site.
class StatusDot extends StatelessWidget {
  /// Creates a [StatusDot] filled with [color], [size] square (default
  /// `8`).
  const StatusDot({super.key, required this.color, this.size = 8});

  /// The dot's fill color — see [statusDotColor]/[statusDotColorForName].
  final Color color;

  /// The dot's width and height.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: SizedBox(width: size, height: size),
      ),
    );
  }
}
