// test/core/automation/decision_field_catalog_test.dart — decision_field_catalog.dart pure-function tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_field_catalog.dart';
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
}
