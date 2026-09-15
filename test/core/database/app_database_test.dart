// test/core/database/app_database_test.dart — AppDatabase schema-15 seeding tests.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/tickets/data/models/transition_precondition_graphs_table.dart'
    show anyTicketTypeSentinel;
import 'package:aion/features/tickets/domain/entities/default_workflow_statuses.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Dummy project — every test passes an explicit in-memory executor,
/// mirroring `ticket_dao_test.dart`'s own precedent.
final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

/// Covers schema-15's `WorkflowStatusesTable` seeding — see
/// `AppDatabase`'s class dartdoc and
/// `aion-arch/changes/configurable-ticket-workflow/design.md` §2.2.
///
/// Scoped to the fresh-`onCreate` install path only: this codebase has no
/// existing exported-schema/`SchemaVerifier` test infrastructure (no
/// prior `app_database_test.dart` establishes one either), and
/// hand-authoring a byte-accurate schema-14 `CREATE TABLE` DDL snapshot
/// just for this one migration step risks a test that fails for reasons
/// unrelated to this change's actual `onUpgrade` branch. The `from < 15`
/// branch itself is a two-line `createTable` + `seedDefaultsIfEmpty`
/// call, identical in shape and effect to every already-untested
/// `onUpgrade` branch in this file (versions 2 through 14 have no
/// migration tests of their own either) — this test instead exercises
/// [WorkflowStatusDao.seedDefaultsIfEmpty]'s idempotency directly (see
/// `workflow_status_dao_test.dart`), which is the actual logic both
/// `onCreate` and `onUpgrade` share.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh onCreate install seeds defaultWorkflowStatuses', () async {
    final database = AppDatabase(_testProject, NativeDatabase.memory());
    addTearDown(database.close);

    final rows = await database.workflowStatusDao.getAll();

    expect(rows, hasLength(defaultWorkflowStatuses.length));
    expect(
      rows.map((r) => r.name).toList(),
      defaultWorkflowStatuses.map((s) => s.name).toList(),
    );
    expect(rows.where((r) => r.role != null).map((r) => r.role).toSet(), {
      'executionTrigger',
      'reviewReady',
      'done',
    });
  });

  test('a freshly-created ticket\'s default status resolves against the '
      'seeded defaultWorkflowStatuses', () async {
    final database = AppDatabase(_testProject, NativeDatabase.memory());
    addTearDown(database.close);

    await database.ticketDao.insertTicket(
      TicketsTableCompanion.insert(
        id: 'ticket-1',
        ticketId: '',
        type: 'task',
        title: 'A fresh ticket',
        status: 'backlog',
        createdAt: 0,
        updatedAt: 0,
      ),
      'AIO',
    );

    final ticket = await database.ticketDao.getTicketById('ticket-1');
    final statuses = await database.workflowStatusDao.getAll();

    expect(ticket, isNotNull);
    expect(statuses.map((s) => s.name), contains(ticket!.status));
  });

  group(
    'schema 16 — WorkflowSkillAttachmentsTable/WorkflowPromptTemplatesTable',
    () {
      // This codebase has no exported-schema/SchemaVerifier infrastructure
      // (see the schema-15 coverage above), so rather than hand-author a
      // byte-accurate schema-15 DDL snapshot, this test opens a
      // `NativeDatabase.memory` whose `setup` callback stamps the raw
      // sqlite3 `user_version` pragma to `15` *before* drift's own
      // migration logic runs — drift then sees `from: 15 < schemaVersion:
      // 16` on open and genuinely invokes `AppDatabase.migration.onUpgrade`'s
      // real `from < 16` branch (not a re-implementation of it), same as
      // it would for an actual upgrading install. The rest of schema 15's
      // tables are never created by this test (nothing here needs them),
      // so only `workflowSkillAttachmentDao`/`workflowPromptTemplateDao`
      // are queried.
      test(
        'an install upgraded from schema 15 has both new tables, empty',
        () async {
          final database = AppDatabase(
            _testProject,
            NativeDatabase.memory(
              setup: (db) => db.execute('PRAGMA user_version = 15'),
            ),
          );
          addTearDown(database.close);

          final attachments = await database.workflowSkillAttachmentDao
              .getAll();
          final templates = await database.workflowPromptTemplateDao.getAll();

          expect(attachments, isEmpty);
          expect(templates, isEmpty);
        },
      );

      // Same scoping rationale as this file's schema-15 coverage above: the
      // `from < 16` branch is a two-line `createTable` pair with no seed/
      // backfill logic to get wrong (see `app_database.dart`'s version-16
      // dartdoc). This test confirms the fresh-`onCreate` install path
      // (which shares `createAll()`, the same table set `onUpgrade`
      // incrementally builds towards) ends with both new tables present
      // and empty too.
      test('a fresh onCreate install has both new tables, empty', () async {
        final database = AppDatabase(_testProject, NativeDatabase.memory());
        addTearDown(database.close);

        final attachments = await database.workflowSkillAttachmentDao.getAll();
        final templates = await database.workflowPromptTemplateDao.getAll();

        expect(attachments, isEmpty);
        expect(templates, isEmpty);
      });
    },
  );

  group(
    'schema 18 — AutomationDecisionGraphsTable/AutomationDecisionNodesTable',
    () {
      // Same `PRAGMA user_version` technique as the schema-16 coverage
      // above — genuinely exercises `AppDatabase.migration.onUpgrade`'s
      // real `from < 18` branch. See
      // `aion-arch/changes/automation-decision-graphs/design.md` §2.
      test('an install upgraded from schema 17 seeds every AutomationContext, '
          'including the two baseline nodes reproducing the former hardcoded '
          'checks', () async {
        final database = AppDatabase(
          _testProject,
          NativeDatabase.memory(
            setup: (db) => db.execute('PRAGMA user_version = 17'),
          ),
        );
        addTearDown(database.close);

        final retryGraph = await database.automationDecisionDao.getGraph(
          AutomationContext.codingExecutionRetry,
        );
        expect(retryGraph, isNotNull);
        expect(retryGraph!.rootNodeId, isNotNull);

        final sddStageGraph = await database.automationDecisionDao.getGraph(
          AutomationContext.sddStage,
        );
        expect(sddStageGraph, isNotNull);
        expect(sddStageGraph!.rootNodeId, isNull);
      });

      test(
        'a fresh onCreate install seeds every AutomationContext the same way',
        () async {
          final database = AppDatabase(_testProject, NativeDatabase.memory());
          addTearDown(database.close);

          final executionGraph = await database.automationDecisionDao.getGraph(
            AutomationContext.codingExecution,
          );
          expect(executionGraph, isNotNull);
          expect(executionGraph!.rootNodeId, isNotNull);
          final node = await database.automationDecisionDao.getNode(
            executionGraph.rootNodeId!,
          );
          expect(node!.conditionId, 'sessionOverageDetected');
        },
      );
    },
  );

  group('schema 20 — verifying graph upgraded to the verifyGateApproved '
      'two-node shape', () {
    // Same `PRAGMA user_version` technique as the schema-16/18 coverage
    // above — genuinely exercises `AppDatabase.migration.onUpgrade`'s real
    // `from < 20` branch (calling
    // `TransitionPreconditionDao.upgradeVerifyingGraphIfDefault`), chained
    // after the real `from < 19` branch (`PRAGMA user_version = 18`, one
    // less than 19, so that branch's own `createTable` +
    // `seedDefaultsIfEmpty` genuinely run first — an in-memory database
    // has no pre-existing tables, so a `from = 19` starting point would
    // skip table creation entirely). Since `seedDefaultsIfEmpty` already
    // seeds the *new* two-node shape directly for any table it creates
    // fresh, `upgradeVerifyingGraphIfDefault`'s own fingerprint check
    // correctly no-ops here — this test only confirms the end state
    // (every upgraded install ends up on the two-node shape, whichever
    // path got it there), not the fingerprint-matching logic itself.
    // `upgradeVerifyingGraphIfDefault`'s actual upgrade-in-place behavior
    // (starting from real single-node data) is covered directly against
    // the DAO in `drift_transition_precondition_repository_test.dart`'s
    // own `upgradeVerifyingGraphIfDefault` group, per
    // `aion-arch/changes/sdd-verify-quality-gate/design.md` §3.2.
    test(
      'an install upgraded from schema 18 ends up with the two-node '
      'verifying shape',
      () async {
        final database = AppDatabase(
          _testProject,
          NativeDatabase.memory(
            setup: (db) => db.execute('PRAGMA user_version = 18'),
          ),
        );
        addTearDown(database.close);

        final nodes = await database.transitionPreconditionDao.getAllNodes();
        final verifyingGraph = await database.transitionPreconditionDao
            .getGraph(SddStage.verifying, anyTicketTypeSentinel);
        final verifyingNodes = nodes
            .where(
              (n) =>
                  n.id == verifyingGraph?.rootNodeId ||
                  n.fieldId == 'verifyGateApproved',
            )
            .toList();

        expect(verifyingGraph?.rootNodeId, isNotNull);
        expect(verifyingNodes, hasLength(2));
        expect(
          verifyingNodes.map((n) => n.fieldId),
          containsAll(['mostRecentChatHasTerminalReply', 'verifyGateApproved']),
        );
      },
    );
  });

  group(
    'schema 22 — transition_precondition_graphs keyed by (SddStage, '
    'TicketType)',
    () {
      // Same file-based "strip down to an earlier shape, then reopen"
      // technique as `drift_ticket_repository_test.dart`'s own AIO-2888
      // migration test (see `feedback_no_blanket_dart_format.md`-adjacent
      // project convention: a real upgrade test, not just a fresh-seed
      // one, for a migration that rewrites existing rows) — a genuine
      // `NativeDatabase(File(...))`, not an in-memory `PRAGMA` stamp,
      // since this migration's own correctness is about *preserving* an
      // existing project's customized row through a primary-key rebuild,
      // not just producing the right end shape from nothing. Added for
      // `AIO-2903`.
      test(
        'a customized pre-existing proposed graph survives the rebuild as '
        "the shared ('any') graph, and Bug's own proposed/applying "
        'overrides are seeded alongside it',
        () async {
          final tempDir = Directory.systemTemp.createTempSync(
            'aion_migration_v22_test',
          );
          final dbFile = File('${tempDir.path}/test.sqlite');
          addTearDown(() => tempDir.deleteSync(recursive: true));

          final v21Db = AppDatabase(_testProject, NativeDatabase(dbFile));
          // Force past onCreate's already-current (post-AIO-2903) table
          // shape: drop it and recreate the old SddStage-only-keyed shape
          // by hand, then insert a customized row a project might really
          // have configured (a single-node "always blocked" proposed
          // graph, distinguishable from the seeded default's multi-node
          // shape).
          await v21Db.customStatement(
            'DROP TABLE transition_precondition_graphs;',
          );
          await v21Db.customStatement('''
            CREATE TABLE transition_precondition_graphs (
              sdd_stage TEXT NOT NULL PRIMARY KEY,
              root_node_id TEXT
            );
          ''');
          const customNodeId = 'custom-always-blocked-node';
          await v21Db.transitionPreconditionDao.upsertNode(
            TransitionPreconditionNodesTableCompanion.insert(
              id: customNodeId,
              fieldId: 'hasChildren',
              matchedBranchKind: 'blocked',
              unmatchedBranchKind: 'blocked',
            ),
          );
          await v21Db.customStatement('''
            INSERT INTO transition_precondition_graphs (sdd_stage, root_node_id)
            VALUES ('proposed', '$customNodeId');
          ''');

          await v21Db.customStatement('PRAGMA user_version = 21;');
          await v21Db.close();

          // Reopen against the same file at the current schemaVersion
          // (22). Drift reads user_version=21, sees schemaVersion=22, and
          // runs the real `from < 22` onUpgrade step.
          final v22Db = AppDatabase(_testProject, NativeDatabase(dbFile));
          addTearDown(v22Db.close);

          final sharedProposed = await v22Db.transitionPreconditionDao
              .getGraph(SddStage.proposed, anyTicketTypeSentinel);
          expect(sharedProposed?.rootNodeId, customNodeId);

          final bugProposed = await v22Db.transitionPreconditionDao.getGraph(
            SddStage.proposed,
            TicketType.bug.name,
          );
          expect(bugProposed?.rootNodeId, isNotNull);
          final bugProposedNode = await v22Db.transitionPreconditionDao
              .getNode(bugProposed!.rootNodeId!);
          expect(bugProposedNode?.fieldId, 'proposeGateApproved');

          final bugApplying = await v22Db.transitionPreconditionDao.getGraph(
            SddStage.applying,
            TicketType.bug.name,
          );
          expect(bugApplying?.rootNodeId, isNotNull);
          final bugApplyingNode = await v22Db.transitionPreconditionDao
              .getNode(bugApplying!.rootNodeId!);
          expect(bugApplyingNode?.fieldId, 'codingExecutionConcluded');
        },
      );

      test(
        'a fresh onCreate install seeds proposed/applying overrides for Bug '
        'alongside every shared graph',
        () async {
          final database = AppDatabase(_testProject, NativeDatabase.memory());
          addTearDown(database.close);

          final bugProposed = await database.transitionPreconditionDao
              .getGraph(SddStage.proposed, TicketType.bug.name);
          final bugApplying = await database.transitionPreconditionDao
              .getGraph(SddStage.applying, TicketType.bug.name);
          final sharedApplying = await database.transitionPreconditionDao
              .getGraph(SddStage.applying, anyTicketTypeSentinel);

          expect(bugProposed?.rootNodeId, isNotNull);
          expect(bugApplying?.rootNodeId, isNotNull);
          // `applying` has never had a shared/type-agnostic graph — only
          // Bug reaches that stage.
          expect(sharedApplying, isNull);
        },
      );
    },
  );
}
