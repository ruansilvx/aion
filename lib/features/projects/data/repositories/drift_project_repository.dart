// data/repositories/drift_project_repository.dart — Drift implementation of ProjectRepository (data layer).

import 'package:drift/drift.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/data/models/project_model.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/projects/domain/repositories/project_repository.dart';

/// Drift-backed implementation of [ProjectRepository], backed by
/// [RegistryDatabase] — the single, non-project-scoped database listing
/// every known project (see
/// `aion-arch/changes/multi-project-hub/design.md` §3). Plain reads/
/// writes only, no validation — invariants (unique name, path already in
/// use, etc.) are owned by `CreateProjectCubit`, not this class.
class DriftProjectRepository implements ProjectRepository {
  /// Creates a [DriftProjectRepository] backed by [_db].
  DriftProjectRepository(this._db);

  final RegistryDatabase _db;

  @override
  Future<List<Project>> getAllProjects() async {
    final rows = await _db.select(_db.projectsTable).get();
    return rows.map((row) => ProjectModel.fromRow(row).toEntity()).toList();
  }

  @override
  Future<Project?> getProject(String id) async {
    final row = await (_db.select(
      _db.projectsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : ProjectModel.fromRow(row).toEntity();
  }

  @override
  Future<void> createProject(Project project) async {
    await _db
        .into(_db.projectsTable)
        .insert(ProjectModel.fromEntity(project).toCompanion());
  }

  @override
  Future<void> updateLastOpened(String id, DateTime timestamp) async {
    await (_db.update(_db.projectsTable)..where((t) => t.id.equals(id))).write(
      ProjectsTableCompanion(
        lastOpenedAt: Value(timestamp.millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> removeProject(String id) async {
    await (_db.delete(_db.projectsTable)..where((t) => t.id.equals(id))).go();
  }
}
