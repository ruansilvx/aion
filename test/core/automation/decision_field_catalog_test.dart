// test/core/automation/decision_field_catalog_test.dart — decision_field_catalog.dart pure-function tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_field_catalog.dart';
import 'package:aion/core/automation/decision_graph_evaluator.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';

void main() {
  group('decisionFieldsFor', () {
    test('returns attemptField for codingExecutionRetry', () {
      final fields = decisionFieldsFor(AutomationContext.codingExecutionRetry);
      expect(fields, [attemptField]);
    });

    test('returns sessionOverageDetectedField for codingExecution', () {
      final fields = decisionFieldsFor(AutomationContext.codingExecution);
      expect(fields, [sessionOverageDetectedField]);
    });

    test('returns empty for a context with no rule-builder fields', () {
      expect(decisionFieldsFor(AutomationContext.sddStage), isEmpty);
    });
  });

  group('operatorsFor', () {
    test('integer gets all six operators', () {
      expect(
        operatorsFor(DecisionFieldType.integer),
        DecisionRuleOperator.values,
      );
    });

    test('boolean gets only the fixed equals ("is") operator', () {
      expect(operatorsFor(DecisionFieldType.boolean), [
        DecisionRuleOperator.equals,
      ]);
    });
  });

  group('ruleBuilderConditionSpec', () {
    test('non-null for a context with fields', () {
      final spec = ruleBuilderConditionSpec(
        AutomationContext.codingExecutionRetry,
      );
      expect(spec, isNotNull);
      expect(spec!.id, ruleBuilderConditionId);
      expect(spec.parameterSpecs, isEmpty);
    });

    test('null for a context with no rule-builder fields', () {
      expect(ruleBuilderConditionSpec(AutomationContext.sddStage), isNull);
    });
  });

  group('defaultRuleConditionParams', () {
    test('seeds an integer field to 0 with the first valid operator', () {
      final params = defaultRuleConditionParams(
        AutomationContext.codingExecutionRetry,
      );
      expect(params['field'], 'attempt');
      expect(params['operator'], DecisionRuleOperator.values.first.name);
      expect(params['value'], 0);
    });

    test('seeds a boolean field to false with the first valid operator', () {
      final params = defaultRuleConditionParams(
        AutomationContext.codingExecution,
      );
      expect(params['field'], 'sessionOverageDetected');
      expect(params['operator'], DecisionRuleOperator.equals.name);
      expect(params['value'], false);
    });

    test('returns {} for a context with no rule-builder fields', () {
      expect(defaultRuleConditionParams(AutomationContext.sddStage), {});
    });
  });

  group('isRecognizedConditionId', () {
    const context = AutomationContext.codingExecutionRetry;

    test('true for a real catalog entry', () {
      expect(isRecognizedConditionId('attemptExceedsMax', context), isTrue);
    });

    test('true for the rule-builder id', () {
      expect(isRecognizedConditionId(ruleBuilderConditionId, context), isTrue);
    });

    test('false for an unknown id', () {
      expect(isRecognizedConditionId('notInTheRegistry', context), isFalse);
    });
  });

  group('decisionNodeTitle', () {
    test('a catalog node returns its spec displayName', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: 'attemptExceedsMax',
        conditionParams: {'maxAttempts': 3},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(decisionNodeTitle(node), 'Attempt count exceeds');
    });

    test('a rule-builder node returns its chosen field displayName', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: ruleBuilderConditionId,
        conditionParams: {
          'field': 'attempt',
          'operator': 'greaterThan',
          'value': 3,
        },
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(decisionNodeTitle(node), 'Attempt count');
    });

    test('a rule-builder node with a malformed field falls back to the '
        'conditionId, never throwing', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: ruleBuilderConditionId,
        conditionParams: {'field': 'notAField'},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(() => decisionNodeTitle(node), returnsNormally);
      expect(decisionNodeTitle(node), ruleBuilderConditionId);
    });

    test('an unrecognized conditionId falls back to the raw id', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: 'notInTheRegistry',
        conditionParams: {},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(decisionNodeTitle(node), 'notInTheRegistry');
    });
  });

  group('decisionNodeSummary', () {
    test('a catalog node returns its conditionParameterSummary output', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: 'attemptExceedsMax',
        conditionParams: {'maxAttempts': 3},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(decisionNodeSummary(node), '> 3');
    });

    test('a flag-only catalog node returns null', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: 'sessionOverageDetected',
        conditionParams: {},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(decisionNodeSummary(node), isNull);
    });

    test('a rule-builder integer node formats "<symbol> <value>"', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: ruleBuilderConditionId,
        conditionParams: {
          'field': 'attempt',
          'operator': 'greaterThanOrEqual',
          'value': 2,
        },
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(decisionNodeSummary(node), '≥ 2');
    });

    test('a rule-builder boolean node formats "is <value>"', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: ruleBuilderConditionId,
        conditionParams: {
          'field': 'sessionOverageDetected',
          'operator': 'equals',
          'value': false,
        },
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(decisionNodeSummary(node), 'is False');
    });

    test('a rule-builder node with a malformed field returns null, never '
        'throwing', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: ruleBuilderConditionId,
        conditionParams: {'field': 'notAField'},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(() => decisionNodeSummary(node), returnsNormally);
      expect(decisionNodeSummary(node), isNull);
    });

    test('a rule-builder node with a missing field returns null, never '
        'throwing', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: ruleBuilderConditionId,
        conditionParams: {},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(() => decisionNodeSummary(node), returnsNormally);
      expect(decisionNodeSummary(node), isNull);
    });

    test('a rule-builder node with a malformed operator returns null, '
        'never throwing', () {
      const node = DecisionNode(
        id: 'n1',
        conditionId: ruleBuilderConditionId,
        conditionParams: {'field': 'attempt', 'operator': 'notAnOperator'},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      expect(() => decisionNodeSummary(node), returnsNormally);
      expect(decisionNodeSummary(node), isNull);
    });
  });

  group('agentJudgmentConditionSpec', () {
    test('null for a non-eligible context', () {
      expect(agentJudgmentConditionSpec(AutomationContext.sddStage), isNull);
    });

    test('a real spec for each of the 3 eligible contexts', () {
      for (final context in [
        AutomationContext.ticketCreation,
        AutomationContext.ticketLinking,
        AutomationContext.chatBranching,
      ]) {
        final spec = agentJudgmentConditionSpec(context);
        expect(spec, isNotNull, reason: '$context should be eligible');
        expect(spec!.id, agentJudgmentConditionId);
        expect(spec.contexts, [context]);
        expect(spec.parameterSpecs, isEmpty);
      }
    });
  });

  group(
    'agentJudgment — isRecognizedConditionId/decisionNodeTitle/decisionNodeSummary',
    () {
      const context = AutomationContext.ticketCreation;

      test('isRecognizedConditionId is true for the agentJudgment id', () {
        expect(
          isRecognizedConditionId(agentJudgmentConditionId, context),
          isTrue,
        );
      });

      test('decisionNodeTitle returns the fixed "Ask the agent" fallback', () {
        const node = DecisionNode(
          id: 'n1',
          conditionId: agentJudgmentConditionId,
          conditionParams: {'prompt': 'Is this fix expensive?'},
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        );
        expect(decisionNodeTitle(node), 'Ask the agent');
      });

      test(
        'decisionNodeTitle returns the same fallback for a missing/empty prompt',
        () {
          const node = DecisionNode(
            id: 'n1',
            conditionId: agentJudgmentConditionId,
            conditionParams: {},
            matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
            unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
          );
          expect(() => decisionNodeTitle(node), returnsNormally);
          expect(decisionNodeTitle(node), 'Ask the agent');
        },
      );

      test('decisionNodeSummary returns the authored prompt verbatim', () {
        const node = DecisionNode(
          id: 'n1',
          conditionId: agentJudgmentConditionId,
          conditionParams: {'prompt': 'Is this fix expensive?'},
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        );
        expect(decisionNodeSummary(node), 'Is this fix expensive?');
      });

      test('decisionNodeSummary truncates a prompt over ~120 chars', () {
        final longPrompt = 'a' * 150;
        final node = DecisionNode(
          id: 'n1',
          conditionId: agentJudgmentConditionId,
          conditionParams: {'prompt': longPrompt},
          matchedBranch: const DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: const DecisionBranch.terminal(
            DecisionOutcome.proceed,
          ),
        );
        final summary = decisionNodeSummary(node);
        expect(summary, isNotNull);
        expect(summary!.length, 121); // 120 chars + the ellipsis character.
        expect(summary.endsWith('…'), isTrue);
      });

      test('decisionNodeSummary returns null for a missing/empty prompt, never '
          'throwing', () {
        const missing = DecisionNode(
          id: 'n1',
          conditionId: agentJudgmentConditionId,
          conditionParams: {},
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        );
        expect(() => decisionNodeSummary(missing), returnsNormally);
        expect(decisionNodeSummary(missing), isNull);

        const empty = DecisionNode(
          id: 'n1',
          conditionId: agentJudgmentConditionId,
          conditionParams: {'prompt': ''},
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        );
        expect(decisionNodeSummary(empty), isNull);

        const nonString = DecisionNode(
          id: 'n1',
          conditionId: agentJudgmentConditionId,
          conditionParams: {'prompt': 42},
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        );
        expect(() => decisionNodeSummary(nonString), returnsNormally);
        expect(decisionNodeSummary(nonString), isNull);
      });
    },
  );
}
