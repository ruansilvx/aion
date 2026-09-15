// data/daos/transition_precondition_dao.dart — TransitionPreconditionDao Drift accessor (data layer).

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/database/app_database.dart';
import 'package:aion/features/tickets/data/models/transition_precondition_graphs_table.dart';
import 'package:aion/features/tickets/data/models/transition_precondition_nodes_table.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

part 'transition_precondition_dao.g.dart';

/// Drift accessor for [TransitionPreconditionGraphsTable]/
/// [TransitionPreconditionNodesTable]. See `AIO-1936` §2/§3. Works at the
/// raw-string `ticket_type` level (a real `TicketType.name` or
/// [anyTicketTypeSentinel]) rather than a nullable `TicketType?` — the
/// null-in/sentinel-out translation, and the "fall back to the shared graph"
/// resolution rule, are `DriftTransitionPreconditionRepository`'s job (this
/// Dao stays a dumb 1:1 mirror of the table, matching every other Dao in
/// this schema). Widened from a `SddStage`-only key to `(SddStage,
/// TicketType)` for `AIO-2903`.
@DriftAccessor(
  tables: [TransitionPreconditionGraphsTable, TransitionPreconditionNodesTable],
)
class TransitionPreconditionDao extends DatabaseAccessor<AppDatabase>
    with _$TransitionPreconditionDaoMixin {
  /// Creates a [TransitionPreconditionDao] bound to [db].
  TransitionPreconditionDao(super.db);

  static const _uuid = Uuid();

  /// Returns the graph row for [stage]/[ticketType] (a `TicketType.name` or
  /// [anyTicketTypeSentinel]), or `null` if it hasn't been seeded yet. Added
  /// the [ticketType] parameter for `AIO-2903`.
  Future<TransitionPreconditionGraphData?> getGraph(
    SddStage stage,
    String ticketType,
  ) {
    return (select(transitionPreconditionGraphsTable)..where(
          (t) =>
              t.sddStage.equals(stage.name) & t.ticketType.equals(ticketType),
        ))
        .getSingleOrNull();
  }

  /// Returns every graph row currently persisted (one per seeded/
  /// configured `(SddStage, TicketType)`) — one query, backing
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
  /// one graph's tree by walking from that graph's root — node rows carry
  /// no stored `SddStage`/`TicketType`/parent pointer of their own (see the
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

  /// Sets [stage]/[ticketType]'s own graph row's `root_node_id` to [nodeId],
  /// inserting the row first if it doesn't exist yet. Always writes exactly
  /// this `(stage, ticketType)` row — never a fallback row — so setting a
  /// type-specific override never mutates the shared graph other types
  /// still fall back to. Added the [ticketType] parameter for `AIO-2903`.
  Future<void> setRoot(SddStage stage, String ticketType, String? nodeId) {
    return into(transitionPreconditionGraphsTable).insertOnConflictUpdate(
      TransitionPreconditionGraphsTableCompanion(
        sddStage: Value(stage.name),
        ticketType: Value(ticketType),
        rootNodeId: Value(nodeId),
      ),
    );
  }

  /// Seeds a graph+node baseline for each of the 5 originally
  /// precondition-bearing `SddStage` values' *shared* graph
  /// (`ticket_type = 'any'`) iff the graph table is currently empty —
  /// checked first so this is safe (idempotent, no duplication) to call
  /// unconditionally from both `onCreate` and every `onUpgrade` branch.
  /// Every seeded tree reproduces that stage's exact pre-existing hardcoded
  /// `TicketsCubit._sddStageAdvanceCheck` branch as data, per design.md §3.
  /// [SddStage.exploring] gets a single-node tree shape; [SddStage.verifying]
  /// gets its own two-node tree (see below, per `AIO-1905` §3.1); `null`/
  /// [SddStage.archived] get no seeded graph.
  ///
  /// A fresh install's table is empty, so this also seeds
  /// [TicketType.bug]'s own `(proposed, bug)`/`(applying, bug)` override
  /// graphs in the same pass (via [_seedBugStageDefaults]) — an *existing*
  /// project upgrading through schema 22 instead reaches those two via
  /// [seedBugStageDefaultsIfMissing], since by the time this method runs on
  /// upgrade the table already holds the backfilled shared rows and this
  /// early-return skips it entirely.
  Future<void> seedDefaultsIfEmpty() async {
    final existing = await select(transitionPreconditionGraphsTable).get();
    if (existing.isNotEmpty) return;

    await transaction<void>(() async {
      // `exploring`: one node — `mostRecentChatHasTerminalReply` →
      // matched: allowed; unmatched: blocked.
      await _seedSingleNodeGraph(
        stage: SddStage.exploring,
        fieldId: 'mostRecentChatHasTerminalReply',
      );

      // `verifying`: two nodes — `mostRecentChatHasTerminalReply` →
      // unmatched: blocked; matched → `verifyGateApproved` → matched:
      // allowed; unmatched: blocked.
      final verifyGateApprovedId = _uuid.v4();
      await into(transitionPreconditionNodesTable).insert(
        TransitionPreconditionNodesTableCompanion.insert(
          id: verifyGateApprovedId,
          fieldId: 'verifyGateApproved',
          matchedBranchKind: 'allowed',
          unmatchedBranchKind: 'blocked',
        ),
      );
      final verifyingRootId = _uuid.v4();
      await into(transitionPreconditionNodesTable).insert(
        TransitionPreconditionNodesTableCompanion.insert(
          id: verifyingRootId,
          fieldId: 'mostRecentChatHasTerminalReply',
          matchedBranchKind: 'node',
          matchedBranchNodeId: Value(verifyGateApprovedId),
          unmatchedBranchKind: 'blocked',
        ),
      );
      await into(transitionPreconditionGraphsTable).insert(
        TransitionPreconditionGraphsTableCompanion.insert(
          sddStage: SddStage.verifying.name,
          ticketType: const Value(anyTicketTypeSentinel),
          rootNodeId: Value(verifyingRootId),
        ),
      );

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
          ticketType: const Value(anyTicketTypeSentinel),
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
          ticketType: const Value(anyTicketTypeSentinel),
          rootNodeId: Value(allTasksCompleteId),
        ),
      );

      await _seedBugStageDefaults();
    });
  }

  /// Inserts [stage]'s single-node *shared* (`ticket_type = 'any'`)
  /// baseline graph: one node checking [fieldId], matched → `allowed`,
  /// unmatched → `blocked`. Shared by [seedDefaultsIfEmpty]'s `exploring`/
  /// `designBrief` branches — the two stages whose baseline tree is exactly
  /// this one-node shape.
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
        ticketType: const Value(anyTicketTypeSentinel),
        rootNodeId: Value(nodeId),
      ),
    );
  }

  /// Inserts [TicketType.bug]'s own `(proposed, bug)`/`(applying, bug)`
  /// override graphs — each a single-node tree mirroring
  /// [_seedSingleNodeGraph]'s shape, checking `proposeGateApproved`/
  /// `codingExecutionConcluded` respectively. These two stages can't share
  /// Epic/Story's `proposed` tree (`hasChildren` is never true for a Bug,
  /// a leaf) or fall back to any shared `applying` tree (no type but Bug
  /// ever reaches that stage, so none was ever seeded) — see
  /// `TicketsCubit._sddStageAdvanceCheck`'s own dartdoc. Shared by
  /// [seedDefaultsIfEmpty] (fresh install) and
  /// [seedBugStageDefaultsIfMissing] (existing project upgrading through
  /// schema 22). Added for `AIO-2903`.
  Future<void> _seedBugStageDefaults() async {
    final proposeGateApprovedId = _uuid.v4();
    await into(transitionPreconditionNodesTable).insert(
      TransitionPreconditionNodesTableCompanion.insert(
        id: proposeGateApprovedId,
        fieldId: 'proposeGateApproved',
        matchedBranchKind: 'allowed',
        unmatchedBranchKind: 'blocked',
      ),
    );
    await into(transitionPreconditionGraphsTable).insert(
      TransitionPreconditionGraphsTableCompanion.insert(
        sddStage: SddStage.proposed.name,
        ticketType: Value(TicketType.bug.name),
        rootNodeId: Value(proposeGateApprovedId),
      ),
    );

    final codingExecutionConcludedId = _uuid.v4();
    await into(transitionPreconditionNodesTable).insert(
      TransitionPreconditionNodesTableCompanion.insert(
        id: codingExecutionConcludedId,
        fieldId: 'codingExecutionConcluded',
        matchedBranchKind: 'allowed',
        unmatchedBranchKind: 'blocked',
      ),
    );
    await into(transitionPreconditionGraphsTable).insert(
      TransitionPreconditionGraphsTableCompanion.insert(
        sddStage: SddStage.applying.name,
        ticketType: Value(TicketType.bug.name),
        rootNodeId: Value(codingExecutionConcludedId),
      ),
    );
  }

  /// One-time migration helper for schema version 22 (see
  /// `core/database/app_database.dart`'s `onUpgrade`) — seeds
  /// [TicketType.bug]'s `(proposed, bug)`/`(applying, bug)` override graphs
  /// for an *existing* project, whose graph table already holds the
  /// backfilled shared rows by the time this runs (so
  /// [seedDefaultsIfEmpty]'s own empty-table guard would otherwise skip
  /// them forever). Checks each of the two rows individually rather than
  /// gating on "any bug row exists" — idempotent and safe to call
  /// unconditionally, matching every other seed method's own precedent.
  /// Added for `AIO-2903`.
  Future<void> seedBugStageDefaultsIfMissing() async {
    final hasProposedBug =
        await getGraph(SddStage.proposed, TicketType.bug.name) != null;
    final hasApplyingBug =
        await getGraph(SddStage.applying, TicketType.bug.name) != null;
    if (hasProposedBug && hasApplyingBug) return;

    await transaction<void>(() async {
      if (!hasProposedBug) {
        final id = _uuid.v4();
        await into(transitionPreconditionNodesTable).insert(
          TransitionPreconditionNodesTableCompanion.insert(
            id: id,
            fieldId: 'proposeGateApproved',
            matchedBranchKind: 'allowed',
            unmatchedBranchKind: 'blocked',
          ),
        );
        await into(transitionPreconditionGraphsTable).insert(
          TransitionPreconditionGraphsTableCompanion.insert(
            sddStage: SddStage.proposed.name,
            ticketType: Value(TicketType.bug.name),
            rootNodeId: Value(id),
          ),
        );
      }
      if (!hasApplyingBug) {
        final id = _uuid.v4();
        await into(transitionPreconditionNodesTable).insert(
          TransitionPreconditionNodesTableCompanion.insert(
            id: id,
            fieldId: 'codingExecutionConcluded',
            matchedBranchKind: 'allowed',
            unmatchedBranchKind: 'blocked',
          ),
        );
        await into(transitionPreconditionGraphsTable).insert(
          TransitionPreconditionGraphsTableCompanion.insert(
            sddStage: SddStage.applying.name,
            ticketType: Value(TicketType.bug.name),
            rootNodeId: Value(id),
          ),
        );
      }
    });
  }

  /// One-time migration helper for schema version 20 (see
  /// `core/database/app_database.dart`'s `onUpgrade`) — upgrades an existing
  /// project's [SddStage.verifying] graph to the new two-node shape
  /// [seedDefaultsIfEmpty] now seeds directly for a fresh install, per
  /// `AIO-1905` §3.2.
  ///
  /// Only touches the graph if its root node still carries the exact
  /// original single-node default's fingerprint — `fieldId ==
  /// 'mostRecentChatHasTerminalReply'` with `matchedBranchKind ==
  /// 'allowed'` — meaning it was never customized via the Workflow
  /// config UI (and hasn't already been upgraded). Any other shape is
  /// left untouched. If [SddStage.verifying] has no graph row at all
  /// yet, this is a no-op — [seedDefaultsIfEmpty] (already called ahead
  /// of every `onUpgrade` branch, per `app_database.dart`) will have
  /// seeded the new shape directly in that case. Always operates on the
  /// *shared* graph ([anyTicketTypeSentinel]) — schema 20 predates
  /// `AIO-2903`'s per-type keying, and [SddStage.verifying] has never had a
  /// type-specific override.
  Future<void> upgradeVerifyingGraphIfDefault() async {
    final graph = await getGraph(SddStage.verifying, anyTicketTypeSentinel);
    final rootNodeId = graph?.rootNodeId;
    if (rootNodeId == null) return;

    final rootNode = await getNode(rootNodeId);
    if (rootNode == null) return;
    final isUntouchedDefault =
        rootNode.fieldId == 'mostRecentChatHasTerminalReply' &&
        rootNode.matchedBranchKind == 'allowed';
    if (!isUntouchedDefault) return;

    await transaction<void>(() async {
      final verifyGateApprovedId = _uuid.v4();
      await into(transitionPreconditionNodesTable).insert(
        TransitionPreconditionNodesTableCompanion.insert(
          id: verifyGateApprovedId,
          fieldId: 'verifyGateApproved',
          matchedBranchKind: 'allowed',
          unmatchedBranchKind: 'blocked',
        ),
      );
      await upsertNode(
        TransitionPreconditionNodesTableCompanion.insert(
          id: rootNodeId,
          fieldId: rootNode.fieldId,
          matchedBranchKind: 'node',
          matchedBranchNodeId: Value(verifyGateApprovedId),
          unmatchedBranchKind: rootNode.unmatchedBranchKind,
        ),
      );
    });
  }
}
