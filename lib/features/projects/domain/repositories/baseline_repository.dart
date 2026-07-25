// domain/repositories/baseline_repository.dart — BaselineRepository interface (domain layer).

import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/entities/baseline_manifest.dart';
import 'package:aion/features/projects/domain/entities/project_override.dart';

/// Read and write access to bundled baseline manifests and a project's
/// local override files. Implemented by the data layer
/// ([BundledBaselineRepository]). Pure I/O — no validation of override
/// content; that belongs in a Cubit (see `OverrideEditorCubit`).
abstract interface class BaselineRepository {
  /// Returns every baseline version bundled in the current app build
  /// (e.g. `["0.1.0"]`).
  Future<List<String>> getAvailableBaselineVersions();

  /// Returns the full manifest for baseline [version].
  ///
  /// @throws if [version] is not bundled in the current app build.
  Future<BaselineManifest> getManifest(String version);

  /// Returns every override file found under
  /// `<rootPath>/.aion/overrides/` for the project with id [projectId].
  /// Returns an empty list when the project has no `rootPath` (i.e. on
  /// mobile/web, where overrides are not supported in this change).
  Future<List<ProjectOverride>> readOverrides(String projectId);

  /// Returns [asset]'s bundled default content (from the app's asset
  /// bundle) — used by the override editor to show "start from the
  /// default," and by `TicketsCubit` to resolve an asset's effective
  /// content when no project override exists for it.
  Future<String> readBundledContent(BaselineAsset asset);

  /// Returns the content of an override file at [overridePath]
  /// ([ProjectOverride.overridePath]).
  Future<String> readOverrideContent(String overridePath);

  /// Creates or overwrites [projectId]'s override for [asset], writing
  /// [content] to `<rootPath>/.aion/overrides/<lastKeySegment>.<ext>` —
  /// the same flat-filename convention [readOverrides] already reads
  /// back. No-ops silently if the project has no `rootPath` (mobile/web).
  Future<void> writeOverride({
    required String projectId,
    required BaselineAsset asset,
    required String content,
  });
}
