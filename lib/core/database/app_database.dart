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

/// Aion's local SQLite database. Schema version 1, seeding
/// [TicketIdSequenceTable] with a single `(id: 1, seq: 0)` row on creation.
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await into(ticketIdSequenceTable).insert(
        const TicketIdSequenceTableCompanion(id: Value(1), seq: Value(0)),
      );
    },
  );
}
