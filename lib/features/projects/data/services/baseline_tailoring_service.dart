// data/services/baseline_tailoring_service.dart — BaselineTailoringService (data layer).

import 'package:aion/core/build/project_stack_detector.dart';
import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';

/// Writes a project's initial baseline overrides at creation time,
/// scoped for now to the architecture-convention asset populated from
/// [ProjectStackDetector]'s marker-file detection (the "shallow" path —
/// see `aion-arch/ideas/project-type-aware-conventions-and-
/// verification.md`). The "full agentic" path (tied to
/// `new-project-onboarding`'s not-yet-built codebase-summarization
/// depth choice) is out of scope for this change; this method's shape
/// (project id + root path in, overrides written as a side effect) is
/// designed to be called again later by that feature with richer input,
/// not to be the only caller forever.
class BaselineTailoringService {
  /// Creates a [BaselineTailoringService] backed by [_baselineRepository]
  /// and [_detector].
  BaselineTailoringService(this._baselineRepository, this._detector);

  final BaselineRepository _baselineRepository;
  final ProjectStackDetector _detector;

  /// No-ops if [ProjectStackDetector.detect] finds nothing (an
  /// undetected stack has no sensible content to template).
  Future<void> tailorForDetectedStack({
    required String projectId,
    required String rootPath,
  }) async {
    final detected = _detector.detect(rootPath);
    if (detected == null) return;

    const asset = BaselineAsset(
      key: 'conventions/architecture-conventions',
      kind: BaselineAssetKind.architectureConvention,
      bundledPath: 'assets/baseline/0.3.0/architecture_convention.md',
    );
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
}
