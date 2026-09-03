// core/automation/data/automation_decision_dao.dart — AutomationDecisionDao Drift accessor (data layer).

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/data/automation_decision_graphs_table.dart';
import 'package:aion/core/automation/data/automation_decision_nodes_table.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/default_decision_graphs.dart';
import 'package:aion/core/database/app_database.dart';

part 'automation_decision_dao.g.dart';

/// Drift accessor for [AutomationDecisionGraphsTable]/
/// [AutomationDecisionNodesTable]. See `AIO-181` §2.
@DriftAccessor(
  tables: [AutomationDecisionGraphsTable, AutomationDecisionNodesTable],
)
class AutomationDecisionDao extends DatabaseAccessor<AppDatabase>
    with _$AutomationDecisionDaoMixin {
  /// Creates an [AutomationDecisionDao] bound to [db].
  AutomationDecisionDao(super.db);

  /// Returns the graph row for [context], or `null` if it hasn't been
  /// seeded yet.
  Future<AutomationDecisionGraphData?> getGraph(AutomationContext context) {
    return (select(
      automationDecisionGraphsTable,
    )..where((t) => t.context.equals(context.name))).getSingleOrNull();
  }

  /// Returns the node row with id [id], or `null` if none exists.
  Future<AutomationDecisionNodeData?> getNode(String id) {
    return (select(
      automationDecisionNodesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Returns every node row currently persisted. Callers filter down to
  /// one context's tree by walking from that context's graph root — node
  /// rows carry no stored `AutomationContext`/parent pointer of their
  /// own (see the table's own dartdoc).
  Future<List<AutomationDecisionNodeData>> getAllNodes() {
    return select(automationDecisionNodesTable).get();
  }

  /// Inserts or replaces [companion] (matched by primary key).
  Future<void> upsertNode(AutomationDecisionNodesTableCompanion companion) {
    return into(automationDecisionNodesTable).insertOnConflictUpdate(companion);
  }

  /// Deletes the node row with id [id].
  Future<void> deleteNode(String id) {
    return (delete(
      automationDecisionNodesTable,
    )..where((t) => t.id.equals(id))).go();
  }

  /// Sets [context]'s graph row's `root_node_id` to [nodeId], inserting
  /// the row first if it doesn't exist yet (defensive — every context
  /// should already have a row from [seedDefaultsIfEmpty]).
  Future<void> setRoot(AutomationContext context, String? nodeId) {
    return into(automationDecisionGraphsTable).insertOnConflictUpdate(
      AutomationDecisionGraphsTableCompanion(
        context: Value(context.name),
        rootNodeId: Value(nodeId),
      ),
    );
  }

  /// Seeds a graph row for every [AutomationContext] value iff the graph
  /// table is currently empty — checked first so this is safe
  /// (idempotent, no duplication) to call unconditionally from both
  /// `onCreate` and every `onUpgrade` branch. Every context seeds a
  /// `null`-root graph except [AutomationContext.codingExecutionRetry]/
  /// [AutomationContext.codingExecution], which each also get a single
  /// baseline node reproducing the former hardcoded
  /// `attempt > _maxVerifyRetries`/`_overageDetectedThisSession` check as
  /// data. Sourced from [defaultDecisionGraphFor]/
  /// [defaultDecisionNodesById] — the exact same fixed-id data
  /// `TicketsCubit._evaluateDecisionGraph` falls back to when constructed
  /// without a `DecisionGraphRepository`, so a freshly-seeded database and
  /// a repository-less cubit are never out of sync with each other.
  Future<void> seedDefaultsIfEmpty() async {
    final existing = await select(automationDecisionGraphsTable).get();
    if (existing.isNotEmpty) return;

    await transaction<void>(() async {
      final insertedNodeIds = <String>{};
      for (final context in AutomationContext.values) {
        final graph = defaultDecisionGraphFor(context);
        final rootNodeId = graph.rootNodeId;
        if (rootNodeId != null && insertedNodeIds.add(rootNodeId)) {
          final node = defaultDecisionNodesById[rootNodeId]!;
          await into(automationDecisionNodesTable).insert(_toCompanion(node));
        }
        await into(automationDecisionGraphsTable).insert(
          AutomationDecisionGraphsTableCompanion.insert(
            context: context.name,
            rootNodeId: Value(rootNodeId),
          ),
        );
      }
    });
  }

  /// Maps a domain [DecisionNode] (terminal-only branches, as every
  /// [defaultDecisionNodesById] entry is) to its insertable companion.
  AutomationDecisionNodesTableCompanion _toCompanion(DecisionNode node) {
    final matched = node.matchedBranch as TerminalBranch;
    final unmatched = node.unmatchedBranch as TerminalBranch;
    return AutomationDecisionNodesTableCompanion.insert(
      id: node.id,
      conditionId: node.conditionId,
      conditionParamsJson: jsonEncode(node.conditionParams),
      matchedBranchKind: matched.outcome.name,
      unmatchedBranchKind: unmatched.outcome.name,
    );
  }
}
