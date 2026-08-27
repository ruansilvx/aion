// test/core/automation/data/automation_decision_dao_test.dart — AutomationDecisionDao CRUD and seeding tests.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/automation/data/automation_decision_dao.dart';
import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';

/// Dummy project — unused since every test passes an explicit in-memory
/// executor, mirroring `workflow_status_dao_test.dart`'s own precedent.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

/// Direct [AutomationDecisionDao] tests against a real in-memory drift
/// instance — genuine persistence behavior (seeding idempotency, the
/// baseline nodes' shape), so this isn't mocked like most repository
/// tests, per `workflow_status_dao_test.dart`'s own precedent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AutomationDecisionDao dao;

  setUp(() async {
    database = AppDatabase(_testProject, NativeDatabase.memory());
    dao = database.automationDecisionDao;
    // AppDatabase's own onCreate already seeds every context's graph row
    // (see app_database_test.dart) — cleared here so each test below
    // starts from a genuinely empty table, matching what it actually
    // asserts.
    for (final row in await dao.getAllNodes()) {
      await dao.deleteNode(row.id);
    }
    final existingGraph = await database
        .customSelect('SELECT context FROM automation_decision_graphs')
        .get();
    for (final row in existingGraph) {
      await database.customStatement(
        'DELETE FROM automation_decision_graphs WHERE context = ?',
        [row.read<String>('context')],
      );
    }
  });

  tearDown(() async {
    await database.close();
  });

  group('seedDefaultsIfEmpty', () {
    test('seeds a graph row for every AutomationContext', () async {
      await dao.seedDefaultsIfEmpty();

      final graphs = <String>[];
      for (final context in AutomationContext.values) {
        final row = await dao.getGraph(context);
        expect(row, isNotNull, reason: '${context.name} should be seeded');
        graphs.add(context.name);
      }
      expect(graphs, hasLength(AutomationContext.values.length));
    });

    test('seeds a single attemptExceedsMax(maxAttempts: 2) node as '
        'codingExecutionRetry\'s root, reproducing the former '
        'attempt > _maxVerifyRetries hardcoded check', () async {
      await dao.seedDefaultsIfEmpty();

      final graph = await dao.getGraph(AutomationContext.codingExecutionRetry);
      expect(graph, isNotNull);
      final rootId = graph!.rootNodeId;
      expect(rootId, isNotNull);

      final node = await dao.getNode(rootId!);
      expect(node, isNotNull);
      expect(node!.conditionId, 'attemptExceedsMax');
      expect(node.conditionParamsJson, '{"maxAttempts":2}');
      expect(node.matchedBranchKind, 'gated');
      expect(node.unmatchedBranchKind, 'proceed');
    });

    test('seeds a single sessionOverageDetected node as codingExecution\'s '
        'root, reproducing the former _overageDetectedThisSession hardcoded '
        'check', () async {
      await dao.seedDefaultsIfEmpty();

      final graph = await dao.getGraph(AutomationContext.codingExecution);
      expect(graph, isNotNull);
      final rootId = graph!.rootNodeId;
      expect(rootId, isNotNull);

      final node = await dao.getNode(rootId!);
      expect(node, isNotNull);
      expect(node!.conditionId, 'sessionOverageDetected');
      expect(node.matchedBranchKind, 'gated');
      expect(node.unmatchedBranchKind, 'proceed');
    });

    test('seeds a null root for every other context', () async {
      await dao.seedDefaultsIfEmpty();

      for (final context in [
        AutomationContext.sddStage,
        AutomationContext.chatBranching,
        AutomationContext.codingExecutionResume,
        AutomationContext.ticketCreation,
        AutomationContext.ticketLinking,
        AutomationContext.specAutoLink,
      ]) {
        final graph = await dao.getGraph(context);
        expect(graph!.rootNodeId, isNull, reason: context.name);
      }
    });

    test('is idempotent — calling twice never duplicates rows', () async {
      await dao.seedDefaultsIfEmpty();
      await dao.seedDefaultsIfEmpty();

      final nodes = await dao.getAllNodes();
      // Exactly the two baseline nodes (codingExecutionRetry,
      // codingExecution) — never doubled.
      expect(nodes, hasLength(2));
    });

    test('is a no-op on an already-populated graph table', () async {
      await dao.setRoot(AutomationContext.ticketCreation, null);

      await dao.seedDefaultsIfEmpty();

      // Only the one row this test itself wrote — seeding never ran.
      final graph = await dao.getGraph(AutomationContext.codingExecution);
      expect(graph, isNull);
    });
  });

  group('upsertNode / getNode / deleteNode', () {
    test('CRUD round-trips a node row', () async {
      await dao.upsertNode(
        AutomationDecisionNodesTableCompanion.insert(
          id: 'n1',
          conditionId: 'attemptExceedsMax',
          conditionParamsJson: '{"maxAttempts":3}',
          matchedBranchKind: 'gated',
          unmatchedBranchKind: 'proceed',
        ),
      );
      var node = await dao.getNode('n1');
      expect(node!.conditionParamsJson, '{"maxAttempts":3}');

      await dao.upsertNode(
        AutomationDecisionNodesTableCompanion.insert(
          id: 'n1',
          conditionId: 'attemptExceedsMax',
          conditionParamsJson: '{"maxAttempts":5}',
          matchedBranchKind: 'decline',
          unmatchedBranchKind: 'proceed',
        ),
      );
      node = await dao.getNode('n1');
      expect(node!.conditionParamsJson, '{"maxAttempts":5}');
      expect(node.matchedBranchKind, 'decline');

      await dao.deleteNode('n1');
      node = await dao.getNode('n1');
      expect(node, isNull);
    });
  });

  group('setRoot', () {
    test('writes a graph row for a context with no prior row', () async {
      await dao.setRoot(AutomationContext.ticketLinking, 'some-node');

      final graph = await dao.getGraph(AutomationContext.ticketLinking);
      expect(graph!.rootNodeId, 'some-node');
    });

    test('clears an existing root back to null', () async {
      await dao.setRoot(AutomationContext.ticketLinking, 'some-node');
      await dao.setRoot(AutomationContext.ticketLinking, null);

      final graph = await dao.getGraph(AutomationContext.ticketLinking);
      expect(graph!.rootNodeId, isNull);
    });
  });
}
