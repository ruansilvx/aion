// presentation/cubit/baseline_upgrade_state.dart — BaselineUpgradeState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

/// The state emitted by `BaselineUpgradeCubit`.
sealed class BaselineUpgradeState extends Equatable {
  const BaselineUpgradeState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before `BaselineUpgradeCubit.load` resolves.
class BaselineUpgradeLoading extends BaselineUpgradeState {
  /// Creates a [BaselineUpgradeLoading] state.
  const BaselineUpgradeLoading();
}

/// Loaded — carries the active project's currently pinned baseline
/// version and the latest bundled version, for `SettingsScreen`'s
/// "BASELINE" section to render.
class BaselineUpgradeReady extends BaselineUpgradeState {
  /// Creates a [BaselineUpgradeReady] state.
  const BaselineUpgradeReady({
    required this.currentVersion,
    required this.latestVersion,
    this.isUpgrading = false,
  });

  /// The active project's currently pinned baseline version.
  final String currentVersion;

  /// The latest baseline version bundled in the running build.
  final String latestVersion;

  /// Whether `BaselineUpgradeCubit.upgrade` is currently in flight.
  final bool isUpgrading;

  /// Whether [currentVersion] already equals [latestVersion] — no action
  /// is offered when `true`.
  bool get isUpToDate => currentVersion == latestVersion;

  @override
  List<Object?> get props => [currentVersion, latestVersion, isUpgrading];
}
