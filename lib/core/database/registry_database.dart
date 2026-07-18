// core/database/registry_database.dart — RegistryDatabase Drift database (core layer).

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'registry_database.g.dart';

/// The project registry table: one row per known [Project]
/// (`features/projects/domain/entities/project.dart`). No FK
/// constraints — integrity is enforced at the repository layer, same
/// convention as `TicketsTable`.
@DataClassName('ProjectRegistryData')
class ProjectsTable extends Table {
  @override
  String get tableName => 'projects';

  /// Internal UUID v4 primary key.
  TextColumn get id => text()();

  /// Display name shown on the Hub.
  TextColumn get name => text()();

  /// Platform-agnostic storage identifier — see
  /// `Project.storageKey`.
  TextColumn get storageKey => text().named('storage_key')();

  /// Real filesystem directory, desktop only. `null` on mobile/web.
  TextColumn get rootPath => text().named('root_path').nullable()();

  /// Pinned baseline version string (e.g. `"0.1.0"`).
  TextColumn get baselineVersion => text().named('baseline_version')();

  /// Unix milliseconds.
  IntColumn get createdAt => integer().named('created_at')();

  /// Unix milliseconds.
  IntColumn get lastOpenedAt => integer().named('last_opened_at')();

  @override
  Set<Column> get primaryKey => {id};
}

/// Opens the platform-appropriate [QueryExecutor] for the registry
/// database — always at one fixed location per platform, unlike
/// [AppDatabase] which is addressed per-[Project] (see
/// `aion-arch/changes/multi-project-hub/design.md` §7). The registry
/// must be readable before any project is picked, so it cannot itself
/// be project-scoped.
QueryExecutor _openRegistryConnection() {
  return driftDatabase(
    name: 'aion_registry',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('worker.dart.js'),
    ),
  );
}

/// Aion's project registry database — the single piece of drift state
/// that is not per-project (see
/// `aion-arch/changes/multi-project-hub/design.md` §3, §7). Lists every
/// known [Project] and its metadata; consulted by the Hub before any
/// project-scoped [AppDatabase] connection exists.
@DriftDatabase(tables: [ProjectsTable])
class RegistryDatabase extends _$RegistryDatabase {
  /// Creates a [RegistryDatabase]. Pass [executor] to use a custom
  /// connection (e.g. `NativeDatabase.memory()` in tests); otherwise
  /// opens the normal platform-appropriate connection via
  /// [_openRegistryConnection].
  RegistryDatabase([QueryExecutor? executor])
    : super(executor ?? _openRegistryConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (Migrator m) async => m.createAll());
}
