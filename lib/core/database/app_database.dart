// core/database/app_database.dart — AppDatabase Drift database (core layer).

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/markdown/wikilink_extractor.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/tickets/data/daos/comment_dao.dart';
import 'package:aion/features/tickets/data/daos/execution_queue_dao.dart';
import 'package:aion/features/tickets/data/daos/page_wikilink_dao.dart';
import 'package:aion/features/tickets/data/daos/ticket_dao.dart';
import 'package:aion/features/tickets/data/daos/ticket_link_dao.dart';
import 'package:aion/features/tickets/data/daos/workflow_prompt_template_dao.dart';
import 'package:aion/features/tickets/data/daos/workflow_skill_attachment_dao.dart';
import 'package:aion/features/tickets/data/daos/workflow_status_dao.dart';
import 'package:aion/features/tickets/data/models/execution_queue_table.dart';
import 'package:aion/features/tickets/data/models/page_wikilink_model.dart';
import 'package:aion/features/tickets/data/models/ticket_comment_model.dart';
import 'package:aion/features/tickets/data/models/ticket_link_model.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';
import 'package:aion/features/tickets/data/models/workflow_prompt_template_table.dart';
import 'package:aion/features/tickets/data/models/workflow_skill_attachment_table.dart';
import 'package:aion/features/tickets/data/models/workflow_status_table.dart';
import 'package:aion/features/tickets/domain/utils/ticket_rollup_calculator.dart';

part 'app_database.g.dart';

/// Opens the platform-appropriate [QueryExecutor], addressed to [project]'s
/// own isolated storage rather than one fixed global location — see
/// `aion-arch/changes/multi-project-hub/design.md` §7.
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

/// Aion's per-project local SQLite database. One instance exists per
/// currently active [Project] — see
/// `aion-arch/changes/multi-project-hub/design.md` §6, §7 — never one
/// fixed global instance; the project registry itself lives in the
/// separate, non-project-scoped [RegistryDatabase]. Schema version 3,
/// seeding [TicketIdSequenceTable] with a single `(id: 1, seq: 0)` row on
/// creation. Version 2 adds ticket search/filter infrastructure (see
/// [_createSearchInfrastructure]): indexes on `status`/`type`/`priority`
/// and an external-content FTS5 index over `title`/`description`. Version 3
/// adds [TicketsTable.deletedAt] for the trash/soft-delete model — see
/// `TicketRepository.trashTicket`/`restoreTicket`. Version 5 adds
/// `TicketsTable.complexity`/`TicketsTable.sddStage` — see
/// `TicketRepository.updateTicketSddStage`. Version 6 adds
/// `TicketsTable.severity`/`stepsToReproduce`/`expectedBehavior`/
/// `actualBehavior` — see `TicketType.bug`. Version 7 adds
/// `TicketCommentsTable.inputTokens`/`outputTokens` — see
/// `TicketsCubit._executionChatOverCap`. Version 8 adds
/// `TicketsTable.suggestedType`/`inboxPurpose` — see
/// `aion-arch/changes/new-project-onboarding-inbox/design.md` §1.4.
/// Version 9 adds `TicketsTable.estimateRollup`/`timeSpentRollup` and
/// backfills them once for every existing row (see [_backfillRollups]) —
/// see `aion-arch/changes/estimate-timespent-rollup-for-ticket-hierarchy/design.md`
/// §1.4. Version 10 adds `TicketsTable.complexitySource`/`estimateSource`
/// and backfills both to `'manual'` for every pre-existing row whose
/// `complexity`/`estimate` is already set — see
/// `aion-arch/changes/ai-assisted-complexity-and-estimate-suggestions/design.md`
/// §3.4. Version 11 adds no columns — `TicketType.signal` was split into
/// `idea`/`knownGap`/`openQuestion`, so every pre-existing `type =
/// 'signal'` row is blanket-reclassified to `'idea'` (the type that
/// keeps `signal`'s exact prior behavior; not a heuristic guess at
/// gap-vs-question-vs-idea) so the app never crashes deserializing
/// pre-existing data — see
/// `aion-arch/changes/idea-gap-question-ticket-types/design.md` §2.1.
/// Version 12 adds [PageWikilinksTable] and backfills it once from every
/// existing `page` ticket's `description` (see [_backfillWikilinks]) —
/// see
/// `aion-arch/changes/inline-wikilink-backlinks/design.md`. Version 13
/// adds [ExecutionQueueTable], with no backfill — a pre-13 database has
/// no persisted queue state to migrate; `TicketsCubit.restoreExecutionQueue`
/// simply finds nothing to resume on its first post-upgrade launch. See
/// `aion-arch/changes/parallel-work/design.md` §7. Version 14 adds
/// `TicketsTable.predictedExecutionTokensLow`/`predictedExecutionTokensHigh`,
/// with no backfill — a pre-14 database has no recorded predictions to
/// migrate; `TicketTokenPredictor` simply produces its first estimate for
/// each not-yet-executed `task`/`bug` ticket the next time it's created or
/// updated. See `aion-arch/changes/token-cost-prediction/design.md` §1.2.
/// Version 15 adds [WorkflowStatusesTable], seeded with
/// `defaultWorkflowStatuses` for both a fresh install and a backfill of
/// every pre-existing project (via [WorkflowStatusDao.seedDefaultsIfEmpty]),
/// reproducing the exact hardcoded status set/roles a pre-15 database
/// already behaved with. No `tickets.status` column change — it was
/// already a raw `TextColumn`. See
/// `aion-arch/changes/configurable-ticket-workflow/design.md` §2.2.
/// Version 16 adds [WorkflowSkillAttachmentsTable] and
/// [WorkflowPromptTemplatesTable], with no seed/backfill — an empty
/// attachment/template table is the correct starting state for both a
/// fresh install and a pre-existing project, since nothing fires
/// automatically today outside the already-unconditional SDD-stage flow.
/// See `aion-arch/changes/workflow-skill-attachments/design.md` §2.3.
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
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await into(ticketIdSequenceTable).insert(
        const TicketIdSequenceTableCompanion(id: Value(1), seq: Value(0)),
      );
      await _createSearchInfrastructure(m);
      await workflowStatusDao.seedDefaultsIfEmpty();
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
        await m.addColumn(
          ticketCommentsTable,
          ticketCommentsTable.inputTokens,
        );
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
        title, description, content='tickets', content_rowid='rowid'
      );
    ''');

    // Backfill: index whatever rows already exist. A no-op on a fresh
    // onCreate (tickets is empty at this point), essential on onUpgrade
    // (existing local ticket data must become searchable retroactively —
    // the triggers below only cover writes from this point forward).
    await m.database.customStatement('''
      INSERT INTO tickets_fts(rowid, title, description)
      SELECT rowid, title, description FROM tickets;
    ''');

    await m.database.customStatement('''
      CREATE TRIGGER IF NOT EXISTS tickets_fts_ai AFTER INSERT ON tickets BEGIN
        INSERT INTO tickets_fts(rowid, title, description)
        VALUES (new.rowid, new.title, new.description);
      END;
    ''');
    await m.database.customStatement('''
      CREATE TRIGGER IF NOT EXISTS tickets_fts_ad AFTER DELETE ON tickets BEGIN
        INSERT INTO tickets_fts(tickets_fts, rowid, title, description)
        VALUES ('delete', old.rowid, old.title, old.description);
      END;
    ''');
    await m.database.customStatement('''
      CREATE TRIGGER IF NOT EXISTS tickets_fts_au AFTER UPDATE ON tickets BEGIN
        INSERT INTO tickets_fts(tickets_fts, rowid, title, description)
        VALUES ('delete', old.rowid, old.title, old.description);
        INSERT INTO tickets_fts(rowid, title, description)
        VALUES (new.rowid, new.title, new.description);
      END;
    ''');
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
      idByTitleLower.putIfAbsent(row.read<String>('title').toLowerCase(), () => id);
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
