// core/database/app_database.dart — AppDatabase Drift database (core layer).

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/automation/data/automation_decision_dao.dart';
import 'package:aion/core/automation/data/automation_decision_graphs_table.dart';
import 'package:aion/core/automation/data/automation_decision_nodes_table.dart';
import 'package:aion/core/markdown/wikilink_extractor.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/tickets/data/daos/comment_dao.dart';
import 'package:aion/features/tickets/data/daos/decision_log_dao.dart';
import 'package:aion/features/tickets/data/daos/execution_queue_dao.dart';
import 'package:aion/features/tickets/data/daos/notification_dao.dart';
import 'package:aion/features/tickets/data/daos/page_wikilink_dao.dart';
import 'package:aion/features/tickets/data/daos/ticket_dao.dart';
import 'package:aion/features/tickets/data/daos/ticket_link_dao.dart';
import 'package:aion/features/tickets/data/daos/workflow_prompt_template_dao.dart';
import 'package:aion/features/tickets/data/daos/workflow_skill_attachment_dao.dart';
import 'package:aion/features/tickets/data/daos/workflow_status_dao.dart';
import 'package:aion/features/tickets/data/models/decision_log_table.dart';
import 'package:aion/features/tickets/data/models/execution_queue_table.dart';
import 'package:aion/features/tickets/data/models/notification_table.dart';
import 'package:aion/features/tickets/data/models/page_wikilink_model.dart';
import 'package:aion/features/tickets/data/models/ticket_comment_model.dart';
import 'package:aion/features/tickets/data/models/ticket_link_model.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';
import 'package:aion/features/tickets/data/models/workflow_prompt_template_table.dart';
import 'package:aion/features/tickets/data/daos/transition_precondition_dao.dart';
import 'package:aion/features/tickets/data/models/transition_precondition_graphs_table.dart';
import 'package:aion/features/tickets/data/models/transition_precondition_nodes_table.dart';
import 'package:aion/features/tickets/data/models/workflow_skill_attachment_table.dart';
import 'package:aion/features/tickets/data/models/workflow_status_table.dart';
import 'package:aion/features/tickets/domain/utils/ticket_rollup_calculator.dart';

part 'app_database.g.dart';

/// Opens the platform-appropriate [QueryExecutor], addressed to [project]'s
/// own isolated storage rather than one fixed global location — see `AIO-1174`
/// §7.
///
/// drift_flutter's `driftDatabase` picks the right implementation per
/// platform via conditional imports: `NativeDatabase` (dart:io) on
/// desktop/mobile, and `WasmDatabase` (drift/wasm) on web.
///
/// - Desktop/mobile: [native]'s `databasePath` resolves to
///   `<rootPath>/.aion/data/app.db` when [Project.rootPath] is set
///   (desktop), or `<app documents dir>/<storageKey>/app.db` otherwise
///   (mobile, which has no user-chosen directory).
/// - Web: the WASM database name becomes `aion_<storageKey>`, so each
///   project gets an isolated OPFS/IndexedDB namespace within the same
///   browser origin.
QueryExecutor _openConnection(Project project) {
  return driftDatabase(
    name: 'aion_${project.storageKey}',
    native: DriftNativeOptions(
      databasePath: () => _resolveNativeDatabasePath(project),
    ),
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('worker.dart.js'),
    ),
  );
}

/// Resolves the on-disk SQLite file path for [project] on desktop/mobile,
/// creating its containing directory if needed (`NativeDatabase` does not
/// create intermediate directories itself).
Future<String> _resolveNativeDatabasePath(Project project) async {
  final Directory dir;
  final rootPath = project.rootPath;
  if (rootPath != null) {
    dir = Directory(
      '$rootPath${Platform.pathSeparator}.aion${Platform.pathSeparator}data',
    );
  } else {
    final documentsDir = await getApplicationDocumentsDirectory();
    dir = Directory(
      '${documentsDir.path}${Platform.pathSeparator}${project.storageKey}',
    );
  }
  await dir.create(recursive: true);
  return '${dir.path}${Platform.pathSeparator}app.db';
}

/// Aion's per-project local SQLite database. One instance exists per currently
/// active [Project] — see `AIO-1174` §6, §7 — never one fixed global instance;
/// the project registry itself lives in the separate, non-project-scoped
/// [RegistryDatabase]. Schema version 3, seeding [TicketIdSequenceTable] with
/// a single `(id: 1, seq: 0)` row on creation. Version 2 adds ticket
/// search/filter infrastructure (see [_createSearchInfrastructure]): indexes
/// on `status`/`type`/`priority` and an external-content FTS5 index over
/// `title`/`description`. Version 3 adds [TicketsTable.deletedAt] for the
/// trash/soft-delete model — see
/// `TicketRepository.trashTicket`/`restoreTicket`. Version 5 adds
/// `TicketsTable.complexity`/`TicketsTable.sddStage` — see
/// `TicketRepository.updateTicketSddStage`. Version 6 adds
/// `TicketsTable.severity`/`stepsToReproduce`/`expectedBehavior`/
/// `actualBehavior` — see `TicketType.bug`. Version 7 adds
/// `TicketCommentsTable.inputTokens`/`outputTokens` — see
/// `TicketsCubit._executionChatOverCap`. Version 8 adds
/// `TicketsTable.suggestedType`/`inboxPurpose` — see `AIO-1300` §1.4. Version
/// 9 adds `TicketsTable.estimateRollup`/`timeSpentRollup` and backfills them
/// once for every existing row (see [_backfillRollups]) — see `AIO-873` §1.4.
/// Version 10 adds `TicketsTable.complexitySource`/`estimateSource` and
/// backfills both to `'manual'` for every pre-existing row whose
/// `complexity`/`estimate` is already set — see `AIO-75` §3.4. Version 11 adds
/// no columns — `TicketType.signal` was split into
/// `idea`/`knownGap`/`openQuestion`, so every pre-existing `type = 'signal'`
/// row is blanket-reclassified to `'idea'` (the type that keeps `signal`'s
/// exact prior behavior; not a heuristic guess at gap-vs-question-vs-idea) so
/// the app never crashes deserializing pre-existing data — see `AIO-934` §2.1.
/// Version 12 adds [PageWikilinksTable] and backfills it once from every
/// existing `page` ticket's `description` (see [_backfillWikilinks]) — see
/// `AIO-963`. Version 13 adds [ExecutionQueueTable], with no backfill — a
/// pre-13 database has no persisted queue state to migrate;
/// `TicketsCubit.restoreExecutionQueue` simply finds nothing to resume on its
/// first post-upgrade launch. See `AIO-1400` §7. Version 14 adds
/// `TicketsTable.predictedExecutionTokensLow`/`predictedExecutionTokensHigh`,
/// with no backfill — a pre-14 database has no recorded predictions to
/// migrate; `TicketTokenPredictor` simply produces its first estimate for each
/// not-yet-executed `task`/`bug` ticket the next time it's created or updated.
/// See `AIO-2455` §1.2. Version 15 adds [WorkflowStatusesTable], seeded with
/// `defaultWorkflowStatuses` for both a fresh install and a backfill of every
/// pre-existing project (via [WorkflowStatusDao.seedDefaultsIfEmpty]),
/// reproducing the exact hardcoded status set/roles a pre-15 database already
/// behaved with. No `tickets.status` column change — it was already a raw
/// `TextColumn`. See `AIO-549` §2.2. Version 16 adds
/// [WorkflowSkillAttachmentsTable] and [WorkflowPromptTemplatesTable], with no
/// seed/backfill — an empty attachment/template table is the correct starting
/// state for both a fresh install and a pre-existing project, since nothing
/// fires automatically today outside the already-unconditional SDD-stage flow.
/// See `AIO-2650` §2.3. Version 17 adds [NotificationsTable], with no backfill
/// — a pre-17 database has no notification history to migrate; the center
/// simply starts empty on first launch after upgrade. See `AIO-1586` §3.
/// Version 18 adds [AutomationDecisionGraphsTable]/
/// [AutomationDecisionNodesTable], seeded with a baseline
/// `DecisionGraph`/`DecisionNode` row per `AutomationContext` (via
/// [AutomationDecisionDao.seedDefaultsIfEmpty]) for both a fresh install and a
/// backfill of every pre-existing project — reproducing the exact hardcoded
/// `_effectiveCodingExecutionRetryConfidence`/
/// `_effectiveCodingExecutionConfidence` ad hoc checks a pre-18 database
/// already behaved with. See `AIO-181` §2. Version 19 adds
/// [TransitionPreconditionGraphsTable]/ [TransitionPreconditionNodesTable],
/// seeded with a baseline transition-precondition graph for each of the 5
/// `SddStage` values that has a real precondition today (via
/// [TransitionPreconditionDao.seedDefaultsIfEmpty]) for both a fresh install
/// and a backfill of every pre-existing project — reproducing the exact
/// hardcoded `TicketsCubit._sddStageAdvanceCheck` branches a pre-19 database
/// already behaved with. See `AIO-1936` §2/§3. Version 20 upgrades an
/// existing project's `verifying` transition-precondition graph to the new
/// two-node `verifyGateApproved` shape, with no schema/table change of its
/// own. See `AIO-1905` §3.2. Version 21 widens the FTS5 `tickets_fts` index
/// (see [_createSearchInfrastructure]) to also cover `ticket_id`, so
/// searching e.g. `AIO-2835` finds that ticket even though its id never
/// appears in its own title/description — `tickets_fts` previously indexed
/// only `title`/`description`. Existing installs get the widened index via
/// [_widenFtsIndexWithTicketId] (drop + recreate, since FTS5's `ALTER TABLE
/// ADD COLUMN` support isn't guaranteed across every bundled `sqlite3`
/// version this app ships against); a fresh install's single
/// [_createSearchInfrastructure] call already creates the 3-column shape
/// directly. See `AIO-2888`. Version 22 widens
/// `transition_precondition_graphs` from a `SddStage`-only primary key to
/// `(SddStage, TicketType)`, with no other changes. Version 23 adds
/// [DecisionLogsTable], with no backfill — a pre-23 database has no decision
/// audit history to migrate. See `AIO-2947` §1.
@DriftDatabase(
  tables: [
    TicketsTable,
    TicketIdSequenceTable,
    TicketLinksTable,
    TicketCommentsTable,
    PageWikilinksTable,
    ExecutionQueueTable,
    WorkflowStatusesTable,
    WorkflowSkillAttachmentsTable,
    WorkflowPromptTemplatesTable,
    NotificationsTable,
    AutomationDecisionGraphsTable,
    AutomationDecisionNodesTable,
    TransitionPreconditionGraphsTable,
    TransitionPreconditionNodesTable,
    DecisionLogsTable,
  ],
  daos: [
    TicketDao,
    TicketLinkDao,
    CommentDao,
    PageWikilinkDao,
    ExecutionQueueDao,
    WorkflowStatusDao,
    WorkflowSkillAttachmentDao,
    WorkflowPromptTemplateDao,
    NotificationDao,
    AutomationDecisionDao,
    TransitionPreconditionDao,
    DecisionLogDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Creates an [AppDatabase] for [project]. Pass [executor] to use a
  /// custom connection (e.g. `NativeDatabase.memory()` in tests), in which
  /// case [project] is accepted but not consulted; otherwise opens the
  /// normal platform-appropriate, project-addressed connection via
  /// [_openConnection].
  AppDatabase(Project project, [QueryExecutor? executor])
    : super(executor ?? _openConnection(project));

  @override
  int get schemaVersion => 23;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await into(ticketIdSequenceTable).insert(
        const TicketIdSequenceTableCompanion(id: Value(1), seq: Value(0)),
      );
      await _createSearchInfrastructure(m);
      await workflowStatusDao.seedDefaultsIfEmpty();
      await automationDecisionDao.seedDefaultsIfEmpty();
      await transitionPreconditionDao.seedDefaultsIfEmpty();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await _createSearchInfrastructure(m);
      }
      if (from < 3) {
        await m.addColumn(ticketsTable, ticketsTable.deletedAt);
      }
      if (from < 4) {
        await m.addColumn(ticketsTable, ticketsTable.syncStatus);
      }
      if (from < 5) {
        await m.addColumn(ticketsTable, ticketsTable.complexity);
        await m.addColumn(ticketsTable, ticketsTable.sddStage);
      }
      if (from < 6) {
        await m.addColumn(ticketsTable, ticketsTable.severity);
        await m.addColumn(ticketsTable, ticketsTable.stepsToReproduce);
        await m.addColumn(ticketsTable, ticketsTable.expectedBehavior);
        await m.addColumn(ticketsTable, ticketsTable.actualBehavior);
      }
      if (from < 7) {
        await m.addColumn(ticketCommentsTable, ticketCommentsTable.inputTokens);
        await m.addColumn(
          ticketCommentsTable,
          ticketCommentsTable.outputTokens,
        );
      }
      if (from < 8) {
        await m.addColumn(ticketsTable, ticketsTable.suggestedType);
        await m.addColumn(ticketsTable, ticketsTable.inboxPurpose);
      }
      if (from < 9) {
        await m.addColumn(ticketsTable, ticketsTable.estimateRollup);
        await m.addColumn(ticketsTable, ticketsTable.timeSpentRollup);
        await _backfillRollups(m);
      }
      if (from < 10) {
        await m.addColumn(ticketsTable, ticketsTable.complexitySource);
        await m.addColumn(ticketsTable, ticketsTable.estimateSource);
        // Every pre-existing sized ticket was sized by hand — there was no
        // other way before this change — so backfill both sources to
        // 'manual' wherever their field is already set. Mirrors
        // `_backfillRollups`'s raw-SQL-inside-the-migration precedent.
        await m.database.customStatement(
          "UPDATE tickets SET complexity_source = 'manual' "
          'WHERE complexity IS NOT NULL AND complexity_source IS NULL',
        );
        await m.database.customStatement(
          "UPDATE tickets SET estimate_source = 'manual' "
          'WHERE estimate IS NOT NULL AND estimate_source IS NULL',
        );
      }
      if (from < 11) {
        // `TicketType.signal` was retired in favor of `idea`/`knownGap`/
        // `openQuestion` — a blanket default landing spot, not a
        // heuristic guess at which of the three each row "should" become.
        // The user can move any of these to `knownGap`/`openQuestion` by
        // hand afterward via `TicketsCubit.reclassifyIdea`.
        await m.database.customStatement(
          "UPDATE tickets SET type = 'idea' WHERE type = 'signal'",
        );
      }
      if (from < 12) {
        await m.createTable(pageWikilinksTable);
        await _backfillWikilinks(m);
      }
      if (from < 13) {
        await m.createTable(executionQueueTable);
      }
      if (from < 14) {
        await m.addColumn(
          ticketsTable,
          ticketsTable.predictedExecutionTokensLow,
        );
        await m.addColumn(
          ticketsTable,
          ticketsTable.predictedExecutionTokensHigh,
        );
      }
      if (from < 15) {
        await m.createTable(workflowStatusesTable);
        await workflowStatusDao.seedDefaultsIfEmpty();
      }
      if (from < 16) {
        await m.createTable(workflowSkillAttachmentsTable);
        await m.createTable(workflowPromptTemplatesTable);
      }
      if (from < 17) {
        await m.createTable(notificationsTable);
      }
      if (from < 18) {
        await m.createTable(automationDecisionGraphsTable);
        await m.createTable(automationDecisionNodesTable);
        await automationDecisionDao.seedDefaultsIfEmpty();
      }
      if (from < 19) {
        await m.createTable(transitionPreconditionGraphsTable);
        await m.createTable(transitionPreconditionNodesTable);
        await transitionPreconditionDao.seedDefaultsIfEmpty();
      }
      if (from < 20) {
        // Upgrades an existing project's `verifying` transition-precondition
        // graph to the new two-node `verifyGateApproved` shape
        // `seedDefaultsIfEmpty` now seeds directly for a fresh install — see
        // `AIO-1905` §3.2.
        await transitionPreconditionDao.upgradeVerifyingGraphIfDefault();
      }
      if (from < 21) {
        await _widenFtsIndexWithTicketId(m);
      }
      if (from < 22) {
        await _widenTransitionPreconditionGraphsWithTicketType(m);
        await transitionPreconditionDao.seedBugStageDefaultsIfMissing();
      }
      if (from < 23) {
        await m.createTable(decisionLogsTable);
      }
    },
  );

  /// Adds the status/type/priority indexes and the FTS5 search index (plus
  /// its sync triggers) for ticket search/filtering. Shared by [onCreate]
  /// (fresh install) and [onUpgrade] from schema 1 (existing local
  /// databases) so both end up with identical search infrastructure.
  ///
  /// `tickets` is a normal (non-`WITHOUT ROWID`) table, so it has SQLite's
  /// implicit integer `rowid` even though its declared primary key (`id`)
  /// is a UUID `TEXT` column — that `rowid` is what ties `tickets_fts` back
  /// to `tickets` via `content_rowid='rowid'`.
  ///
  /// Indexes `ticket_id` alongside `title`/`description` (since schema 21,
  /// `AIO-2888`) — searching `AIO-2835` needs to find that ticket even
  /// though its id never appears in its own title/description text.
  /// [TicketDao._buildFtsQuery] already quotes every query token (defending
  /// against `-`/`(`/`"`/`:` being parsed as FTS5 query-syntax operators);
  /// the *indexed* text goes through the same `unicode61` tokenizer at
  /// write time, so `AIO-2835` becomes the token pair `["aio", "2835"]` on
  /// both sides and a quoted-phrase-with-prefix query matches it exactly —
  /// the earlier `-`-as-NOT-operator theory this ticket started with turned
  /// out not to be the actual bug; `ticket_id` was simply never indexed at
  /// all. On [_widenFtsIndexWithTicketId]'s upgrade path, this method is
  /// called a second time *after* the old 2-column index and its triggers
  /// are dropped, so every `IF NOT EXISTS`/backfill statement below runs for
  /// real rather than silently no-op'ing against still-existing objects.
  Future<void> _createSearchInfrastructure(Migrator m) async {
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tickets_type ON tickets(type);',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tickets_priority ON tickets(priority);',
    );

    await m.database.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS tickets_fts USING fts5(
        title, description, ticket_id, content='tickets', content_rowid='rowid'
      );
    ''');

    // Backfill: index whatever rows already exist. A no-op on a fresh
    // onCreate (tickets is empty at this point), essential on onUpgrade
    // (existing local ticket data must become searchable retroactively —
    // the triggers below only cover writes from this point forward).
    await m.database.customStatement('''
      INSERT INTO tickets_fts(rowid, title, description, ticket_id)
      SELECT rowid, title, description, ticket_id FROM tickets;
    ''');

    await m.database.customStatement('''
      CREATE TRIGGER IF NOT EXISTS tickets_fts_ai AFTER INSERT ON tickets BEGIN
        INSERT INTO tickets_fts(rowid, title, description, ticket_id)
        VALUES (new.rowid, new.title, new.description, new.ticket_id);
      END;
    ''');
    await m.database.customStatement('''
      CREATE TRIGGER IF NOT EXISTS tickets_fts_ad AFTER DELETE ON tickets BEGIN
        INSERT INTO tickets_fts(tickets_fts, rowid, title, description, ticket_id)
        VALUES ('delete', old.rowid, old.title, old.description, old.ticket_id);
      END;
    ''');
    await m.database.customStatement('''
      CREATE TRIGGER IF NOT EXISTS tickets_fts_au AFTER UPDATE ON tickets BEGIN
        INSERT INTO tickets_fts(tickets_fts, rowid, title, description, ticket_id)
        VALUES ('delete', old.rowid, old.title, old.description, old.ticket_id);
        INSERT INTO tickets_fts(rowid, title, description, ticket_id)
        VALUES (new.rowid, new.title, new.description, new.ticket_id);
      END;
    ''');
  }

  /// Upgrades an existing (pre-21) project's `tickets_fts` index from
  /// `(title, description)` to `(title, description, ticket_id)` — see
  /// [_createSearchInfrastructure]'s own dartdoc for why. FTS5's `ALTER
  /// TABLE ... ADD COLUMN` support isn't guaranteed across every bundled
  /// `sqlite3` version this app ships against, so this drops the index and
  /// its 3 sync triggers outright and calls [_createSearchInfrastructure]
  /// again, which recreates all of it (indexes, virtual table, backfill,
  /// triggers) from scratch with the new 3-column shape — safe because
  /// `tickets_fts` is an *external-content* FTS5 table (`content='tickets'`):
  /// it stores no text of its own, only the index, so dropping and
  /// rebuilding it is a pure reindex, never data loss. `idx_tickets_*`/the 3
  /// triggers all use `IF NOT EXISTS`/are dropped-then-recreated, so this is
  /// idempotent if ever re-run.
  ///
  /// No-ops if `tickets` itself doesn't exist yet — every real upgrade has
  /// it (it's the very first table this app ever created), but several of
  /// this file's own pre-existing tests simulate "an install upgraded from
  /// schema N" via a bare `PRAGMA user_version = N` on an otherwise-empty
  /// in-memory database (see `app_database_test.dart`'s schema-16/18/20
  /// groups), deliberately never creating `tickets` at all since their own
  /// `from < N` block under test doesn't need it. Since `from < 21` is true
  /// for any of those (`N` < 21), this method would otherwise always run
  /// for them too and fail on `no such table: tickets` — a test-harness
  /// artifact, not a real-world case this needs to actually recover from.
  /// Added for `AIO-2888`.
  Future<void> _widenFtsIndexWithTicketId(Migrator m) async {
    final ticketsTableExists = await m.database
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'tickets'",
        )
        .getSingleOrNull();
    if (ticketsTableExists == null) return;

    await m.database.customStatement(
      'DROP TRIGGER IF EXISTS tickets_fts_ai;',
    );
    await m.database.customStatement(
      'DROP TRIGGER IF EXISTS tickets_fts_ad;',
    );
    await m.database.customStatement(
      'DROP TRIGGER IF EXISTS tickets_fts_au;',
    );
    await m.database.customStatement('DROP TABLE IF EXISTS tickets_fts;');
    await _createSearchInfrastructure(m);
  }

  /// Widens `transition_precondition_graphs` from a `SddStage`-only primary
  /// key to `(SddStage, TicketType)`, per `AIO-2903` — see
  /// `TransitionPreconditionGraphsTable`'s own dartdoc for why the new
  /// `ticket_type` column is a `NOT NULL` sentinel (`'any'`), not a nullable
  /// one. SQLite has no `ALTER TABLE` support for changing a primary key, so
  /// this does the standard rebuild: create the new-shape table under a
  /// temporary name, copy every existing row across with `ticket_type`
  /// backfilled to the shared-graph sentinel (preserving every project's
  /// existing configuration exactly — a row that was `SddStage.proposed`'s
  /// one shared tree stays exactly that tree, just addressable as
  /// `(proposed, 'any')` now), drop the old table, then rename the new one
  /// into its place. Unlike [_widenFtsIndexWithTicketId]'s FTS5
  /// external-content index (which stores no data of its own, so dropping
  /// and rebuilding it is a pure reindex), this table's rows *are* the
  /// data — hence copy-then-drop, never drop-then-recreate-empty.
  ///
  /// No-ops if `transition_precondition_graphs` doesn't exist yet — mirrors
  /// [_widenFtsIndexWithTicketId]'s own `tickets`-existence guard and for
  /// the same reason: several of this file's own tests simulate "an install
  /// upgraded from schema N" via a bare `PRAGMA user_version = N` on an
  /// otherwise-empty in-memory database, and a low enough `N` reaches this
  /// `from < 22` branch without the `from < 19` branch (which creates this
  /// table) ever having run in that same simulated upgrade.
  ///
  /// Also no-ops if the table *already* has a `ticket_type` column — not
  /// just a defensive nicety. `onUpgrade`'s `from < 19` branch calls
  /// `m.createTable(transitionPreconditionGraphsTable)`, which always
  /// builds *today's* table shape (this repo has no historical/versioned
  /// Table classes) — so any real upgrade starting below schema 19 already
  /// gets the post-`AIO-2903` composite-key table straight from that
  /// `createTable` call, before this `from < 22` branch even runs. Without
  /// this check, the rebuild below would still fire, re-inserting every
  /// already-correctly-`ticket_type`-tagged row (including
  /// `seedDefaultsIfEmpty`'s own fresh Bug `proposed`/`applying` rows) back
  /// in as the literal `'any'` sentinel — colliding with the real `'any'`
  /// row already sitting at the same `sdd_stage` and crashing the whole
  /// migration on a primary-key conflict. Found via this file's own
  /// schema-16/18/20 upgrade tests, which start below schema 19 and so
  /// exercise exactly this path.
  Future<void> _widenTransitionPreconditionGraphsWithTicketType(
    Migrator m,
  ) async {
    final tableExists = await m.database
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' "
          "AND name = 'transition_precondition_graphs'",
        )
        .getSingleOrNull();
    if (tableExists == null) return;

    final hasTicketTypeColumn = await m.database
        .customSelect(
          "SELECT 1 FROM pragma_table_info('transition_precondition_graphs') "
          "WHERE name = 'ticket_type'",
        )
        .getSingleOrNull();
    if (hasTicketTypeColumn != null) return;

    await m.database.customStatement('''
      CREATE TABLE transition_precondition_graphs_new (
        sdd_stage TEXT NOT NULL,
        ticket_type TEXT NOT NULL DEFAULT '$anyTicketTypeSentinel',
        root_node_id TEXT,
        PRIMARY KEY (sdd_stage, ticket_type)
      );
    ''');
    await m.database.customStatement('''
      INSERT INTO transition_precondition_graphs_new
        (sdd_stage, ticket_type, root_node_id)
      SELECT sdd_stage, '$anyTicketTypeSentinel', root_node_id
      FROM transition_precondition_graphs;
    ''');
    await m.database.customStatement(
      'DROP TABLE transition_precondition_graphs;',
    );
    await m.database.customStatement(
      'ALTER TABLE transition_precondition_graphs_new '
      'RENAME TO transition_precondition_graphs;',
    );
  }

  /// One-time backfill of `estimate_rollup`/`time_spent_rollup` for every
  /// existing row. Runs only on upgrade from a pre-9 schema — a fresh
  /// [onCreate] install has no pre-existing rows to backfill, so this is
  /// never called there. Selects every row's `(id, parent_id, estimate,
  /// time_spent)` filtered to `deleted_at IS NULL` — the same filter
  /// `TicketRepository.getAllTickets` applies at runtime, so a
  /// pre-existing trashed subtree can't silently poison an ancestor's
  /// backfilled total — maps each row to a [RollupNode], calls
  /// [computeRollups], then writes each non-empty result straight back
  /// with a raw `UPDATE`. Runs inside the same migration transaction
  /// Drift already wraps [onUpgrade] in.
  Future<void> _backfillRollups(Migrator m) async {
    final rows = await m.database
        .customSelect(
          'SELECT * FROM tickets WHERE deleted_at IS NULL',
          readsFrom: {ticketsTable},
        )
        .map((row) => ticketsTable.map(row.data))
        .get();
    final nodes = [
      for (final row in rows)
        (
          id: row.id,
          parentId: row.parentId,
          estimate: row.estimate,
          timeSpent: row.timeSpent,
        ),
    ];
    final results = computeRollups(nodes);
    for (final entry in results.entries) {
      await m.database.customStatement(
        'UPDATE tickets SET estimate_rollup = ?, time_spent_rollup = ? WHERE id = ?',
        [entry.value.estimateRollup, entry.value.timeSpentRollup, entry.key],
      );
    }
  }

  /// One-time backfill of [PageWikilinksTable] for every existing `page`
  /// ticket's `[[...]]`-referencing `description`. Runs only on upgrade
  /// from a pre-12 schema — a fresh [onCreate] install has no
  /// pre-existing rows to backfill, so this is never called there (same
  /// caveat [_backfillRollups] notes). Without this, a `[[...]]` a user
  /// hand-typed into a page *before* this feature shipped would silently
  /// miss the Backlinks section until that page happens to be re-saved.
  ///
  /// Builds an in-memory candidate set of every live `page`/`resource`
  /// ticket's `(id, ticketId, title)`, runs [WikilinkExtractor
  /// .extractReferences] over each live `page`'s `description`, resolves
  /// each match's target the same way `PageWikilinkIndexer` does at
  /// runtime (an exact `ticketId` match when
  /// [WikilinkExtractor.looksLikeTicketId] says it looks like one,
  /// otherwise a case-insensitive first-`createdAt` title match), then
  /// bulk-inserts the resolved rows.
  Future<void> _backfillWikilinks(Migrator m) async {
    final candidateRows = await m.database
        .customSelect(
          "SELECT id, ticket_id, title, created_at FROM tickets "
          "WHERE deleted_at IS NULL AND type IN ('page', 'resource') "
          'ORDER BY created_at ASC',
          readsFrom: {ticketsTable},
        )
        .get();

    final idByTicketId = <String, String>{};
    final idByTitleLower = <String, String>{};
    for (final row in candidateRows) {
      final id = row.read<String>('id');
      idByTicketId[row.read<String>('ticket_id')] = id;
      idByTitleLower.putIfAbsent(
        row.read<String>('title').toLowerCase(),
        () => id,
      );
    }

    final pageRows = await m.database
        .customSelect(
          "SELECT id, description FROM tickets "
          "WHERE deleted_at IS NULL AND type = 'page'",
          readsFrom: {ticketsTable},
        )
        .get();

    final now = DateTime.now();
    const uuid = Uuid();
    for (final row in pageRows) {
      final sourceId = row.read<String>('id');
      final description = row.readNullable<String>('description') ?? '';
      final matches = WikilinkExtractor.extractReferences(description);
      final resolvedIds = <String>{
        for (final match in matches)
          if (WikilinkExtractor.looksLikeTicketId(match.target))
            ?idByTicketId[match.target]
          else
            ?idByTitleLower[match.target.toLowerCase()],
      };
      // Typed insert (not raw SQL) so Drift encodes `createdAt` in
      // whatever on-disk DateTime format it expects, rather than this
      // migration having to duplicate that encoding by hand. `this`
      // (not `m.database`) resolves `pageWikilinksTable` — we're already
      // inside an [AppDatabase] instance method.
      for (final targetId in resolvedIds) {
        await into(pageWikilinksTable).insert(
          PageWikilinksTableCompanion.insert(
            id: uuid.v4(),
            sourcePageId: sourceId,
            targetPageId: targetId,
            createdAt: now,
          ),
        );
      }
    }
  }
}
