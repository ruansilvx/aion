// presentation/cubit/active_project_cubit.dart — ActiveProjectCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/build/project_manifest_writer.dart';
import 'package:aion/core/core.dart';
import 'package:aion/features/projects/data/services/baseline_tailoring_service.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/projects/domain/repositories/project_repository.dart';
import 'package:aion/features/projects/presentation/cubit/active_project_state.dart';

/// Tracks which [Project] is currently active and drives the live,
/// no-restart project switch described in
/// `AIO-1174` §6: the workspace
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
  /// Creates an [ActiveProjectCubit] backed by [_repository],
  /// [_baselineRepository], and [_baselineTailoringService].
  ActiveProjectCubit(
    this._repository,
    this._baselineRepository,
    this._baselineTailoringService,
  ) : super(const ActiveProjectNone());

  final ProjectRepository _repository;
  final BaselineRepository _baselineRepository;
  final BaselineTailoringService _baselineTailoringService;

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

  @override
  bool get offerBaselineUpgrade => switch (state) {
    ActiveProjectOpen(:final offerBaselineUpgrade) => offerBaselineUpgrade,
    _ => false,
  };

  /// Makes [project] the active project. Emits
  /// [ActiveProjectSwitching] (carrying the previously active project,
  /// if any) immediately, persists `lastOpenedAt` via
  /// [ProjectRepository.updateLastOpened], then emits
  /// [ActiveProjectOpen] carrying [offerCodebaseAnalysis] (default
  /// `false` — pass `true` only right after creating a project from an
  /// already-git-tracked directory; see `NewProjectScreen.onCreated`)
  /// and a freshly-computed [ActiveProjectOpen.offerBaselineUpgrade]
  /// (`true` whenever [project]'s pinned baseline version isn't the
  /// latest version bundled in the running build).
  Future<void> switchTo(
    Project project, {
    bool offerCodebaseAnalysis = false,
  }) async {
    final previous = activeProject;
    emit(ActiveProjectSwitching(from: previous, to: project));

    final now = DateTime.now();
    await _repository.updateLastOpened(project.id, now);

    final versions = await _baselineRepository.getAvailableBaselineVersions();
    final offerBaselineUpgrade = project.baselineVersion != versions.last;

    emit(
      ActiveProjectOpen(
        _withLastOpened(project, now),
        offerCodebaseAnalysis: offerCodebaseAnalysis,
        offerBaselineUpgrade: offerBaselineUpgrade,
      ),
    );
  }

  /// Clears the current [ActiveProjectOpen.offerCodebaseAnalysis] flag
  /// back to `false`, re-emitting the same project unchanged (preserving
  /// [ActiveProjectOpen.offerBaselineUpgrade] untouched). Called by
  /// `TicketsListScreen.initState` once it has read the flag and shown
  /// (or decided not to show) the codebase-analysis offer, so the offer
  /// never reappears on a later rebuild within the same session. No-ops
  /// if the current state isn't [ActiveProjectOpen], or the flag is
  /// already `false`. Added for
  /// `AIO-1266`.
  @override
  void consumeCodebaseAnalysisOffer() {
    final current = state;
    if (current is! ActiveProjectOpen || !current.offerCodebaseAnalysis) {
      return;
    }
    emit(
      ActiveProjectOpen(
        current.project,
        offerBaselineUpgrade: current.offerBaselineUpgrade,
      ),
    );
  }

  /// Clears the current [ActiveProjectOpen.offerBaselineUpgrade] flag
  /// back to `false`, re-emitting the same project unchanged (preserving
  /// [ActiveProjectOpen.offerCodebaseAnalysis] untouched). Called by
  /// `TicketsListScreen.initState` once it has read the flag and shown
  /// (or decided not to show) the baseline-upgrade offer banner. No-ops
  /// if the current state isn't [ActiveProjectOpen], or the flag is
  /// already `false`. Added for
  /// `AIO-297`.
  @override
  void consumeBaselineUpgradeOffer() {
    final current = state;
    if (current is! ActiveProjectOpen || !current.offerBaselineUpgrade) {
      return;
    }
    emit(
      ActiveProjectOpen(
        current.project,
        offerCodebaseAnalysis: current.offerCodebaseAnalysis,
      ),
    );
  }

  /// Bumps [activeProject]'s pinned baseline to the latest bundled
  /// version: updates the registry DB row
  /// ([ProjectRepository.updateBaselineVersion]), rewrites
  /// `.aion/manifest.json` (desktop only), and tailors any
  /// newly-introduced `architectureConvention`-kind asset (desktop
  /// only — see
  /// [BaselineTailoringService.tailorNewlyIntroducedAssets]). A no-op if
  /// the current state isn't [ActiveProjectOpen] or the project is
  /// already pinned to the latest version. Re-emits [ActiveProjectOpen]
  /// with the bumped project and [ActiveProjectOpen.offerBaselineUpgrade]
  /// cleared. Added for
  /// `AIO-297`.
  @override
  Future<void> acceptBaselineUpgrade() async {
    final current = state;
    if (current is! ActiveProjectOpen) return;
    final project = current.project;

    final versions = await _baselineRepository.getAvailableBaselineVersions();
    final newVersion = versions.last;
    if (newVersion == project.baselineVersion) return;

    final oldManifest = await _baselineRepository.getManifest(
      project.baselineVersion,
    );
    final newManifest = await _baselineRepository.getManifest(newVersion);

    await _repository.updateBaselineVersion(project.id, newVersion);

    final rootPath = project.rootPath;
    if (rootPath != null) {
      await ProjectManifestWriter.write(rootPath, newVersion);
      await _baselineTailoringService.tailorNewlyIntroducedAssets(
        projectId: project.id,
        rootPath: rootPath,
        oldManifest: oldManifest,
        newManifest: newManifest,
      );
    }

    emit(
      ActiveProjectOpen(
        _withBaselineVersion(project, newVersion),
        offerCodebaseAnalysis: current.offerCodebaseAnalysis,
      ),
    );
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

  Project _withBaselineVersion(Project project, String baselineVersion) {
    return Project(
      id: project.id,
      name: project.name,
      storageKey: project.storageKey,
      rootPath: project.rootPath,
      baselineVersion: baselineVersion,
      createdAt: project.createdAt,
      lastOpenedAt: project.lastOpenedAt,
    );
  }
}
