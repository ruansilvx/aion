// test/features/providers/presentation/cubit/transition_precondition_config_cubit_test.dart — TransitionPreconditionConfigCubit tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/providers/presentation/cubit/transition_precondition_config_cubit.dart';
import 'package:aion/features/providers/presentation/cubit/transition_precondition_config_state.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTransitionPreconditionRepository extends Mock
    implements TransitionPreconditionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(SddStage.proposed);
    registerFallbackValue(
      const TransitionNode(
        id: 'fallback',
        fieldId: 'hasChildren',
        matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
        unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
      ),
    );
  });

  late MockTransitionPreconditionRepository repository;
  late TransitionPreconditionConfigCubit cubit;

  const stage = SddStage.proposed;

  const rootNode = TransitionNode(
    id: 'root',
    fieldId: 'hasChildren',
    matchedBranch: TransitionBranch.toNode('child'),
    unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
  );
  const childNode = TransitionNode(
    id: 'child',
    fieldId: 'storyNeedsDesignReview',
    matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
    unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
  );

  setUp(() {
    repository = MockTransitionPreconditionRepository();
    cubit = TransitionPreconditionConfigCubit(repository);

    when(() => repository.getGraph(stage)).thenAnswer(
      (_) async => const TransitionGraph(stage: stage, rootNodeId: 'root'),
    );
    when(
      () => repository.getAllNodes(stage),
    ).thenAnswer((_) async => const [rootNode, childNode]);
    when(() => repository.upsertNode(any())).thenAnswer((_) async {});
    when(() => repository.deleteNode(any())).thenAnswer((_) async {});
    when(() => repository.setRoot(stage, any())).thenAnswer((_) async {});
  });

  group('load', () {
    test('emits TransitionPreconditionConfigLoaded with the graph and its '
        'nodes', () async {
      await cubit.load(stage);

      final state = cubit.state as TransitionPreconditionConfigLoaded;
      expect(state.stage, stage);
      expect(state.graph.rootNodeId, 'root');
      expect(state.nodesById.keys, containsAll(['root', 'child']));
    });
  });

  group('createNode', () {
    test('creates a standalone node and returns its id', () async {
      await cubit.load(stage);

      final newId = await cubit.createNode(fieldId: 'allChildrenComplete');

      expect(newId, isNotNull);
      verify(() => repository.upsertNode(any())).called(1);
    });

    test(
      'rejects when both branches would point at the same existing node',
      () async {
        await cubit.load(stage);

        await cubit.createNode(
          fieldId: 'allChildrenComplete',
          matchedBranch: const TransitionBranch.toNode('child'),
          unmatchedBranch: const TransitionBranch.toNode('child'),
        );

        final state = cubit.state as TransitionPreconditionConfigError;
        // The prior loaded tree is preserved, not clobbered.
        expect(state.previous.nodesById.keys, containsAll(['root', 'child']));
        verifyNever(() => repository.upsertNode(any()));
      },
    );

    test('rejects when a branch points at a node id absent from the loaded '
        'set', () async {
      await cubit.load(stage);

      await cubit.createNode(
        fieldId: 'allChildrenComplete',
        matchedBranch: const TransitionBranch.toNode('does-not-exist'),
      );

      expect(cubit.state, isA<TransitionPreconditionConfigError>());
    });

    test(
      'keeps the freshly created node in state even though the repository '
      'reload does not return it yet — mirrors '
      '`DecisionGraphConfigCubit.createNode`\'s own fix for this case',
      () async {
        await cubit.load(stage);

        final newId = await cubit.createNode(fieldId: 'allChildrenComplete');
        expect(newId, isNotNull);

        final loaded = cubit.state as TransitionPreconditionConfigLoaded;
        expect(loaded.nodesById.keys, contains(newId));

        await cubit.updateNode(
          rootNode.copyWith(matchedBranch: TransitionBranch.toNode(newId!)),
        );

        expect(cubit.state, isA<TransitionPreconditionConfigLoaded>());
        verify(() => repository.upsertNode(any())).called(2);
      },
    );

    test('lets setRoot attach a freshly created node as the graph\'s very '
        'first node', () async {
      const emptyStage = SddStage.designBrief;
      when(() => repository.getGraph(emptyStage)).thenAnswer(
        (_) async => const TransitionGraph(stage: emptyStage, rootNodeId: null),
      );
      when(
        () => repository.getAllNodes(emptyStage),
      ).thenAnswer((_) async => const []);
      when(
        () => repository.setRoot(emptyStage, any()),
      ).thenAnswer((_) async {});

      await cubit.load(emptyStage);

      final newId = await cubit.createNode(
        fieldId: 'linkedDesignPageHasContent',
      );
      expect(newId, isNotNull);

      await cubit.setRoot(newId);

      expect(cubit.state, isA<TransitionPreconditionConfigLoaded>());
      verify(() => repository.setRoot(emptyStage, newId)).called(1);
    });
  });

  group('updateNode', () {
    test('rejects when the node id is unknown', () async {
      await cubit.load(stage);

      await cubit.updateNode(
        const TransitionNode(
          id: 'not-loaded',
          fieldId: 'hasChildren',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
      );

      expect(cubit.state, isA<TransitionPreconditionConfigError>());
      verifyNever(() => repository.upsertNode(any()));
    });

    test(
      'rejects when an edit would create a cycle reachable from the root',
      () async {
        await cubit.load(stage);

        // child's matched branch now points back at root — a cycle
        // reachable from the graph's own root.
        await cubit.updateNode(
          childNode.copyWith(
            matchedBranch: const TransitionBranch.toNode('root'),
          ),
        );

        expect(cubit.state, isA<TransitionPreconditionConfigError>());
      },
    );

    test('persists a valid edit and reloads', () async {
      await cubit.load(stage);

      await cubit.updateNode(rootNode.copyWith(fieldId: 'allChildrenComplete'));

      verify(() => repository.upsertNode(any())).called(1);
    });

    test(
      'rejects a cycle among nodes not reachable from the graph root',
      () async {
        const detachedRoot = TransitionNode(
          id: 'root',
          fieldId: 'hasChildren',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        );
        const orphanA = TransitionNode(
          id: 'orphanA',
          fieldId: 'allChildrenComplete',
          matchedBranch: TransitionBranch.toNode('orphanB'),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        );
        const orphanB = TransitionNode(
          id: 'orphanB',
          fieldId: 'storyNeedsDesignReview',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        );
        when(
          () => repository.getAllNodes(stage),
        ).thenAnswer((_) async => const [detachedRoot, orphanA, orphanB]);

        await cubit.load(stage);

        // orphanB's unmatched branch now points back at orphanA, closing
        // a cycle entirely disconnected from the graph's actual root.
        await cubit.updateNode(
          orphanB.copyWith(
            unmatchedBranch: const TransitionBranch.toNode('orphanA'),
          ),
        );

        expect(cubit.state, isA<TransitionPreconditionConfigError>());
        verifyNever(() => repository.upsertNode(any()));
      },
    );
  });

  group('deleteNode', () {
    test('clears the graph root and cascades to every descendant when '
        'deleting the root node', () async {
      await cubit.load(stage);

      await cubit.deleteNode('root');

      verify(() => repository.deleteNode('root')).called(1);
      verify(() => repository.deleteNode('child')).called(1);
      verify(() => repository.setRoot(stage, null)).called(1);
    });

    test(
      'does not clear the root when deleting a non-root leaf node',
      () async {
        await cubit.load(stage);

        await cubit.deleteNode('child');

        verify(() => repository.deleteNode('child')).called(1);
        verifyNever(() => repository.deleteNode('root'));
        verifyNever(() => repository.setRoot(stage, any()));
      },
    );
  });

  group('descendantIdsOf', () {
    test('returns just the node itself for a leaf', () {
      expect(descendantIdsOf('child', {'root': rootNode, 'child': childNode}), {
        'child',
      });
    });

    test('walks both branches transitively', () {
      const grandchild = TransitionNode(
        id: 'grandchild',
        fieldId: 'allTasksComplete',
        matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
        unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
      );
      const chainedChild = TransitionNode(
        id: 'child',
        fieldId: 'storyNeedsDesignReview',
        matchedBranch: TransitionBranch.toNode('grandchild'),
        unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
      );
      expect(
        descendantIdsOf('root', {
          'root': rootNode,
          'child': chainedChild,
          'grandchild': grandchild,
        }),
        {'root', 'child', 'grandchild'},
      );
    });

    test('does not loop forever on a self-referencing branch', () {
      const cyclic = TransitionNode(
        id: 'cyclic',
        fieldId: 'hasChildren',
        matchedBranch: TransitionBranch.toNode('cyclic'),
        unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
      );
      expect(descendantIdsOf('cyclic', {'cyclic': cyclic}), {'cyclic'});
    });
  });

  group('setRoot', () {
    test('rejects an id outside the loaded set', () async {
      await cubit.load(stage);

      await cubit.setRoot('unknown-id');

      expect(cubit.state, isA<TransitionPreconditionConfigError>());
      verifyNever(() => repository.setRoot(stage, any()));
    });

    test('accepts null (clearing the graph)', () async {
      await cubit.load(stage);

      await cubit.setRoot(null);

      verify(() => repository.setRoot(stage, null)).called(1);
    });
  });
}
