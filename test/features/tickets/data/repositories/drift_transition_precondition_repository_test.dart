// test/features/tickets/data/repositories/drift_transition_precondition_repository_test.dart — DriftTransitionPreconditionRepository persistence tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/repositories/drift_transition_precondition_repository.dart';
import 'package:aion/features/tickets/tickets.dart';

/// Dummy project — unused since the test passes an explicit in-memory
/// executor, mirroring `automation_decision_dao_test.dart`'s own
/// precedent.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

/// [DriftTransitionPreconditionRepository] tests against a real in-memory
/// drift instance — genuine persistence behavior (seeding idempotency,
/// the baseline trees' shape), so this isn't mocked, per
/// `automation_decision_dao_test.dart`'s own precedent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DriftTransitionPreconditionRepository repository;

  setUp(() async {
    database = AppDatabase(_testProject, NativeDatabase.memory());
    repository = DriftTransitionPreconditionRepository(database);
    // AppDatabase's own onCreate already seeds every precondition-bearing
    // stage's baseline graph — cleared here so each test below starts
    // from a genuinely empty table, matching what it actually asserts.
    for (final row in await database.transitionPreconditionDao.getAllNodes()) {
      await database.transitionPreconditionDao.deleteNode(row.id);
    }
    final existingGraphs = await database
        .customSelect('SELECT sdd_stage FROM transition_precondition_graphs')
        .get();
    for (final row in existingGraphs) {
      await database.customStatement(
        'DELETE FROM transition_precondition_graphs WHERE sdd_stage = ?',
        [row.read<String>('sdd_stage')],
      );
    }
  });

  tearDown(() async {
    await database.close();
  });

  group('seedDefaultsIfEmpty', () {
    test(
      'seeds a graph for each of the 5 precondition-bearing stages',
      () async {
        await repository.seedDefaultsIfEmpty();

        for (final stage in [
          SddStage.exploring,
          SddStage.proposed,
          SddStage.designBrief,
          SddStage.designSync,
          SddStage.verifying,
        ]) {
          final graph = await repository.getGraph(stage);
          expect(
            graph.rootNodeId,
            isNotNull,
            reason: '${stage.name} should be seeded',
          );
        }
      },
    );

    test('seeds no graph for null/archived', () async {
      await repository.seedDefaultsIfEmpty();

      final archived = await repository.getGraph(SddStage.archived);
      expect(archived.rootNodeId, isNull);
    });

    test(
      'exploring/verifying each seed a single mostRecentChatHasTerminalReply '
      'node — matched allowed, unmatched blocked',
      () async {
        await repository.seedDefaultsIfEmpty();

        for (final stage in [SddStage.exploring, SddStage.verifying]) {
          final nodes = await repository.getAllNodes(stage);
          expect(nodes, hasLength(1), reason: stage.name);
          final node = nodes.single;
          expect(node.fieldId, 'mostRecentChatHasTerminalReply');
          expect(
            node.matchedBranch,
            const TransitionBranch.terminal(TransitionOutcome.allowed),
          );
          expect(
            node.unmatchedBranch,
            const TransitionBranch.terminal(TransitionOutcome.blocked),
          );
        }
      },
    );

    test('proposed seeds the 3-node tree reproducing children.isNotEmpty && '
        '(needsDesign || children.every(...))', () async {
      await repository.seedDefaultsIfEmpty();

      final nodes = await repository.getAllNodes(SddStage.proposed);
      expect(nodes, hasLength(3));

      final graph = await repository.getGraph(SddStage.proposed);
      final byId = {for (final n in nodes) n.id: n};
      final root = byId[graph.rootNodeId]!;
      expect(root.fieldId, 'hasChildren');
      expect(
        root.unmatchedBranch,
        const TransitionBranch.terminal(TransitionOutcome.blocked),
      );

      final storyNeedsDesignReview =
          byId[(root.matchedBranch as ToTransitionNodeBranch).nodeId]!;
      expect(storyNeedsDesignReview.fieldId, 'storyNeedsDesignReview');
      expect(
        storyNeedsDesignReview.matchedBranch,
        const TransitionBranch.terminal(TransitionOutcome.allowed),
      );

      final allChildrenComplete =
          byId[(storyNeedsDesignReview.unmatchedBranch
                  as ToTransitionNodeBranch)
              .nodeId]!;
      expect(allChildrenComplete.fieldId, 'allChildrenComplete');
      expect(
        allChildrenComplete.matchedBranch,
        const TransitionBranch.terminal(TransitionOutcome.allowed),
      );
      expect(
        allChildrenComplete.unmatchedBranch,
        const TransitionBranch.terminal(TransitionOutcome.blocked),
      );
    });

    test('designBrief seeds a single linkedDesignPageHasContent node — matched '
        'allowed, unmatched blocked', () async {
      await repository.seedDefaultsIfEmpty();

      final nodes = await repository.getAllNodes(SddStage.designBrief);
      expect(nodes, hasLength(1));
      final node = nodes.single;
      expect(node.fieldId, 'linkedDesignPageHasContent');
      expect(
        node.matchedBranch,
        const TransitionBranch.terminal(TransitionOutcome.allowed),
      );
      expect(
        node.unmatchedBranch,
        const TransitionBranch.terminal(TransitionOutcome.blocked),
      );
    });

    test('designSync seeds the 2-node tree reproducing approved && '
        'tasks.isNotEmpty && tasks.every(...)', () async {
      await repository.seedDefaultsIfEmpty();

      final nodes = await repository.getAllNodes(SddStage.designSync);
      expect(nodes, hasLength(2));

      final graph = await repository.getGraph(SddStage.designSync);
      final byId = {for (final n in nodes) n.id: n};
      final root = byId[graph.rootNodeId]!;
      expect(root.fieldId, 'allTasksComplete');
      expect(
        root.unmatchedBranch,
        const TransitionBranch.terminal(TransitionOutcome.blocked),
      );

      final designSyncApproved =
          byId[(root.matchedBranch as ToTransitionNodeBranch).nodeId]!;
      expect(designSyncApproved.fieldId, 'designSyncApproved');
      expect(
        designSyncApproved.matchedBranch,
        const TransitionBranch.terminal(TransitionOutcome.allowed),
      );
      expect(
        designSyncApproved.unmatchedBranch,
        const TransitionBranch.terminal(TransitionOutcome.blocked),
      );
    });

    test('is idempotent — calling twice never duplicates rows', () async {
      await repository.seedDefaultsIfEmpty();
      await repository.seedDefaultsIfEmpty();

      // 1 (exploring) + 1 (verifying) + 3 (proposed) + 1 (designBrief) +
      // 2 (designSync) = 8 baseline nodes total, never doubled.
      final allNodes = await database.transitionPreconditionDao.getAllNodes();
      expect(allNodes, hasLength(8));
    });

    test('is a no-op on an already-populated graph table', () async {
      await repository.setRoot(SddStage.exploring, null);

      await repository.seedDefaultsIfEmpty();

      final graph = await repository.getGraph(SddStage.proposed);
      expect(graph.rootNodeId, isNull);
    });
  });

  group('upsertNode / getNode / deleteNode', () {
    test('CRUD round-trips a node', () async {
      const node = TransitionNode(
        id: 'n1',
        fieldId: 'hasChildren',
        matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
        unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
      );
      await repository.upsertNode(node);
      var fetched = await repository.getNode('n1');
      expect(fetched, node);

      const updated = TransitionNode(
        id: 'n1',
        fieldId: 'hasChildren',
        matchedBranch: TransitionBranch.toNode('n2'),
        unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
      );
      await repository.upsertNode(updated);
      fetched = await repository.getNode('n1');
      expect(fetched, updated);

      await repository.deleteNode('n1');
      fetched = await repository.getNode('n1');
      expect(fetched, isNull);
    });
  });

  group('setRoot', () {
    test('writes a graph row for a stage with no prior row', () async {
      await repository.setRoot(SddStage.exploring, 'some-node');

      final graph = await repository.getGraph(SddStage.exploring);
      expect(graph.rootNodeId, 'some-node');
    });

    test('clears an existing root back to null', () async {
      await repository.setRoot(SddStage.exploring, 'some-node');
      await repository.setRoot(SddStage.exploring, null);

      final graph = await repository.getGraph(SddStage.exploring);
      expect(graph.rootNodeId, isNull);
    });
  });

  group('onChanged', () {
    test('fires on upsertNode', () async {
      final events = <void>[];
      final sub = repository.onChanged.listen(events.add);

      await repository.upsertNode(
        const TransitionNode(
          id: 'n1',
          fieldId: 'hasChildren',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
      );

      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('fires on deleteNode', () async {
      await repository.upsertNode(
        const TransitionNode(
          id: 'n1',
          fieldId: 'hasChildren',
          matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
          unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
        ),
      );
      final events = <void>[];
      final sub = repository.onChanged.listen(events.add);

      await repository.deleteNode('n1');

      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('fires on setRoot', () async {
      final events = <void>[];
      final sub = repository.onChanged.listen(events.add);

      await repository.setRoot(SddStage.exploring, 'n1');

      expect(events, hasLength(1));
      await sub.cancel();
    });
  });

  group('getNodeCounts', () {
    test('is empty when no graph has ever been seeded/configured', () async {
      expect(await repository.getNodeCounts(), isEmpty);
    });

    test('counts 0 for a graph row with a null root', () async {
      await repository.setRoot(SddStage.exploring, null);

      expect(await repository.getNodeCounts(), {SddStage.exploring: 0});
    });

    test(
      'counts every node reachable from each stage\'s root, in one batch',
      () async {
        // exploring: a single-node tree.
        await repository.upsertNode(
          const TransitionNode(
            id: 'exploring-n1',
            fieldId: 'mostRecentChatHasTerminalReply',
            matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
            unmatchedBranch: TransitionBranch.terminal(
              TransitionOutcome.blocked,
            ),
          ),
        );
        await repository.setRoot(SddStage.exploring, 'exploring-n1');

        // proposed: the 3-node baseline shape.
        await repository.upsertNode(
          const TransitionNode(
            id: 'proposed-allChildrenComplete',
            fieldId: 'allChildrenComplete',
            matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
            unmatchedBranch: TransitionBranch.terminal(
              TransitionOutcome.blocked,
            ),
          ),
        );
        await repository.upsertNode(
          const TransitionNode(
            id: 'proposed-storyNeedsDesignReview',
            fieldId: 'storyNeedsDesignReview',
            matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
            unmatchedBranch: TransitionBranch.toNode(
              'proposed-allChildrenComplete',
            ),
          ),
        );
        await repository.upsertNode(
          const TransitionNode(
            id: 'proposed-hasChildren',
            fieldId: 'hasChildren',
            matchedBranch: TransitionBranch.toNode(
              'proposed-storyNeedsDesignReview',
            ),
            unmatchedBranch: TransitionBranch.terminal(
              TransitionOutcome.blocked,
            ),
          ),
        );
        await repository.setRoot(SddStage.proposed, 'proposed-hasChildren');

        // designBrief: no graph configured at all — absent from the
        // result entirely (never seeded/setRoot-touched), distinct from
        // a `0` count.
        expect(await repository.getNodeCounts(), {
          SddStage.exploring: 1,
          SddStage.proposed: 3,
        });
      },
    );
  });
}
