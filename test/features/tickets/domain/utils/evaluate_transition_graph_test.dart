// test/features/tickets/domain/utils/evaluate_transition_graph_test.dart — evaluateTransitionGraph pure-function tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/tickets/domain/entities/transition_branch.dart';
import 'package:aion/features/tickets/domain/entities/transition_field_spec.dart';
import 'package:aion/features/tickets/domain/entities/transition_node.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/transition_outcome.dart';
import 'package:aion/features/tickets/domain/repositories/transition_precondition_repository.dart';
import 'package:aion/features/tickets/domain/utils/evaluate_transition_graph.dart';

void main() {
  group('evaluateTransitionGraph', () {
    test('null root resolves allowed, no blocking field name', () {
      const graph = TransitionGraph(stage: SddStage.proposed, rootNodeId: null);

      final result = evaluateTransitionGraph(
        graph,
        const {},
        const TransitionEvalContext(),
      );

      expect(result.outcome, TransitionOutcome.allowed);
      expect(result.blockingFieldDisplayName, isNull);
    });

    test('single node — matched branch terminates allowed', () {
      const graph = TransitionGraph(
        stage: SddStage.designBrief,
        rootNodeId: 'n1',
      );
      const nodes = {
        'n1': TransitionNode(
          id: 'n1',
          fieldId: 'linkedDesignPageHasContent',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
      };

      final result = evaluateTransitionGraph(
        graph,
        nodes,
        const TransitionEvalContext(linkedDesignPageHasContent: true),
      );

      expect(result.outcome, TransitionOutcome.allowed);
      expect(result.blockingFieldDisplayName, isNull);
    });

    test('single node — unmatched branch terminates blocked with the field '
        'display name', () {
      const graph = TransitionGraph(
        stage: SddStage.designBrief,
        rootNodeId: 'n1',
      );
      const nodes = {
        'n1': TransitionNode(
          id: 'n1',
          fieldId: 'linkedDesignPageHasContent',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
      };

      final result = evaluateTransitionGraph(
        graph,
        nodes,
        const TransitionEvalContext(linkedDesignPageHasContent: false),
      );

      expect(result.outcome, TransitionOutcome.blocked);
      expect(
        result.blockingFieldDisplayName,
        linkedDesignPageHasContentField.displayName,
      );
    });

    test('the 3-node proposed tree walks correctly across every branch '
        'combination', () {
      const graph = TransitionGraph(
        stage: SddStage.proposed,
        rootNodeId: 'hasChildren',
      );
      const nodes = {
        'hasChildren': TransitionNode(
          id: 'hasChildren',
          fieldId: 'hasChildren',
          matchedBranch: TransitionBranch.toNode('storyNeedsDesignReview'),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
        'storyNeedsDesignReview': TransitionNode(
          id: 'storyNeedsDesignReview',
          fieldId: 'storyNeedsDesignReview',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.toNode('allChildrenComplete'),
        ),
        'allChildrenComplete': TransitionNode(
          id: 'allChildrenComplete',
          fieldId: 'allChildrenComplete',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
      };

      // No children at all — blocked at the root, never reaches the
      // other two nodes.
      expect(
        evaluateTransitionGraph(
          graph,
          nodes,
          const TransitionEvalContext(hasChildren: false),
        ).outcome,
        TransitionOutcome.blocked,
      );

      // Has children, needs design review — allowed via
      // storyNeedsDesignReview's matched branch.
      expect(
        evaluateTransitionGraph(
          graph,
          nodes,
          const TransitionEvalContext(
            hasChildren: true,
            storyNeedsDesignReview: true,
          ),
        ).outcome,
        TransitionOutcome.allowed,
      );

      // Has children, doesn't need design review, all children complete
      // — allowed via allChildrenComplete's matched branch.
      expect(
        evaluateTransitionGraph(
          graph,
          nodes,
          const TransitionEvalContext(
            hasChildren: true,
            storyNeedsDesignReview: false,
            allChildrenComplete: true,
          ),
        ).outcome,
        TransitionOutcome.allowed,
      );

      // Has children, doesn't need design review, children not all
      // complete — blocked.
      final blocked = evaluateTransitionGraph(
        graph,
        nodes,
        const TransitionEvalContext(
          hasChildren: true,
          storyNeedsDesignReview: false,
          allChildrenComplete: false,
        ),
      );
      expect(blocked.outcome, TransitionOutcome.blocked);
      expect(
        blocked.blockingFieldDisplayName,
        allChildrenCompleteField.displayName,
      );
    });

    test('the 2-node designSync tree walks correctly', () {
      const graph = TransitionGraph(
        stage: SddStage.designSync,
        rootNodeId: 'allTasksComplete',
      );
      const nodes = {
        'allTasksComplete': TransitionNode(
          id: 'allTasksComplete',
          fieldId: 'allTasksComplete',
          matchedBranch: TransitionBranch.toNode('designSyncApproved'),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
        'designSyncApproved': TransitionNode(
          id: 'designSyncApproved',
          fieldId: 'designSyncApproved',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
      };

      // Tasks not all complete — blocked at the root.
      final tasksIncomplete = evaluateTransitionGraph(
        graph,
        nodes,
        const TransitionEvalContext(
          allTasksComplete: false,
          designSyncApproved: true,
        ),
      );
      expect(tasksIncomplete.outcome, TransitionOutcome.blocked);
      expect(
        tasksIncomplete.blockingFieldDisplayName,
        allTasksCompleteField.displayName,
      );

      // Tasks complete, not approved — blocked at the child.
      final notApproved = evaluateTransitionGraph(
        graph,
        nodes,
        const TransitionEvalContext(
          allTasksComplete: true,
          designSyncApproved: false,
        ),
      );
      expect(notApproved.outcome, TransitionOutcome.blocked);
      expect(
        notApproved.blockingFieldDisplayName,
        designSyncApprovedField.displayName,
      );

      // Tasks complete and approved — allowed.
      expect(
        evaluateTransitionGraph(
          graph,
          nodes,
          const TransitionEvalContext(
            allTasksComplete: true,
            designSyncApproved: true,
          ),
        ).outcome,
        TransitionOutcome.allowed,
      );
    });

    test('a dangling ToTransitionNodeBranch reference resolves allowed '
        'defensively, never throws', () {
      const graph = TransitionGraph(
        stage: SddStage.designBrief,
        rootNodeId: 'missing',
      );

      final result = evaluateTransitionGraph(
        graph,
        const {},
        const TransitionEvalContext(),
      );

      expect(result.outcome, TransitionOutcome.allowed);
      expect(result.blockingFieldDisplayName, isNull);
    });

    test('a node whose fieldId has no matching TransitionEvalContext value '
        '(a stale/unrecognized field) resolves unmatched defensively', () {
      const graph = TransitionGraph(
        stage: SddStage.designBrief,
        rootNodeId: 'n1',
      );
      const nodes = {
        'n1': TransitionNode(
          id: 'n1',
          fieldId: 'noLongerShipped',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
      };

      final result = evaluateTransitionGraph(
        graph,
        nodes,
        const TransitionEvalContext(),
      );

      // Unmatched — but the field doesn't resolve via
      // transitionFieldById, so blockingFieldDisplayName falls back to
      // null rather than throwing.
      expect(result.outcome, TransitionOutcome.blocked);
      expect(result.blockingFieldDisplayName, isNull);
    });
  });
}
