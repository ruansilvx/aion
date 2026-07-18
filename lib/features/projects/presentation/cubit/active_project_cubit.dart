// presentation/cubit/active_project_cubit.dart — ActiveProjectCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/core.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/projects/domain/repositories/project_repository.dart';
import 'package:aion/features/projects/presentation/cubit/active_project_state.dart';

/// Tracks which [Project] is currently active and drives the live,
/// no-restart project switch described in
/// `aion-arch/changes/multi-project-hub/design.md` §6: the workspace
/// subtree in `main.dart` is keyed on `ValueKey(activeProject.id)`, so
/// emitting a new [ActiveProjectOpen] with a different project id causes
/// Flutter to dispose the old subtree (closing its [AppDatabase]
/// connection) and build a fresh one addressed to the new project.
///
/// Implements [ActiveProjectProvider] (the `core/contracts/` interface,
/// per `project.md`'s Pattern 1) so any feature can depend on "what
/// project is active" without importing `features/projects/` directly.
/// Provided once at the app root, above the workspace subtree.
class ActiveProjectCubit extends Cubit<ActiveProjectState>
    implements ActiveProjectProvider {
  /// Creates an [ActiveProjectCubit] backed by [_repository].
  ActiveProjectCubit(this._repository) : super(const ActiveProjectNone());

  final ProjectRepository _repository;

  @override
  Project? get activeProject => switch (state) {
    ActiveProjectOpen(:final project) => project,
    _ => null,
  };

  @override
  Stream<Project?> get activeProjectStream => stream.map(
    (s) => switch (s) {
      ActiveProjectOpen(:final project) => project,
      _ => null,
    },
  );

  /// Makes [project] the active project. Emits
  /// [ActiveProjectSwitching] (carrying the previously active project,
  /// if any) immediately, persists `lastOpenedAt` via
  /// [ProjectRepository.updateLastOpened], then emits
  /// [ActiveProjectOpen].
  Future<void> switchTo(Project project) async {
    final previous = activeProject;
    emit(ActiveProjectSwitching(from: previous, to: project));

    final now = DateTime.now();
    await _repository.updateLastOpened(project.id, now);
    emit(ActiveProjectOpen(_withLastOpened(project, now)));
  }

  Project _withLastOpened(Project project, DateTime lastOpenedAt) {
    return Project(
      id: project.id,
      name: project.name,
      storageKey: project.storageKey,
      rootPath: project.rootPath,
      baselineVersion: project.baselineVersion,
      createdAt: project.createdAt,
      lastOpenedAt: lastOpenedAt,
    );
  }
}
