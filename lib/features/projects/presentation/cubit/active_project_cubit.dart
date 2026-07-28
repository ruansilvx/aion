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

  @override
  bool get offerCodebaseAnalysis => switch (state) {
    ActiveProjectOpen(:final offerCodebaseAnalysis) => offerCodebaseAnalysis,
    _ => false,
  };

  /// Makes [project] the active project. Emits
  /// [ActiveProjectSwitching] (carrying the previously active project,
  /// if any) immediately, persists `lastOpenedAt` via
  /// [ProjectRepository.updateLastOpened], then emits
  /// [ActiveProjectOpen] carrying [offerCodebaseAnalysis] (default
  /// `false` — pass `true` only right after creating a project from an
  /// already-git-tracked directory; see `NewProjectScreen.onCreated`).
  Future<void> switchTo(
    Project project, {
    bool offerCodebaseAnalysis = false,
  }) async {
    final previous = activeProject;
    emit(ActiveProjectSwitching(from: previous, to: project));

    final now = DateTime.now();
    await _repository.updateLastOpened(project.id, now);
    emit(
      ActiveProjectOpen(
        _withLastOpened(project, now),
        offerCodebaseAnalysis: offerCodebaseAnalysis,
      ),
    );
  }

  /// Clears the current [ActiveProjectOpen.offerCodebaseAnalysis] flag
  /// back to `false`, re-emitting the same project unchanged. Called by
  /// `TicketsListScreen.initState` once it has read the flag and shown
  /// (or decided not to show) the codebase-analysis offer, so the offer
  /// never reappears on a later rebuild within the same session. No-ops
  /// if the current state isn't [ActiveProjectOpen], or the flag is
  /// already `false`. Added for
  /// `aion-arch/changes/new-project-onboarding`.
  @override
  void consumeCodebaseAnalysisOffer() {
    final current = state;
    if (current is! ActiveProjectOpen || !current.offerCodebaseAnalysis) {
      return;
    }
    emit(ActiveProjectOpen(current.project));
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
