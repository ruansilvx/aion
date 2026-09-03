// domain/entities/transition_field_spec.dart — TransitionFieldSpec catalog (domain layer).

import 'package:meta/meta.dart';

import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';

/// One plain-boolean field a `TransitionNode` can check — the vocabulary
/// `TransitionNodeForm`'s field picker offers. Every field this proposal
/// ships is a plain fact (no parameter, no operator, no units), unlike
/// `core/automation/decision_field_catalog.dart`'s `DecisionFieldSpec`,
/// which also carries a [DecisionFieldType] selecting an operator/value
/// shape — nothing here needs that distinction. Added for
/// `AIO-1936`.
@immutable
class TransitionFieldSpec {
  /// Creates a [TransitionFieldSpec].
  const TransitionFieldSpec({
    required this.id,
    required this.displayName,
    required this.stages,
  });

  /// Stable identifier, stored as `TransitionNode.fieldId`.
  final String id;

  /// User-facing label shown in the field picker and wherever a node's
  /// title is rendered.
  final String displayName;

  /// Which [SddStage] values this field is valid for —
  /// [transitionFieldsFor] filters the full catalog down to this set.
  final List<SddStage> stages;
}

/// Wraps `TicketsCubit._mostRecentChatHasTerminalReply` — whether the
/// current stage's most recently created `chat` child already has an AI
/// reply. Valid for [SddStage.exploring]/[SddStage.verifying], the two
/// stages that gate on it today.
const mostRecentChatHasTerminalReplyField = TransitionFieldSpec(
  id: 'mostRecentChatHasTerminalReply',
  displayName: 'Most recent chat has a reply',
  stages: [SddStage.exploring, SddStage.verifying],
);

/// Whether the ticket has at least one direct child at the next rank down
/// — one of the three terms of [SddStage.proposed]'s current
/// `children.isNotEmpty && (needsDesign || children.every(...))` check.
const hasChildrenField = TransitionFieldSpec(
  id: 'hasChildren',
  displayName: 'Ticket has children',
  stages: [SddStage.proposed],
);

/// Wraps `TicketsCubit._storyNeedsDesignReview` — whether a Story's child
/// Tasks indicate UI work, routing it through `designBrief`/`designSync`
/// rather than straight to `verifying`.
const storyNeedsDesignReviewField = TransitionFieldSpec(
  id: 'storyNeedsDesignReview',
  displayName: 'Story needs design review',
  stages: [SddStage.proposed],
);

/// Whether every direct child at the next rank down has reached a terminal
/// state — the third term of [SddStage.proposed]'s current check.
const allChildrenCompleteField = TransitionFieldSpec(
  id: 'allChildrenComplete',
  displayName: 'All children are complete',
  stages: [SddStage.proposed],
);

/// Whether [SddStage.designBrief]'s linked design Page ticket exists and
/// has non-empty pasted content — folds "page exists" and "description
/// non-empty" into one field, since both failure modes produce the same
/// outcome today.
const linkedDesignPageHasContentField = TransitionFieldSpec(
  id: 'linkedDesignPageHasContent',
  displayName: 'Design page has content',
  stages: [SddStage.designBrief],
);

/// Whether every child Task/Bug has reached `WorkflowStatusRole.done` — one
/// of the two terms of [SddStage.designSync]'s current
/// `approved && tasks.every(...)` check.
const allTasksCompleteField = TransitionFieldSpec(
  id: 'allTasksComplete',
  displayName: 'All child tasks are complete',
  stages: [SddStage.designSync],
);

/// Wraps `TicketsCubit._designSyncApproved` — whether the Design Sync
/// chat's most recent AI reply contains `DESIGN GATE: APPROVED`.
const designSyncApprovedField = TransitionFieldSpec(
  id: 'designSyncApproved',
  displayName: 'Design sync has been approved',
  stages: [SddStage.designSync],
);

/// Wraps `TicketsCubit._verifyGateApproved` — whether the Verifying-stage
/// chat's most recent AI reply contains `VERIFY GATE: APPROVED`. Added for
/// `AIO-1905`.
const verifyGateApprovedField = TransitionFieldSpec(
  id: 'verifyGateApproved',
  displayName: 'Verification has been approved',
  stages: [SddStage.verifying],
);

/// Every field this proposal ships, regardless of stage. Exactly the 8
/// entries reproducing the precondition-bearing stages' hardcoded checks
/// as data — see
/// `AIO-1936` §1 and
/// `AIO-1905` §2.1.
const List<TransitionFieldSpec> transitionFieldCatalog = [
  mostRecentChatHasTerminalReplyField,
  hasChildrenField,
  storyNeedsDesignReviewField,
  allChildrenCompleteField,
  linkedDesignPageHasContentField,
  allTasksCompleteField,
  designSyncApprovedField,
  verifyGateApprovedField,
];

/// The subset of [transitionFieldCatalog] valid for [stage] — what
/// `TransitionNodeForm`'s field picker offers when editing that stage's
/// graph.
List<TransitionFieldSpec> transitionFieldsFor(SddStage stage) {
  return transitionFieldCatalog
      .where((field) => field.stages.contains(stage))
      .toList();
}

/// [fieldId]'s [TransitionFieldSpec] in [transitionFieldCatalog], or `null`
/// if [fieldId] doesn't match any shipped field.
TransitionFieldSpec? transitionFieldById(String fieldId) {
  for (final field in transitionFieldCatalog) {
    if (field.id == fieldId) return field;
  }
  return null;
}
