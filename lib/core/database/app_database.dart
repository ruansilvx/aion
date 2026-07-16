// core/database/app_database.dart — AppDatabase Drift database (core layer).

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'package:aion/features/tickets/data/daos/comment_dao.dart';
import 'package:aion/features/tickets/data/daos/ticket_dao.dart';
import 'package:aion/features/tickets/data/daos/ticket_link_dao.dart';
import 'package:aion/features/tickets/data/models/ticket_comment_model.dart';
import 'package:aion/features/tickets/data/models/ticket_link_model.dart';
import 'package:aion/features/tickets/data/models/ticket_model.dart';

part 'app_database.g.dart';

/// Opens the platform-appropriate [QueryExecutor].
///
/// drift_flutter's `driftDatabase` picks the right implementation per
/// platform via conditional imports: `NativeDatabase` (dart:io) on
/// desktop/mobile, and `WasmDatabase` (drift/wasm) on web. The `web` option
/// is only consulted by the web implementation; it is ignored on native.
QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'aion',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('worker.dart.js'),
    ),
  );
}

/// Aion's local SQLite database. Schema version 2, seeding
/// [TicketIdSequenceTable] with a single `(id: 1, seq: 0)` row on creation.
/// Version 2 adds ticket search/filter infrastructure (see
/// [_createSearchInfrastructure]): indexes on `status`/`type`/`priority`
/// and an external-content FTS5 index over `title`/`description`.
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
  /// Creates an [AppDatabase]. Pass [executor] to use a custom connection
  /// (e.g. `NativeDatabase.memory()` in tests); otherwise opens the normal
  /// platform-appropriate connection via [_openConnection].
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

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
