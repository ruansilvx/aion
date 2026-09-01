// data/daos/transition_precondition_dao.dart — TransitionPreconditionDao Drift accessor (data layer).

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/models/transition_precondition_graphs_table.dart';
import 'package:aion/features/tickets/data/models/transition_precondition_nodes_table.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';

part 'transition_precondition_dao.g.dart';

/// Drift accessor for [TransitionPreconditionGraphsTable]/
/// [TransitionPreconditionNodesTable]. See
/// `aion-arch/changes/sddstage-transition-preconditions/design.md` §2/§3.
@DriftAccessor(
  tables: [TransitionPreconditionGraphsTable, TransitionPreconditionNodesTable],
)
class TransitionPreconditionDao extends DatabaseAccessor<AppDatabase>
    with _$TransitionPreconditionDaoMixin {
  /// Creates a [TransitionPreconditionDao] bound to [db].
  TransitionPreconditionDao(super.db);

  static const _uuid = Uuid();

  /// Returns the graph row for [stage], or `null` if it hasn't been seeded
  /// yet.
  Future<TransitionPreconditionGraphData?> getGraph(SddStage stage) {
    return (select(
      transitionPreconditionGraphsTable,
    )..where((t) => t.sddStage.equals(stage.name))).getSingleOrNull();
  }

  /// Returns every graph row currently persisted (one per seeded/
  /// configured `SddStage`) — one query, backing
  /// [TransitionPreconditionRepository.getNodeCounts]'s batch read.
  Future<List<TransitionPreconditionGraphData>> getAllGraphs() {
    return select(transitionPreconditionGraphsTable).get();
  }

  /// Returns the node row with id [id], or `null` if none exists.
  Future<TransitionPreconditionNodeData?> getNode(String id) {
    return (select(
      transitionPreconditionNodesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Returns every node row currently persisted. Callers filter down to
  /// one stage's tree by walking from that stage's graph root — node rows
  /// carry no stored `SddStage`/parent pointer of their own (see the
  /// table's own dartdoc).
  Future<List<TransitionPreconditionNodeData>> getAllNodes() {
    return select(transitionPreconditionNodesTable).get();
  }

  /// Inserts or replaces [companion] (matched by primary key).
  Future<void> upsertNode(TransitionPreconditionNodesTableCompanion companion) {
    return into(
      transitionPreconditionNodesTable,
    ).insertOnConflictUpdate(companion);
  }

  /// Deletes the node row with id [id].
  Future<void> deleteNode(String id) {
    return (delete(
      transitionPreconditionNodesTable,
    )..where((t) => t.id.equals(id))).go();
  }

  /// Sets [stage]'s graph row's `root_node_id` to [nodeId], inserting the
  /// row first if it doesn't exist yet (defensive — every
  /// precondition-bearing stage should already have a row from
  /// [seedDefaultsIfEmpty]).
  Future<void> setRoot(SddStage stage, String? nodeId) {
    return into(transitionPreconditionGraphsTable).insertOnConflictUpdate(
      TransitionPreconditionGraphsTableCompanion(
        sddStage: Value(stage.name),
        rootNodeId: Value(nodeId),
      ),
    );
  }

  /// Seeds a graph+node baseline for each of the 5 precondition-bearing
  /// `SddStage` values iff the graph table is currently empty — checked
  /// first so this is safe (idempotent, no duplication) to call
  /// unconditionally from both `onCreate` and every `onUpgrade` branch.
  /// Every seeded tree reproduces that stage's exact pre-existing
  /// hardcoded `TicketsCubit._sddStageAdvanceCheck` branch as data, per
  /// design.md §3. [SddStage.exploring]/[SddStage.verifying] share one
  /// single-node tree shape (seeded separately per stage, since each has
  /// its own graph row); `null`/[SddStage.archived] get no seeded graph.
  Future<void> seedDefaultsIfEmpty() async {
    final existing = await select(transitionPreconditionGraphsTable).get();
    if (existing.isNotEmpty) return;

    await transaction<void>(() async {
      // `exploring`/`verifying`: one node —
      // `mostRecentChatHasTerminalReply` → matched: allowed; unmatched:
      // blocked.
      for (final stage in [SddStage.exploring, SddStage.verifying]) {
        await _seedSingleNodeGraph(
          stage: stage,
          fieldId: 'mostRecentChatHasTerminalReply',
        );
      }

      // `proposed`: three nodes — `hasChildren` → unmatched: blocked;
      // matched → `storyNeedsDesignReview` → matched: allowed; unmatched
      // → `allChildrenComplete` → matched: allowed; unmatched: blocked.
      final allChildrenCompleteId = _uuid.v4();
      await into(transitionPreconditionNodesTable).insert(
        TransitionPreconditionNodesTableCompanion.insert(
          id: allChildrenCompleteId,
          fieldId: 'allChildrenComplete',
          matchedBranchKind: 'allowed',
          unmatchedBranchKind: 'blocked',
        ),
      );
      final storyNeedsDesignReviewId = _uuid.v4();
      await into(transitionPreconditionNodesTable).insert(
        TransitionPreconditionNodesTableCompanion.insert(
          id: storyNeedsDesignReviewId,
          fieldId: 'storyNeedsDesignReview',
          matchedBranchKind: 'allowed',
          unmatchedBranchKind: 'node',
          unmatchedBranchNodeId: Value(allChildrenCompleteId),
        ),
      );
      final hasChildrenId = _uuid.v4();
      await into(transitionPreconditionNodesTable).insert(
        TransitionPreconditionNodesTableCompanion.insert(
          id: hasChildrenId,
          fieldId: 'hasChildren',
          matchedBranchKind: 'node',
          matchedBranchNodeId: Value(storyNeedsDesignReviewId),
          unmatchedBranchKind: 'blocked',
        ),
      );
      await into(transitionPreconditionGraphsTable).insert(
        TransitionPreconditionGraphsTableCompanion.insert(
          sddStage: SddStage.proposed.name,
          rootNodeId: Value(hasChildrenId),
        ),
      );

      // `designBrief`: one node — `linkedDesignPageHasContent` → matched:
      // allowed; unmatched: blocked.
      await _seedSingleNodeGraph(
        stage: SddStage.designBrief,
        fieldId: 'linkedDesignPageHasContent',
      );

      // `designSync`: two nodes — `allTasksComplete` → unmatched: blocked;
      // matched → `designSyncApproved` → matched: allowed; unmatched:
      // blocked.
      final designSyncApprovedId = _uuid.v4();
      await into(transitionPreconditionNodesTable).insert(
        TransitionPreconditionNodesTableCompanion.insert(
          id: designSyncApprovedId,
          fieldId: 'designSyncApproved',
          matchedBranchKind: 'allowed',
          unmatchedBranchKind: 'blocked',
        ),
      );
      final allTasksCompleteId = _uuid.v4();
      await into(transitionPreconditionNodesTable).insert(
        TransitionPreconditionNodesTableCompanion.insert(
          id: allTasksCompleteId,
          fieldId: 'allTasksComplete',
          matchedBranchKind: 'node',
          matchedBranchNodeId: Value(designSyncApprovedId),
          unmatchedBranchKind: 'blocked',
        ),
      );
      await into(transitionPreconditionGraphsTable).insert(
        TransitionPreconditionGraphsTableCompanion.insert(
          sddStage: SddStage.designSync.name,
          rootNodeId: Value(allTasksCompleteId),
        ),
      );
    });
  }

  /// Inserts [stage]'s single-node baseline graph: one node checking
  /// [fieldId], matched → `allowed`, unmatched → `blocked`. Shared by
  /// [seedDefaultsIfEmpty]'s `exploring`/`verifying`/`designBrief`
  /// branches — the three stages whose baseline tree is exactly this
  /// one-node shape.
  Future<void> _seedSingleNodeGraph({
    required SddStage stage,
    required String fieldId,
  }) async {
    final nodeId = _uuid.v4();
    await into(transitionPreconditionNodesTable).insert(
      TransitionPreconditionNodesTableCompanion.insert(
        id: nodeId,
        fieldId: fieldId,
        matchedBranchKind: 'allowed',
        unmatchedBranchKind: 'blocked',
      ),
    );
    await into(transitionPreconditionGraphsTable).insert(
      TransitionPreconditionGraphsTableCompanion.insert(
        sddStage: stage.name,
        rootNodeId: Value(nodeId),
      ),
    );
  }
}
