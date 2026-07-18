// domain/entities/resolved_config_item.dart — ResolvedConfigItem entity + ConfigSource enum (domain layer).

import 'package:equatable/equatable.dart';

/// Where a [ResolvedConfigItem]'s content actually came from.
enum ConfigSource {
  /// Unshadowed — served from the pinned [BaselineManifest].
  baseline,

  /// Shadowed by a project-local [ProjectOverride](project_override.dart).
  override,
}

/// One entry of a project's effective configuration: the result of
/// merging a [BaselineManifest](baseline_manifest.dart) with whatever
/// [ProjectOverride](project_override.dart)s exist for a project,
/// override-wins by matching key. See
/// `aion-arch/changes/multi-project-hub/design.md` §2 — no
/// override-authoring UI consumes this yet in this change; it exists so
/// future "effective config" surfaces (e.g. which skills are available)
/// have a settled shape to build on.
class ResolvedConfigItem extends Equatable {
  /// The [BaselineAsset.key](baseline_asset.dart)/
  /// [ProjectOverride.assetKey] this entry resolves.
  final String key;

  /// Whether [contentPath] came from the baseline or a local override.
  final ConfigSource source;

  /// Resolved content path — a bundled asset path when [source] is
  /// [ConfigSource.baseline], or a real override file path when
  /// [source] is [ConfigSource.override].
  final String contentPath;

  /// Creates a [ResolvedConfigItem].
  const ResolvedConfigItem({
    required this.key,
    required this.source,
    required this.contentPath,
  });

  @override
  List<Object?> get props => [key, source, contentPath];
}
