// presentation/cubit/baseline_upgrade_cubit.dart — BaselineUpgradeCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/active_project_provider.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/projects/presentation/cubit/baseline_upgrade_state.dart';

/// Drives `SettingsScreen`'s "BASELINE" section — the manual,
/// always-available upgrade action. Thin by design: the actual upgrade
/// logic already lives on `ActiveProjectCubit.acceptBaselineUpgrade`
/// (via [ActiveProjectProvider]); this cubit only merges "current
/// version" and "latest available version" into a UI-ready state and
/// forwards the accept call. Added for
/// `aion-arch/changes/baseline-version-upgrade-flow`.
class BaselineUpgradeCubit extends Cubit<BaselineUpgradeState> {
  /// Creates a [BaselineUpgradeCubit] backed by [_baselineRepository] and
  /// [_activeProjectProvider].
  BaselineUpgradeCubit(this._baselineRepository, this._activeProjectProvider)
    : super(const BaselineUpgradeLoading());

  final BaselineRepository _baselineRepository;
  final ActiveProjectProvider _activeProjectProvider;

  /// Loads the active project's currently pinned baseline version and
  /// the latest bundled version, emitting [BaselineUpgradeLoading] then
  /// [BaselineUpgradeReady]. The leading [BaselineUpgradeLoading] emit
  /// only matters if [load] is ever called again after already
  /// [BaselineUpgradeReady] (there's no such call site today —
  /// `app_router.dart` calls this once, on creation) — kept anyway so a
  /// future re-load shows a transient spinner instead of jumping
  /// straight between two ready states.
  Future<void> load() async {
    emit(const BaselineUpgradeLoading());
    final versions = await _baselineRepository.getAvailableBaselineVersions();
    final project = _activeProjectProvider.activeProject!;
    emit(
      BaselineUpgradeReady(
        currentVersion: project.baselineVersion,
        latestVersion: versions.last,
      ),
    );
  }

  /// Bumps the active project's pinned baseline to the latest bundled
  /// version via [ActiveProjectProvider.acceptBaselineUpgrade]. Emits an
  /// [BaselineUpgradeReady] with [BaselineUpgradeReady.isUpgrading] set
  /// while the call is in flight, then a final ready state reflecting
  /// the bumped version. No-ops if the current state isn't
  /// [BaselineUpgradeReady] or [BaselineUpgradeReady.isUpToDate] is
  /// already `true`.
  Future<void> upgrade() async {
    final current = state;
    if (current is! BaselineUpgradeReady || current.isUpToDate) return;
    emit(
      BaselineUpgradeReady(
        currentVersion: current.currentVersion,
        latestVersion: current.latestVersion,
        isUpgrading: true,
      ),
    );
    await _activeProjectProvider.acceptBaselineUpgrade();
    final project = _activeProjectProvider.activeProject!;
    emit(
      BaselineUpgradeReady(
        currentVersion: project.baselineVersion,
        latestVersion: current.latestVersion,
      ),
    );
  }
}
