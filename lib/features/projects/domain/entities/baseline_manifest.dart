// domain/entities/baseline_manifest.dart — BaselineManifest entity (domain layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/projects/domain/entities/baseline_asset.dart';

/// One versioned, app-bundled baseline package: a fixed set of default
/// skills, model config, and architecture-convention pointers a
/// [Project](project.dart) pins at creation time. See
/// `aion-arch/changes/multi-project-hub/design.md` §8.
class BaselineManifest extends Equatable {
  /// The baseline version this manifest describes (e.g. `"0.1.0"`).
  final String version;

  /// Every asset bundled at this version.
  final List<BaselineAsset> assets;

  /// Creates a [BaselineManifest].
  const BaselineManifest({required this.version, required this.assets});

  @override
  List<Object?> get props => [version, assets];
}
