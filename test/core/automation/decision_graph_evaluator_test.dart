// test/core/automation/decision_graph_evaluator_test.dart — evaluateDecisionGraph pure-function tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_field_catalog.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_graph_evaluator.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';
import 'package:aion/core/contracts/agent_session_handle.dart';
import 'package:aion/core/contracts/provider_id.dart';

void main() {
  const graphContext = AutomationContext.codingExecutionRetry;

  group('evaluateDecisionGraph', () {
    test('null root always resolves proceed', () async {
      const graph = DecisionGraph(context: graphContext, rootNodeId: null);

      final outcome = await evaluateDecisionGraph(
        graph,
        const {},
        const DecisionEvalContext(),
      );

      expect(outcome, DecisionOutcome.proceed);
    });

    test(
      'single node — matched branch terminates on a matching condition',
      () async {
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

        final outcome = await evaluateDecisionGraph(
          graph,
          nodes,
          const DecisionEvalContext(attempt: 3),
        );

        expect(outcome, DecisionOutcome.gated);
      },
    );

    test(
      'single node — unmatched branch terminates when condition is false',
      () async {
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

        final outcome = await evaluateDecisionGraph(
          graph,
          nodes,
          const DecisionEvalContext(attempt: 1),
        );

        expect(outcome, DecisionOutcome.proceed);
      },
    );

    test(
      'multi-level tree — walks matched then unmatched to a terminal',
      () async {
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
        final outcome = await evaluateDecisionGraph(
          graph,
          nodes,
          const DecisionEvalContext(attempt: 5, sessionOverageDetected: false),
        );

        expect(outcome, DecisionOutcome.gated);

        // Same tree, overage detected this time (child's matched → decline).
        final declineOutcome = await evaluateDecisionGraph(
          graph,
          nodes,
          const DecisionEvalContext(attempt: 5, sessionOverageDetected: true),
        );

        expect(declineOutcome, DecisionOutcome.decline);
      },
    );

    test(
      'modelJudgment resolves identically to proceed at evaluation time',
      () async {
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

        final outcome = await evaluateDecisionGraph(
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

    test('a dangling node reference resolves proceed defensively', () async {
      const graph = DecisionGraph(context: graphContext, rootNodeId: 'missing');

      final outcome = await evaluateDecisionGraph(
        graph,
        const {},
        const DecisionEvalContext(),
      );

      expect(outcome, DecisionOutcome.proceed);
    });

    test(
      'an unknown conditionId never matches, following the unmatched branch',
      () async {
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

        final outcome = await evaluateDecisionGraph(
          graph,
          nodes,
          const DecisionEvalContext(),
        );

        expect(outcome, DecisionOutcome.proceed);
      },
    );
  });

  group('evaluateDecisionGraph — ruleBuilder condition', () {
    Future<DecisionOutcome> evalRule(
      Map<String, dynamic> params,
      DecisionEvalContext input,
    ) async {
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

    test('greaterThan on attempt', () async {
      final params = {
        'field': 'attempt',
        'operator': 'greaterThan',
        'value': 3,
      };
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 4)),
        DecisionOutcome.gated,
      );
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test('greaterThanOrEqual on attempt', () async {
      final params = {
        'field': 'attempt',
        'operator': 'greaterThanOrEqual',
        'value': 3,
      };
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.gated,
      );
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 2)),
        DecisionOutcome.proceed,
      );
    });

    test('lessThan on attempt', () async {
      final params = {'field': 'attempt', 'operator': 'lessThan', 'value': 3};
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 2)),
        DecisionOutcome.gated,
      );
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test('lessThanOrEqual on attempt', () async {
      final params = {
        'field': 'attempt',
        'operator': 'lessThanOrEqual',
        'value': 3,
      };
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.gated,
      );
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 4)),
        DecisionOutcome.proceed,
      );
    });

    test('equals on attempt', () async {
      final params = {'field': 'attempt', 'operator': 'equals', 'value': 3};
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.gated,
      );
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 4)),
        DecisionOutcome.proceed,
      );
    });

    test('notEquals on attempt', () async {
      final params = {'field': 'attempt', 'operator': 'notEquals', 'value': 3};
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 4)),
        DecisionOutcome.gated,
      );
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test(
      'equals/notEquals on the boolean sessionOverageDetected field',
      () async {
        final equalsParams = {
          'field': 'sessionOverageDetected',
          'operator': 'equals',
          'value': true,
        };
        expect(
          await evalRule(
            equalsParams,
            const DecisionEvalContext(sessionOverageDetected: true),
          ),
          DecisionOutcome.gated,
        );
        expect(
          await evalRule(
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
          await evalRule(
            notEqualsParams,
            const DecisionEvalContext(sessionOverageDetected: false),
          ),
          DecisionOutcome.gated,
        );
        expect(
          await evalRule(
            notEqualsParams,
            const DecisionEvalContext(sessionOverageDetected: true),
          ),
          DecisionOutcome.proceed,
        );
      },
    );

    test('an unrecognized field evaluates false defensively', () async {
      final params = {'field': 'notAField', 'operator': 'equals', 'value': 3};
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test('an unrecognized operator evaluates false defensively', () async {
      final params = {
        'field': 'attempt',
        'operator': 'notAnOperator',
        'value': 3,
      };
      expect(
        await evalRule(params, const DecisionEvalContext(attempt: 3)),
        DecisionOutcome.proceed,
      );
    });

    test('a null underlying field value evaluates false defensively', () async {
      final params = {
        'field': 'attempt',
        'operator': 'greaterThan',
        'value': 0,
      };
      expect(
        await evalRule(params, const DecisionEvalContext()),
        DecisionOutcome.proceed,
      );
    });
  });

  group('evaluateDecisionGraph — agentJudgment condition', () {
    const session = AgentSessionHandle(
      providerId: ProviderId.claudeAgentSdk,
      sessionId: 'session-1',
      modelId: 'claude-sonnet-5',
    );

    Future<DecisionOutcome> evalAgentJudgment({
      required Map<String, dynamic> params,
      AgentSessionHandle? session,
      Future<bool?> Function(AgentSessionHandle, String)? askAgentJudgment,
    }) async {
      const graph = DecisionGraph(context: graphContext, rootNodeId: 'n1');
      final nodes = {
        'n1': DecisionNode(
          id: 'n1',
          conditionId: agentJudgmentConditionId,
          conditionParams: params,
          matchedBranch: const DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: const DecisionBranch.terminal(
            DecisionOutcome.proceed,
          ),
        ),
      };
      return evaluateDecisionGraph(
        graph,
        nodes,
        DecisionEvalContext(
          session: session,
          askAgentJudgment: askAgentJudgment,
        ),
      );
    }

    test('askAgentJudgment returning true matches', () async {
      final outcome = await evalAgentJudgment(
        params: const {'prompt': 'Is this expensive?'},
        session: session,
        askAgentJudgment: (_, _) async => true,
      );
      expect(outcome, DecisionOutcome.gated);
    });

    test('askAgentJudgment returning false is unmatched', () async {
      final outcome = await evalAgentJudgment(
        params: const {'prompt': 'Is this expensive?'},
        session: session,
        askAgentJudgment: (_, _) async => false,
      );
      expect(outcome, DecisionOutcome.proceed);
    });

    test('askAgentJudgment returning null is unmatched', () async {
      final outcome = await evalAgentJudgment(
        params: const {'prompt': 'Is this expensive?'},
        session: session,
        askAgentJudgment: (_, _) async => null,
      );
      expect(outcome, DecisionOutcome.proceed);
    });

    test(
      'session == null is unmatched, askAgentJudgment never invoked',
      () async {
        var called = false;
        final outcome = await evalAgentJudgment(
          params: const {'prompt': 'Is this expensive?'},
          session: null,
          askAgentJudgment: (_, _) async {
            called = true;
            return true;
          },
        );
        expect(outcome, DecisionOutcome.proceed);
        expect(called, isFalse);
      },
    );

    test('askAgentJudgment == null is unmatched', () async {
      final outcome = await evalAgentJudgment(
        params: const {'prompt': 'Is this expensive?'},
        session: session,
        askAgentJudgment: null,
      );
      expect(outcome, DecisionOutcome.proceed);
    });

    test(
      'missing prompt is unmatched, never invokes askAgentJudgment',
      () async {
        var called = false;
        final outcome = await evalAgentJudgment(
          params: const {},
          session: session,
          askAgentJudgment: (_, _) async {
            called = true;
            return true;
          },
        );
        expect(outcome, DecisionOutcome.proceed);
        expect(called, isFalse);
      },
    );

    test(
      'non-String prompt is unmatched, never invokes askAgentJudgment',
      () async {
        var called = false;
        final outcome = await evalAgentJudgment(
          params: const {'prompt': 42},
          session: session,
          askAgentJudgment: (_, _) async {
            called = true;
            return true;
          },
        );
        expect(outcome, DecisionOutcome.proceed);
        expect(called, isFalse);
      },
    );
  });
}
