// domain/utils/evaluate_transition_graph.dart — evaluateTransitionGraph pure evaluator (domain layer).

import 'package:meta/meta.dart';

import 'package:aion/features/tickets/domain/entities/transition_branch.dart';
import 'package:aion/features/tickets/domain/entities/transition_field_spec.dart';
import 'package:aion/features/tickets/domain/entities/transition_node.dart';
import 'package:aion/features/tickets/domain/enums/transition_outcome.dart';
import 'package:aion/features/tickets/domain/repositories/transition_precondition_repository.dart';

/// Every value a [TransitionFieldSpec] might need to read, bundled by the
/// call site rather than fetched by [evaluateTransitionGraph] itself —
/// keeps that function pure (no I/O) and trivially unit-testable. Mirrors
/// `core/automation/decision_graph_evaluator.dart`'s `DecisionEvalContext`
/// "bundled by the caller, not fetched here" convention, one field per
/// `transitionFieldCatalog` entry. Every field is optional; a stage's
/// evaluation only ever reads the fields valid for it. Added for
/// `aion-arch/changes/sddstage-transition-preconditions`.
@immutable
class TransitionEvalContext {
  /// Creates a [TransitionEvalContext].
  const TransitionEvalContext({
    this.mostRecentChatHasTerminalReply,
    this.hasChildren,
    this.storyNeedsDesignReview,
    this.allChildrenComplete,
    this.linkedDesignPageHasContent,
    this.allTasksComplete,
    this.designSyncApproved,
    this.verifyGateApproved,
  });

  /// Value for [mostRecentChatHasTerminalReplyField].
  final bool? mostRecentChatHasTerminalReply;

  /// Value for [hasChildrenField].
  final bool? hasChildren;

  /// Value for [storyNeedsDesignReviewField].
  final bool? storyNeedsDesignReview;

  /// Value for [allChildrenCompleteField].
  final bool? allChildrenComplete;

  /// Value for [linkedDesignPageHasContentField].
  final bool? linkedDesignPageHasContent;

  /// Value for [allTasksCompleteField].
  final bool? allTasksComplete;

  /// Value for [designSyncApprovedField].
  final bool? designSyncApproved;

  /// Value for [verifyGateApprovedField].
  final bool? verifyGateApproved;
}

/// `TransitionFieldSpec.id → current value` accessor registry — how
/// [evaluateTransitionGraph] resolves a `TransitionNode.fieldId` to the
/// [TransitionEvalContext] value it names. Adding a field to
/// `transition_field_spec.dart`'s catalog also means adding its accessor
/// here.
final Map<String, bool? Function(TransitionEvalContext input)> _fieldAccessors =
    {
      mostRecentChatHasTerminalReplyField.id: (input) =>
          input.mostRecentChatHasTerminalReply,
      hasChildrenField.id: (input) => input.hasChildren,
      storyNeedsDesignReviewField.id: (input) => input.storyNeedsDesignReview,
      allChildrenCompleteField.id: (input) => input.allChildrenComplete,
      linkedDesignPageHasContentField.id: (input) =>
          input.linkedDesignPageHasContent,
      allTasksCompleteField.id: (input) => input.allTasksComplete,
      designSyncApprovedField.id: (input) => input.designSyncApproved,
      verifyGateApprovedField.id: (input) => input.verifyGateApproved,
    };

/// Walks [graph] from its `TransitionGraph.rootNodeId`, evaluating each
/// [TransitionNode] (looked up in [nodesById]) against [input] via
/// [_fieldAccessors], following `TransitionNode.matchedBranch`/
/// `.unmatchedBranch` until a `TransitionBranch.terminal` is reached.
/// Returns `(outcome: TransitionOutcome.allowed, blockingFieldDisplayName:
/// null)` immediately if `TransitionGraph.rootNodeId` is `null` (no
/// precondition configured — an unconfigured stage should never gate,
/// mirroring `evaluateDecisionGraph`'s own "never silently block" defensive
/// posture) or if the walk ever references a node id missing from
/// [nodesById] (a dangling reference resolves that node's branch as
/// unmatched, never throws). A missing/`null` field value in [input] also
/// resolves as unmatched, the same defensive treatment. On `blocked`,
/// [blockingFieldDisplayName] carries the failing node's field's
/// `TransitionFieldSpec.displayName`, so the call site can build `'Waiting
/// on: $blockingFieldDisplayName'` without a second lookup. Pure — no I/O.
/// Added for `aion-arch/changes/sddstage-transition-preconditions`.
({TransitionOutcome outcome, String? blockingFieldDisplayName})
evaluateTransitionGraph(
  TransitionGraph graph,
  Map<String, TransitionNode> nodesById,
  TransitionEvalContext input,
) {
  var currentId = graph.rootNodeId;
  if (currentId == null) {
    return (outcome: TransitionOutcome.allowed, blockingFieldDisplayName: null);
  }

  while (true) {
    final node = nodesById[currentId];
    if (node == null) {
      return (
        outcome: TransitionOutcome.allowed,
        blockingFieldDisplayName: null,
      );
    }

    final matched = _fieldAccessors[node.fieldId]?.call(input) ?? false;
    final branch = matched ? node.matchedBranch : node.unmatchedBranch;

    switch (branch) {
      case ToTransitionNodeBranch(:final nodeId):
        currentId = nodeId;
      case TerminalTransitionBranch(:final outcome):
        final blockingFieldDisplayName = outcome == TransitionOutcome.blocked
            ? transitionFieldById(node.fieldId)?.displayName
            : null;
        return (
          outcome: outcome,
          blockingFieldDisplayName: blockingFieldDisplayName,
        );
    }
  }
}
