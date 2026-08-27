// test/core/automation/data/drift_decision_graph_repository_test.dart — DriftDecisionGraphRepository delegation tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:drift/drift.dart' show Value;

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/data/automation_decision_dao.dart';
import 'package:aion/core/automation/data/drift_decision_graph_repository.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';
import 'package:aion/core/database/app_database.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockAutomationDecisionDao extends Mock implements AutomationDecisionDao {}

/// [DriftDecisionGraphRepository] is a thin delegate over
/// [AutomationDecisionDao] — per `project.md`'s repository-test
/// convention (see `drift_workflow_status_repository_test.dart`), these
/// tests mock the DAO via mocktail rather than spinning up a real drift
/// instance.
void main() {
  setUpAll(() {
    registerFallbackValue(
      const AutomationDecisionNodesTableCompanion(id: Value('fallback')),
    );
  });

  late MockAppDatabase database;
  late MockAutomationDecisionDao dao;
  late DriftDecisionGraphRepository repository;

  setUp(() {
    database = MockAppDatabase();
    dao = MockAutomationDecisionDao();
    when(() => database.automationDecisionDao).thenReturn(dao);
    repository = DriftDecisionGraphRepository(database);
  });

  group('getGraph', () {
    test('maps a persisted row to a DecisionGraph', () async {
      when(() => dao.getGraph(AutomationContext.codingExecution)).thenAnswer(
        (_) async => const AutomationDecisionGraphData(
          context: 'codingExecution',
          rootNodeId: 'root-1',
        ),
      );

      final result = await repository.getGraph(
        AutomationContext.codingExecution,
      );

      expect(
        result,
        const DecisionGraph(
          context: AutomationContext.codingExecution,
          rootNodeId: 'root-1',
        ),
      );
    });

    test('defaults to a null-root graph when unseeded', () async {
      when(
        () => dao.getGraph(AutomationContext.sddStage),
      ).thenAnswer((_) async => null);

      final result = await repository.getGraph(AutomationContext.sddStage);

      expect(
        result,
        const DecisionGraph(
          context: AutomationContext.sddStage,
          rootNodeId: null,
        ),
      );
    });
  });

  group('getAllNodes', () {
    test('walks from the root, collecting only reachable nodes', () async {
      when(
        () => dao.getGraph(AutomationContext.codingExecutionRetry),
      ).thenAnswer(
        (_) async => const AutomationDecisionGraphData(
          context: 'codingExecutionRetry',
          rootNodeId: 'root',
        ),
      );
      when(() => dao.getAllNodes()).thenAnswer(
        (_) async => const [
          AutomationDecisionNodeData(
            id: 'root',
            conditionId: 'attemptExceedsMax',
            conditionParamsJson: '{"maxAttempts":2}',
            matchedBranchKind: 'node',
            matchedBranchNodeId: 'child',
            unmatchedBranchKind: 'proceed',
            unmatchedBranchNodeId: null,
          ),
          AutomationDecisionNodeData(
            id: 'child',
            conditionId: 'sessionOverageDetected',
            conditionParamsJson: '{}',
            matchedBranchKind: 'decline',
            matchedBranchNodeId: null,
            unmatchedBranchKind: 'gated',
            unmatchedBranchNodeId: null,
          ),
          // Orphaned row — unreachable from `root`, belongs to no
          // currently-rooted graph. Must not appear in the result.
          AutomationDecisionNodeData(
            id: 'orphan',
            conditionId: 'attemptExceedsMax',
            conditionParamsJson: '{"maxAttempts":5}',
            matchedBranchKind: 'gated',
            matchedBranchNodeId: null,
            unmatchedBranchKind: 'proceed',
            unmatchedBranchNodeId: null,
          ),
        ],
      );

      final result = await repository.getAllNodes(
        AutomationContext.codingExecutionRetry,
      );

      expect(result.map((n) => n.id), containsAll(['root', 'child']));
      expect(result.map((n) => n.id), isNot(contains('orphan')));
      final root = result.firstWhere((n) => n.id == 'root');
      expect(root.matchedBranch, const DecisionBranch.toNode('child'));
      expect(
        root.unmatchedBranch,
        const DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      final child = result.firstWhere((n) => n.id == 'child');
      expect(
        child.matchedBranch,
        const DecisionBranch.terminal(DecisionOutcome.decline),
      );
      expect(
        child.unmatchedBranch,
        const DecisionBranch.terminal(DecisionOutcome.gated),
      );
    });

    test('returns empty when the graph has no root', () async {
      when(
        () => dao.getGraph(AutomationContext.ticketCreation),
      ).thenAnswer((_) async => null);

      final result = await repository.getAllNodes(
        AutomationContext.ticketCreation,
      );

      expect(result, isEmpty);
      verifyNever(() => dao.getAllNodes());
    });
  });

  group('upsertNode', () {
    test(
      'round-trips conditionParams and both branch kinds through the DAO',
      () async {
        when(() => dao.upsertNode(any())).thenAnswer((_) async {});

        const node = DecisionNode(
          id: 'n1',
          conditionId: 'attemptExceedsMax',
          conditionParams: {'maxAttempts': 4},
          matchedBranch: DecisionBranch.toNode('n2'),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        );

        await repository.upsertNode(node);

        final captured = verify(() => dao.upsertNode(captureAny())).captured;
        final companion =
            captured.single as AutomationDecisionNodesTableCompanion;
        expect(companion.id.value, 'n1');
        expect(companion.conditionParamsJson.value, '{"maxAttempts":4}');
        expect(companion.matchedBranchKind.value, 'node');
        expect(companion.matchedBranchNodeId.value, 'n2');
        expect(companion.unmatchedBranchKind.value, 'proceed');
        expect(companion.unmatchedBranchNodeId.value, isNull);
      },
    );

    test('fires onChanged', () async {
      when(() => dao.upsertNode(any())).thenAnswer((_) async {});
      final events = <void>[];
      final sub = repository.onChanged.listen(events.add);

      await repository.upsertNode(
        const DecisionNode(
          id: 'n1',
          conditionId: 'attemptExceedsMax',
          conditionParams: {},
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        ),
      );

      expect(events, hasLength(1));
      await sub.cancel();
    });
  });

  group('deleteNode / setRoot', () {
    test('deleteNode delegates to the DAO and fires onChanged', () async {
      when(() => dao.deleteNode('n1')).thenAnswer((_) async {});
      final events = <void>[];
      final sub = repository.onChanged.listen(events.add);

      await repository.deleteNode('n1');

      verify(() => dao.deleteNode('n1')).called(1);
      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('setRoot delegates to the DAO and fires onChanged', () async {
      when(
        () => dao.setRoot(AutomationContext.chatBranching, 'n1'),
      ).thenAnswer((_) async {});
      final events = <void>[];
      final sub = repository.onChanged.listen(events.add);

      await repository.setRoot(AutomationContext.chatBranching, 'n1');

      verify(
        () => dao.setRoot(AutomationContext.chatBranching, 'n1'),
      ).called(1);
      expect(events, hasLength(1));
      await sub.cancel();
    });
  });

  group('seedDefaultsIfEmpty', () {
    test('delegates to AutomationDecisionDao.seedDefaultsIfEmpty', () async {
      when(() => dao.seedDefaultsIfEmpty()).thenAnswer((_) async {});

      await repository.seedDefaultsIfEmpty();

      verify(() => dao.seedDefaultsIfEmpty()).called(1);
    });
  });
}
