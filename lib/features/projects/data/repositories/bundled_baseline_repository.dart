// data/repositories/bundled_baseline_repository.dart — Bundled-asset implementation of BaselineRepository (data layer).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/entities/baseline_manifest.dart';
import 'package:aion/features/projects/domain/entities/project_override.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/projects/domain/repositories/project_repository.dart';

/// Reads baseline manifests from the app's bundled
/// `assets/baseline/<version>/manifest.json` assets, and lists a
/// project's local override files from
/// `<rootPath>/.aion/overrides/`. Depends on [ProjectRepository] to
/// resolve a project id to its `rootPath` for [readOverrides] — pure
/// reads only, no validation (see
/// `aion-arch/changes/multi-project-hub/design.md` §3).
class BundledBaselineRepository implements BaselineRepository {
  /// Creates a [BundledBaselineRepository]. [_projectRepository] resolves
  /// a project id to its `rootPath` for [readOverrides]; [_bundle]
  /// defaults to [rootBundle] and is overridable for tests.
  BundledBaselineRepository(this._projectRepository, {AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final ProjectRepository _projectRepository;
  final AssetBundle _bundle;

  /// Baseline versions bundled in the current app build. Hardcoded to
  /// the single version shipped in `assets/baseline/` — a future
  /// baseline release adds an entry here alongside its own asset
  /// directory.
  static const _bundledVersions = ['0.1.0'];

  @override
  Future<List<String>> getAvailableBaselineVersions() async {
    return List.unmodifiable(_bundledVersions);
  }

  @override
  Future<BaselineManifest> getManifest(String version) async {
    if (!_bundledVersions.contains(version)) {
      throw ArgumentError.value(
        version,
        'version',
        'No bundled baseline manifest for this version',
      );
    }

    final raw = await _bundle.loadString(
      'assets/baseline/$version/manifest.json',
    );
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final assetsJson = json['assets'] as List<dynamic>;

    return BaselineManifest(
      version: json['version'] as String,
      assets: assetsJson
          .map((a) => _assetFromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  BaselineAsset _assetFromJson(Map<String, dynamic> json) {
    return BaselineAsset(
      key: json['key'] as String,
      kind: BaselineAssetKind.values.byName(json['kind'] as String),
      bundledPath: json['bundledPath'] as String,
    );
  }

  @override
  Future<List<ProjectOverride>> readOverrides(String projectId) async {
    final project = await _projectRepository.getProject(projectId);
    final rootPath = project?.rootPath;
    if (rootPath == null) return const [];

    final overridesDir = Directory(
      '$rootPath${Platform.pathSeparator}.aion${Platform.pathSeparator}overrides',
    );
    if (!overridesDir.existsSync()) return const [];

    return overridesDir
        .listSync()
        .whereType<File>()
        .map(
          (file) => ProjectOverride(
            projectId: projectId,
            assetKey: _assetKeyFromFileName(file.path),
            overridePath: file.path,
          ),
        )
        .toList();
  }

  /// Derives a baseline asset key from an override file's name — the
  /// file name without its extension (e.g. `propose.md` → `"propose"`).
  /// Matched against [BaselineAsset.key] by the caller.
  String _assetKeyFromFileName(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex == -1 ? fileName : fileName.substring(0, dotIndex);
  }
}
