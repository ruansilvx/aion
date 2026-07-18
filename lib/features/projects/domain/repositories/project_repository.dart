// domain/repositories/project_repository.dart — ProjectRepository interface (domain layer).

import 'package:aion/features/projects/domain/entities/project.dart';

/// Read/write access to the project registry — the lightweight,
/// non-project-scoped list of every known [Project] and its metadata.
/// Implemented by the data layer ([DriftProjectRepository]); UI and
/// domain code depend only on this interface, never on a concrete data
/// source. Plain reads/writes only — no validation (see
/// [CreateProjectCubit] for the invariants a project must satisfy
/// before this is called).
abstract interface class ProjectRepository {
  /// Returns every known project, in no particular order — callers that
  /// need most-recently-opened-first ordering (the Hub) sort the result
  /// themselves.
  Future<List<Project>> getAllProjects();

  /// Returns the project with internal id [id], or `null` if none
  /// exists.
  Future<Project?> getProject(String id);

  /// Adds [project] to the registry.
  ///
  /// @throws if a project with the same [Project.id] already exists.
  Future<void> createProject(Project project);

  /// Updates only the `lastOpenedAt` field of the project with id [id]
  /// to [timestamp]. Does not touch any other field.
  ///
  /// @throws if [id] does not exist.
  Future<void> updateLastOpened(String id, DateTime timestamp);

  /// Removes the registry entry for project [id]. Does **not** delete
  /// the project's on-disk data (desktop) or storage namespace
  /// (mobile/web) — see
  /// `aion-arch/changes/multi-project-hub/design.md` §3.
  ///
  /// @throws if [id] does not exist.
  Future<void> removeProject(String id);
}
