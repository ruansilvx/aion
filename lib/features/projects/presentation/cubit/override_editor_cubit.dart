// presentation/cubit/override_editor_cubit.dart — OverrideEditorCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/projects/domain/entities/baseline_asset.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/projects/presentation/cubit/override_editor_state.dart';

/// Loads and saves one baseline asset's effective content — its local
/// override if one exists, otherwise the bundled default — for
/// `OverrideEditorScreen`. Route-scoped — provided per visit to
/// `/workspace/settings/overrides/:assetKey`, not at the app root.
class OverrideEditorCubit extends Cubit<OverrideEditorState> {
  /// Creates an [OverrideEditorCubit] backed by [_baselineRepository],
  /// scoped to the project identified by [_projectId] pinned to
  /// [_baselineVersion], editing the asset keyed [_assetKey].
  OverrideEditorCubit(
    this._baselineRepository,
    this._projectId,
    this._baselineVersion,
    this._assetKey,
  ) : super(const OverrideEditorLoading());

  final BaselineRepository _baselineRepository;
  final String _projectId;
  final String _baselineVersion;
  final String _assetKey;

  /// The resolved [BaselineAsset] for [_assetKey], captured by [load] for
  /// [save] to reuse — avoids re-resolving the manifest on every save.
  BaselineAsset? _asset;

  /// Resolves [_assetKey] against [_baselineVersion]'s manifest, then
  /// loads its effective content: the project's local override content
  /// if [BaselineRepository.readOverrides] finds one matching
  /// [_assetKey], otherwise the bundled default. Emits
  /// [OverrideEditorLoading] then [OverrideEditorReady] on success, or
  /// [OverrideEditorError] if [_assetKey] isn't in the manifest or any
  /// repository call throws.
  Future<void> load() async {
    emit(const OverrideEditorLoading());
    try {
      final manifest = await _baselineRepository.getManifest(
        _baselineVersion,
      );
      BaselineAsset? asset;
      for (final candidate in manifest.assets) {
        if (candidate.key == _assetKey) {
          asset = candidate;
          break;
        }
      }
      if (asset == null) {
        emit(OverrideEditorError('Unknown baseline asset: $_assetKey'));
        return;
      }
      _asset = asset;

      final overrides = await _baselineRepository.readOverrides(_projectId);
      String? overridePath;
      for (final override in overrides) {
        if (override.assetKey == _assetKey) {
          overridePath = override.overridePath;
          break;
        }
      }

      final content = overridePath != null
          ? await _baselineRepository.readOverrideContent(overridePath)
          : await _baselineRepository.readBundledContent(asset);
      emit(
        OverrideEditorReady(content: content, isOverridden: overridePath != null),
      );
    } catch (e) {
      emit(OverrideEditorError(e.toString()));
    }
  }

  /// Writes [content] as the project's local override for the asset
  /// resolved by [load]. No-ops if [load] hasn't successfully resolved
  /// an asset yet. Emits [OverrideEditorSaving] then [OverrideEditorSaved]
  /// on success, or [OverrideEditorError] if the write throws.
  Future<void> save(String content) async {
    final asset = _asset;
    if (asset == null) return;
    emit(OverrideEditorSaving(content));
    try {
      await _baselineRepository.writeOverride(
        projectId: _projectId,
        asset: asset,
        content: content,
      );
      emit(const OverrideEditorSaved());
    } catch (e) {
      emit(OverrideEditorError(e.toString()));
    }
  }
}
