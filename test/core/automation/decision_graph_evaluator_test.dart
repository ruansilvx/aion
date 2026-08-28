// test/core/automation/decision_graph_evaluator_test.dart — evaluateDecisionGraph pure-function tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_field_catalog.dart';
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

  group('evaluateDecisionGraph — ruleBuilder condition', () {
    DecisionOutcome evalRule(
      Map<String, dynamic> params,
      DecisionEvalContext input,
    ) {
      const graph = DecisionGraph(context: graphContext, rootNodeId: 'n1');
      final nodes = {
        'n1': DecisionNode(
          id: 'n1',
          conditionId: ruleBuilderConditionId,
          conditionParams: params,
          matchedBranch: const DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: const DecisionBranch.terminal(
            DecisionOutcome.proceed,
          ),
        ),
      };
      return evaluateDecisionGraph(graph, nodes, input);
    }

    test('greaterThan on attempt', () {
      final params = {
        'field': 'attempt',
        'operator': 'greaterThan',
        'value': 3,
      };
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 4)),
        DecisionOutcome.gated,
      );
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test('greaterThanOrEqual on attempt', () {
      final params = {
        'field': 'attempt',
        'operator': 'greaterThanOrEqual',
        'value': 3,
      };
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.gated,
      );
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 2)),
        DecisionOutcome.proceed,
      );
    });

    test('lessThan on attempt', () {
      final params = {'field': 'attempt', 'operator': 'lessThan', 'value': 3};
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 2)),
        DecisionOutcome.gated,
      );
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test('lessThanOrEqual on attempt', () {
      final params = {
        'field': 'attempt',
        'operator': 'lessThanOrEqual',
        'value': 3,
      };
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.gated,
      );
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 4)),
        DecisionOutcome.proceed,
      );
    });

    test('equals on attempt', () {
      final params = {'field': 'attempt', 'operator': 'equals', 'value': 3};
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.gated,
      );
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 4)),
        DecisionOutcome.proceed,
      );
    });

    test('notEquals on attempt', () {
      final params = {
        'field': 'attempt',
        'operator': 'notEquals',
        'value': 3,
      };
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 4)),
        DecisionOutcome.gated,
      );
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test('equals/notEquals on the boolean sessionOverageDetected field', () {
      final equalsParams = {
        'field': 'sessionOverageDetected',
        'operator': 'equals',
        'value': true,
      };
      expect(
        evalRule(
          equalsParams,
          const DecisionEvalContext(sessionOverageDetected: true),
        ),
        DecisionOutcome.gated,
      );
      expect(
        evalRule(
          equalsParams,
          const DecisionEvalContext(sessionOverageDetected: false),
        ),
        DecisionOutcome.proceed,
      );

      final notEqualsParams = {
        'field': 'sessionOverageDetected',
        'operator': 'notEquals',
        'value': true,
      };
      expect(
        evalRule(
          notEqualsParams,
          const DecisionEvalContext(sessionOverageDetected: false),
        ),
        DecisionOutcome.gated,
      );
      expect(
        evalRule(
          notEqualsParams,
          const DecisionEvalContext(sessionOverageDetected: true),
        ),
        DecisionOutcome.proceed,
      );
    });

    test('an unrecognized field evaluates false defensively', () {
      final params = {
        'field': 'notAField',
        'operator': 'equals',
        'value': 3,
      };
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test('an unrecognized operator evaluates false defensively', () {
      final params = {
        'field': 'attempt',
        'operator': 'notAnOperator',
        'value': 3,
      };
      expect(
        evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test('a null underlying field value evaluates false defensively', () {
      final params = {
        'field': 'attempt',
        'operator': 'greaterThan',
        'value': 0,
      };
      expect(
        evalRule(params, const DecisionEvalContext()),
        DecisionOutcome.proceed,
      );
    });
  });
}
