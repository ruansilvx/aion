// test/features/providers/presentation/cubit/decision_graph_config_cubit_test.dart — DecisionGraphConfigCubit tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_graph_repository.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_state.dart';

class MockDecisionGraphRepository extends Mock
    implements DecisionGraphRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(AutomationContext.codingExecutionRetry);
    registerFallbackValue(
      const DecisionNode(
        id: 'fallback',
        conditionId: 'attemptExceedsMax',
        conditionParams: {},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      ),
    );
  });

  late MockDecisionGraphRepository repository;
  late DecisionGraphConfigCubit cubit;

  const automationContext = AutomationContext.codingExecutionRetry;

  const rootNode = DecisionNode(
    id: 'root',
    conditionId: 'attemptExceedsMax',
    conditionParams: {'maxAttempts': 2},
    matchedBranch: DecisionBranch.toNode('child'),
    unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
  );
  const childNode = DecisionNode(
    id: 'child',
    conditionId: 'attemptExceedsMax',
    conditionParams: {'maxAttempts': 5},
    matchedBranch: DecisionBranch.terminal(DecisionOutcome.decline),
    unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
  );

  setUp(() {
    repository = MockDecisionGraphRepository();
    cubit = DecisionGraphConfigCubit(repository);

    when(() => repository.getGraph(automationContext)).thenAnswer(
      (_) async =>
          const DecisionGraph(context: automationContext, rootNodeId: 'root'),
    );
    when(
      () => repository.getAllNodes(automationContext),
    ).thenAnswer((_) async => const [rootNode, childNode]);
    when(() => repository.upsertNode(any())).thenAnswer((_) async {});
    when(() => repository.deleteNode(any())).thenAnswer((_) async {});
    when(
      () => repository.setRoot(automationContext, any()),
    ).thenAnswer((_) async {});
  });

  group('load', () {
    test(
      'emits DecisionGraphConfigLoaded with the graph and its nodes',
      () async {
        await cubit.load(automationContext);

        final state = cubit.state as DecisionGraphConfigLoaded;
        expect(state.context, automationContext);
        expect(state.graph.rootNodeId, 'root');
        expect(state.nodesById.keys, containsAll(['root', 'child']));
      },
    );
  });

  group('createNode', () {
    test('creates a standalone node and returns its id', () async {
      await cubit.load(automationContext);

      final newId = await cubit.createNode(
        conditionId: 'attemptExceedsMax',
        conditionParams: const {'maxAttempts': 1},
      );

      expect(newId, isNotNull);
      verify(() => repository.upsertNode(any())).called(1);
    });

    test('rejects with duplicateChildReference when both branches would '
        'point at the same existing node', () async {
      await cubit.load(automationContext);

      await cubit.createNode(
        conditionId: 'attemptExceedsMax',
        conditionParams: const {},
        matchedBranch: const DecisionBranch.toNode('child'),
        unmatchedBranch: const DecisionBranch.toNode('child'),
      );

      final state = cubit.state as DecisionGraphConfigError;
      expect(
        state.reason,
        DecisionGraphConfigErrorReason.duplicateChildReference,
      );
      // The prior loaded tree is preserved, not clobbered.
      expect(state.previous.nodesById.keys, containsAll(['root', 'child']));
      verifyNever(() => repository.upsertNode(any()));
    });

    test('rejects with danglingBranchTarget when a branch points at a node '
        'id absent from the loaded set', () async {
      await cubit.load(automationContext);

      await cubit.createNode(
        conditionId: 'attemptExceedsMax',
        conditionParams: const {},
        matchedBranch: const DecisionBranch.toNode('does-not-exist'),
      );

      final state = cubit.state as DecisionGraphConfigError;
      expect(state.reason, DecisionGraphConfigErrorReason.danglingBranchTarget);
    });
  });

  group('updateNode', () {
    test('rejects with nodeNotFound when the node id is unknown', () async {
      await cubit.load(automationContext);

      await cubit.updateNode(
        const DecisionNode(
          id: 'not-loaded',
          conditionId: 'attemptExceedsMax',
          conditionParams: {},
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        ),
      );

      final state = cubit.state as DecisionGraphConfigError;
      expect(state.reason, DecisionGraphConfigErrorReason.nodeNotFound);
      verifyNever(() => repository.upsertNode(any()));
    });

    test(
      'rejects with cycleDetected when an edit would make the root '
      'unreachable-without-repeat (a node pointing back at an ancestor)',
      () async {
        await cubit.load(automationContext);

        // child's matched branch now points back at root — a cycle
        // reachable from the graph's own root.
        await cubit.updateNode(
          childNode.copyWith(
            matchedBranch: const DecisionBranch.toNode('root'),
          ),
        );

        final state = cubit.state as DecisionGraphConfigError;
        expect(state.reason, DecisionGraphConfigErrorReason.cycleDetected);
      },
    );

    test('persists a valid edit and reloads', () async {
      await cubit.load(automationContext);

      await cubit.updateNode(
        rootNode.copyWith(conditionParams: const {'maxAttempts': 9}),
      );

      verify(() => repository.upsertNode(any())).called(1);
    });

    test('rejects with cycleDetected for a cycle among nodes not reachable '
        'from the graph root — /verify fix pass 2 regression: the previous '
        'root-only reachability walk missed this case entirely', () async {
      // A separate fixture: root's branches are both terminal (nothing
      // reachable from it), plus two orphan nodes — orphanA already
      // points at orphanB, neither attached to root or referenced by
      // anyone. This loads validly.
      const detachedRoot = DecisionNode(
        id: 'root',
        conditionId: 'attemptExceedsMax',
        conditionParams: {'maxAttempts': 2},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
      );
      const orphanA = DecisionNode(
        id: 'orphanA',
        conditionId: 'attemptExceedsMax',
        conditionParams: {'maxAttempts': 4},
        matchedBranch: DecisionBranch.toNode('orphanB'),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      const orphanB = DecisionNode(
        id: 'orphanB',
        conditionId: 'attemptExceedsMax',
        conditionParams: {'maxAttempts': 6},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
      );
      when(
        () => repository.getAllNodes(automationContext),
      ).thenAnswer((_) async => const [detachedRoot, orphanA, orphanB]);

      await cubit.load(automationContext);

      // orphanB's unmatched branch now points back at orphanA, closing
      // a cycle (orphanA -> orphanB -> orphanA) entirely disconnected
      // from the graph's actual root.
      await cubit.updateNode(
        orphanB.copyWith(
          unmatchedBranch: const DecisionBranch.toNode('orphanA'),
        ),
      );

      final state = cubit.state as DecisionGraphConfigError;
      expect(state.reason, DecisionGraphConfigErrorReason.cycleDetected);
      verifyNever(() => repository.upsertNode(any()));
    });
  });

  group('deleteNode', () {
    test('clears the graph root when deleting the root node', () async {
      await cubit.load(automationContext);

      await cubit.deleteNode('root');

      verify(() => repository.deleteNode('root')).called(1);
      verify(() => repository.setRoot(automationContext, null)).called(1);
    });

    test('does not clear the root when deleting a non-root node', () async {
      await cubit.load(automationContext);

      await cubit.deleteNode('child');

      verify(() => repository.deleteNode('child')).called(1);
      verifyNever(() => repository.setRoot(automationContext, any()));
    });
  });

  group('setRoot', () {
    test(
      'rejects with nodeNotFound for an id outside the loaded set',
      () async {
        await cubit.load(automationContext);

        await cubit.setRoot('unknown-id');

        final state = cubit.state as DecisionGraphConfigError;
        expect(state.reason, DecisionGraphConfigErrorReason.nodeNotFound);
        verifyNever(() => repository.setRoot(automationContext, any()));
      },
    );

    test('accepts null (clearing the graph)', () async {
      await cubit.load(automationContext);

      await cubit.setRoot(null);

      verify(() => repository.setRoot(automationContext, null)).called(1);
    });
  });
}
