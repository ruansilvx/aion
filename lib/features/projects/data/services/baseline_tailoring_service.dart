// data/services/baseline_tailoring_service.dart — BaselineTailoringService (data layer).

import 'package:aion/core/build/project_stack_detector.dart';
import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/entities/baseline_manifest.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';

/// Writes a project's baseline overrides from [ProjectStackDetector]'s
/// marker-file detection (the "shallow" path — see AIO-53) for the one
/// asset kind that mechanism can produce content for:
/// [BaselineAssetKind.architectureConvention]. Used both at project
/// creation ([tailorForDetectedStack], called against the version just
/// pinned) and, via [tailorNewlyIntroducedAssets], during a baseline
/// version upgrade (called against the new version). The "full agentic"
/// path (tied to `new-project-onboarding`'s not-yet-built
/// codebase-summarization depth choice) is out of scope for this
/// change; this method's shape (project id + root path in, overrides
/// written as a side effect) is designed to be called again later by
/// that feature with richer input, not to be the only caller forever.
class BaselineTailoringService {
  /// Creates a [BaselineTailoringService] backed by [_baselineRepository]
  /// and [_detector].
  BaselineTailoringService(this._baselineRepository, this._detector);

  final BaselineRepository _baselineRepository;
  final ProjectStackDetector _detector;

  /// Writes a project's `conventions/architecture-conventions` override
  /// from [ProjectStackDetector]'s marker-file detection, resolving the
  /// concrete asset (key, bundled path) from [manifest] rather than a
  /// hardcoded version. No-ops if [ProjectStackDetector.detect] finds
  /// nothing (an undetected stack has no sensible content to template),
  /// or if [manifest] has no [BaselineAssetKind.architectureConvention]
  /// asset.
  Future<void> tailorForDetectedStack({
    required String projectId,
    required String rootPath,
    required BaselineManifest manifest,
  }) async {
    final detected = _detector.detect(rootPath);
    if (detected == null) return;

    // No `package:collection` dependency exists in pubspec.yaml today —
    // a plain loop instead of `.firstOrNull` avoids adding one for this.
    BaselineAsset? asset;
    for (final a in manifest.assets) {
      if (a.kind == BaselineAssetKind.architectureConvention) {
        asset = a;
        break;
      }
    }
    if (asset == null) return;

    final content =
        '# Architecture conventions\n\n'
        'Detected stack: ${detected.language}.\n\n'
        'Suggested build/verification command: `${detected.checkCommand}`'
        '${detected.setupCommand != null ? ' (after `${detected.setupCommand}`)' : ''}.\n\n'
        'Add your own conventions, formatting rules, and architectural '
        'constraints below.';

    await _baselineRepository.writeOverride(
      projectId: projectId,
      asset: asset,
      content: content,
    );
  }

  /// Called on a baseline version upgrade. Finds the
  /// [BaselineAssetKind.architectureConvention] asset in [newManifest],
  /// if any, whose key did not exist at all in [oldManifest] — i.e.
  /// genuinely newly-introduced by this version bump, not merely
  /// re-tailored. If found and not already locally overridden, runs
  /// [tailorForDetectedStack] against [newManifest]. No-ops otherwise:
  /// this is the only asset kind [tailorForDetectedStack]'s template
  /// mechanism can produce content for — any other newly-introduced key
  /// (a new `skills/*` file, say) is deliberately left unoverridden,
  /// resolving to its bundled default like any other unoverridden
  /// asset.
  Future<void> tailorNewlyIntroducedAssets({
    required String projectId,
    required String rootPath,
    required BaselineManifest oldManifest,
    required BaselineManifest newManifest,
  }) async {
    final oldKeys = oldManifest.assets.map((a) => a.key).toSet();
    BaselineAsset? newConventionAsset;
    for (final a in newManifest.assets) {
      if (a.kind == BaselineAssetKind.architectureConvention &&
          !oldKeys.contains(a.key)) {
        newConventionAsset = a;
        break;
      }
    }
    if (newConventionAsset == null) return;

    final overrides = await _baselineRepository.readOverrides(projectId);
    final alreadyOverridden = overrides.any(
      (o) => o.assetKey == newConventionAsset!.key,
    );
    if (alreadyOverridden) return;

    await tailorForDetectedStack(
      projectId: projectId,
      rootPath: rootPath,
      manifest: newManifest,
    );
  }
}
