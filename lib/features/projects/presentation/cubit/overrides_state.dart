// presentation/cubit/overrides_state.dart — OverridesState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/projects/domain/entities/baseline_manifest.dart';
import 'package:aion/features/projects/domain/entities/project_override.dart';

/// The state emitted by [OverridesCubit].
sealed class OverridesState extends Equatable {
  const OverridesState();

  @override
  List<Object?> get props => [];
}

/// The manifest/override fetch is in flight. UI should show [AppSpinner].
class OverridesLoading extends OverridesState {
  /// Creates an [OverridesLoading] state.
  const OverridesLoading();
}

/// The active project's pinned baseline manifest and its local overrides
/// loaded successfully.
class OverridesReady extends OverridesState {
  /// Creates an [OverridesReady] state carrying [manifest] and
  /// [overrides].
  const OverridesReady({required this.manifest, required this.overrides});

  /// The active project's pinned baseline manifest — every asset key it
  /// starts from.
  final BaselineManifest manifest;

  /// Which of [manifest]'s assets the active project has a local override
  /// for. Matched against a [BaselineAsset.key](baseline_asset.dart) by
  /// [ProjectOverride.assetKey].
  final List<ProjectOverride> overrides;

  @override
  List<Object?> get props => [manifest, overrides];
}

/// The manifest/override fetch failed. Carries a raw, unlocalized
/// description of what went wrong.
class OverridesError extends OverridesState {
  /// Creates an [OverridesError] state carrying [message].
  const OverridesError(this.message);

  /// A raw, unlocalized description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
