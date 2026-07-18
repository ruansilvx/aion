// core/database/app_database.dart — AppDatabase Drift database (core layer).

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/tickets/data/daos/comment_dao.dart';
import 'package:aion/features/tickets/data/daos/ticket_dao.dart';
import 'package:aion/features/tickets/data/daos/ticket_link_dao.dart';
import 'package:aion/features/tickets/data/models/ticket_comment_model.dart';
import 'package:aion/features/tickets/data/models/ticket_link_model.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';

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
/// `TicketRepository.trashTicket`/`restoreTicket`.
@DriftDatabase(
  tables: [
    TicketsTable,
    TicketIdSequenceTable,
    TicketLinksTable,
    TicketCommentsTable,
  ],
  daos: [TicketDao, TicketLinkDao, CommentDao],
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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await into(ticketIdSequenceTable).insert(
        const TicketIdSequenceTableCompanion(id: Value(1), seq: Value(0)),
      );
      await _createSearchInfrastructure(m);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await _createSearchInfrastructure(m);
      }
      if (from < 3) {
        await m.addColumn(ticketsTable, ticketsTable.deletedAt);
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
}
