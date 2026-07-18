// domain/entities/project_override.dart — ProjectOverride entity (domain layer).

import 'package:equatable/equatable.dart';

/// A project-local file shadowing one named
/// [BaselineAsset](baseline_asset.dart) by matching [assetKey]. Desktop
/// only in this change — mobile/web projects have no local filesystem
/// override surface (see
/// `aion-arch/changes/multi-project-hub/design.md` §2).
class ProjectOverride extends Equatable {
  /// The [Project.id](project.dart) this override belongs to.
  final String projectId;

  /// The [BaselineAsset.key] this override shadows.
  final String assetKey;

  /// Real file path of the override, under
  /// `<rootPath>/.aion/overrides/`.
  final String overridePath;

  /// Creates a [ProjectOverride].
  const ProjectOverride({
    required this.projectId,
    required this.assetKey,
    required this.overridePath,
  });

  @override
  List<Object?> get props => [projectId, assetKey, overridePath];
}
