// test/core/automation/decision_graph_evaluator_test.dart — evaluateDecisionGraph pure-function tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_graph_evaluator.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';

void main() {
  const graphContext = AutomationContext.codingExecutionRetry;

  group('evaluateDecisionGraph', () {
    test('null root always resolves proceed', () {
      const graph = DecisionGraph(context: graphContext, rootNodeId: null);

      final outcome = evaluateDecisionGraph(
        graph,
        const {},
        const DecisionEvalContext(),
      );

      expect(outcome, DecisionOutcome.proceed);
    });

    test('single node — matched branch terminates on a matching condition', () {
      const graph = DecisionGraph(context: graphContext, rootNodeId: 'n1');
      const nodes = {
        'n1': DecisionNode(
          id: 'n1',
          conditionId: 'attemptExceedsMax',
          conditionParams: {'maxAttempts': 2},
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        ),
      };

      final outcome = evaluateDecisionGraph(
        graph,
        nodes,
        const DecisionEvalContext(attempt: 3),
      );

      expect(outcome, DecisionOutcome.gated);
    });

    test(
      'single node — unmatched branch terminates when condition is false',
      () {
        const graph = DecisionGraph(context: graphContext, rootNodeId: 'n1');
        const nodes = {
          'n1': DecisionNode(
            id: 'n1',
            conditionId: 'attemptExceedsMax',
            conditionParams: {'maxAttempts': 2},
            matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
            unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
          ),
        };

        final outcome = evaluateDecisionGraph(
          graph,
          nodes,
          const DecisionEvalContext(attempt: 1),
        );

        expect(outcome, DecisionOutcome.proceed);
      },
    );

    test('multi-level tree — walks matched then unmatched to a terminal', () {
      const graph = DecisionGraph(context: graphContext, rootNodeId: 'root');
      const nodes = {
        'root': DecisionNode(
          id: 'root',
          conditionId: 'attemptExceedsMax',
          conditionParams: {'maxAttempts': 1},
          matchedBranch: DecisionBranch.toNode('child'),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        ),
        'child': DecisionNode(
          id: 'child',
          conditionId: 'sessionOverageDetected',
          conditionParams: {},
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.decline),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        ),
      };

      // Attempt exceeds max (matched → child), overage not detected
      // (child's unmatched → gated).
      final outcome = evaluateDecisionGraph(
        graph,
        nodes,
        const DecisionEvalContext(attempt: 5, sessionOverageDetected: false),
      );

      expect(outcome, DecisionOutcome.gated);

      // Same tree, overage detected this time (child's matched → decline).
      final declineOutcome = evaluateDecisionGraph(
        graph,
        nodes,
        const DecisionEvalContext(attempt: 5, sessionOverageDetected: true),
      );

      expect(declineOutcome, DecisionOutcome.decline);
    });

    test(
      'modelJudgment resolves identically to proceed at evaluation time',
      () {
        const graph = DecisionGraph(context: graphContext, rootNodeId: 'n1');
        const nodes = {
          'n1': DecisionNode(
            id: 'n1',
            conditionId: 'sessionOverageDetected',
            conditionParams: {},
            matchedBranch: DecisionBranch.terminal(
              DecisionOutcome.modelJudgment,
            ),
            unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
          ),
        };

        final outcome = evaluateDecisionGraph(
          graph,
          nodes,
          const DecisionEvalContext(sessionOverageDetected: true),
        );

        // Distinct value, but the caller-side switch in TicketsCubit treats
        // it exactly like `proceed` — this test only asserts the evaluator
        // returns the distinct value faithfully rather than collapsing it.
        expect(outcome, DecisionOutcome.modelJudgment);
      },
    );

    test('a dangling node reference resolves proceed defensively', () {
      const graph = DecisionGraph(context: graphContext, rootNodeId: 'missing');

      final outcome = evaluateDecisionGraph(
        graph,
        const {},
        const DecisionEvalContext(),
      );

      expect(outcome, DecisionOutcome.proceed);
    });

    test(
      'an unknown conditionId never matches, following the unmatched branch',
      () {
        const graph = DecisionGraph(context: graphContext, rootNodeId: 'n1');
        const nodes = {
          'n1': DecisionNode(
            id: 'n1',
            conditionId: 'notInTheRegistry',
            conditionParams: {},
            matchedBranch: DecisionBranch.terminal(DecisionOutcome.decline),
            unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
          ),
        };

        final outcome = evaluateDecisionGraph(
          graph,
          nodes,
          const DecisionEvalContext(),
        );

        expect(outcome, DecisionOutcome.proceed);
      },
    );
  });
}
