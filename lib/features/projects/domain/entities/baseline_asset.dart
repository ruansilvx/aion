// domain/entities/baseline_asset.dart — BaselineAsset entity + BaselineAssetKind enum (domain layer).

import 'package:equatable/equatable.dart';

/// What kind of baseline item a [BaselineAsset] represents.
enum BaselineAssetKind {
  /// A default agentic-coding skill (desktop only), sourced from
  /// `aion-arch/.claude/skills/`.
  skill,

  /// A default model/provider configuration stub.
  modelConfig,

  /// A pointer to an architecture-convention document (e.g.
  /// `flutter-conventions.md`).
  architectureConvention,
}

/// One named item inside a [BaselineManifest](baseline_manifest.dart) —
/// a default skill, model config, or architecture-convention pointer a
/// project starts from and may locally shadow via a
/// [ProjectOverride](project_override.dart) of the same [key].
class BaselineAsset extends Equatable {
  /// Unique name within its manifest (e.g. `"skills/propose"`). Matched
  /// against [ProjectOverride.assetKey] to resolve overrides.
  final String key;

  /// Which category of baseline item this is.
  final BaselineAssetKind kind;

  /// Path to this asset's bundled content inside the app's asset bundle
  /// (e.g. `"assets/baseline/0.1.0/skills/propose.md"`).
  final String bundledPath;

  /// Creates a [BaselineAsset].
  const BaselineAsset({
    required this.key,
    required this.kind,
    required this.bundledPath,
  });

  @override
  List<Object?> get props => [key, kind, bundledPath];
}
