// domain/repositories/baseline_repository.dart — BaselineRepository interface (domain layer).

import 'package:aion/features/projects/domain/entities/baseline_manifest.dart';
import 'package:aion/features/projects/domain/entities/project_override.dart';

/// Read access to bundled baseline manifests and a project's local
/// override files. Implemented by the data layer
/// ([BundledBaselineRepository]). Pure reads — no validation of
/// override content; that belongs in a Cubit if/when override-authoring
/// UI exists (out of scope for this change, see
/// `aion-arch/changes/multi-project-hub/proposal.md`).
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
}
