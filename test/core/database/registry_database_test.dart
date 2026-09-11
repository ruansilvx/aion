// test/core/database/registry_database_test.dart — RegistryDatabase schema-2 migration tests.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';

void main() {
  test('a fresh onCreate install can write and read ticketsRootPath', () async {
    final database = RegistryDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await database
        .into(database.projectsTable)
        .insert(
          ProjectsTableCompanion.insert(
            id: '1',
            name: 'Test Project',
            storageKey: '1',
            ticketsRootPath: const Value('/tickets/repo'),
            baselineVersion: '0.1.0',
            createdAt: 0,
            lastOpenedAt: 0,
          ),
        );

    final row = await (database.select(
      database.projectsTable,
    )..where((t) => t.id.equals('1'))).getSingle();

    expect(row.ticketsRootPath, '/tickets/repo');
  });

  group('schema 2 — ticketsRootPath column', () {
    // No exported-schema/SchemaVerifier infrastructure exists in this
    // codebase (see app_database_test.dart's own schema-15 coverage
    // rationale for the same point) -- so the pre-migration schema-1
    // `projects` table is hand-authored here via raw SQL, matching
    // exactly what `ProjectsTable` generated before `ticketsRootPath`
    // existed (every column this migration doesn't touch). Unlike the
    // brand-new-table migrations `app_database_test.dart` covers this
    // way, `addColumn` needs a real pre-existing table to alter, so the
    // "just stamp user_version" shortcut alone isn't enough here.
    test('an install upgraded from schema 1 keeps its existing row, with '
        'ticketsRootPath null', () async {
      final database = RegistryDatabase(
        NativeDatabase.memory(
          setup: (db) {
            db.execute('''
                CREATE TABLE "projects" (
                  "id" TEXT NOT NULL,
                  "name" TEXT NOT NULL,
                  "storage_key" TEXT NOT NULL,
                  "root_path" TEXT NULL,
                  "baseline_version" TEXT NOT NULL,
                  "created_at" INTEGER NOT NULL,
                  "last_opened_at" INTEGER NOT NULL,
                  PRIMARY KEY ("id")
                )
              ''');
            db.execute(
              'INSERT INTO "projects" (id, name, storage_key, '
              'baseline_version, created_at, last_opened_at) '
              "VALUES ('1', 'Existing Project', '1', '0.1.0', 0, 0)",
            );
            db.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(database.close);

      final row = await (database.select(
        database.projectsTable,
      )..where((t) => t.id.equals('1'))).getSingle();

      expect(row.name, 'Existing Project');
      expect(row.ticketsRootPath, isNull);
    });

    test('an install upgraded from schema 1 can write ticketsRootPath on a '
        'new row', () async {
      final database = RegistryDatabase(
        NativeDatabase.memory(
          setup: (db) {
            db.execute('''
                CREATE TABLE "projects" (
                  "id" TEXT NOT NULL,
                  "name" TEXT NOT NULL,
                  "storage_key" TEXT NOT NULL,
                  "root_path" TEXT NULL,
                  "baseline_version" TEXT NOT NULL,
                  "created_at" INTEGER NOT NULL,
                  "last_opened_at" INTEGER NOT NULL,
                  PRIMARY KEY ("id")
                )
              ''');
            db.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(database.close);

      await database
          .into(database.projectsTable)
          .insert(
            ProjectsTableCompanion.insert(
              id: '2',
              name: 'New Project',
              storageKey: '2',
              ticketsRootPath: const Value('/tickets/repo'),
              baselineVersion: '0.1.0',
              createdAt: 0,
              lastOpenedAt: 0,
            ),
          );

      final row = await (database.select(
        database.projectsTable,
      )..where((t) => t.id.equals('2'))).getSingle();

      expect(row.ticketsRootPath, '/tickets/repo');
    });
  });
}
