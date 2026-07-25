// presentation/cubit/overrides_cubit.dart — OverridesCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/projects/presentation/cubit/overrides_state.dart';

/// Loads the active project's pinned baseline manifest and its local
/// overrides for `OverridesListScreen`. Route-scoped — provided per visit
/// to `/workspace/settings/overrides`, not at the app root.
class OverridesCubit extends Cubit<OverridesState> {
  /// Creates an [OverridesCubit] backed by [_baselineRepository], scoped
  /// to the project identified by [_projectId] pinned to
  /// [_baselineVersion].
  OverridesCubit(
    this._baselineRepository,
    this._projectId,
    this._baselineVersion,
  ) : super(const OverridesLoading());

  final BaselineRepository _baselineRepository;
  final String _projectId;
  final String _baselineVersion;

  /// Fetches [_baselineVersion]'s manifest and [_projectId]'s local
  /// overrides. Emits [OverridesLoading] then [OverridesReady] on
  /// success, or [OverridesError] if either repository call throws.
  Future<void> load() async {
    emit(const OverridesLoading());
    try {
      final manifest = await _baselineRepository.getManifest(
        _baselineVersion,
      );
      final overrides = await _baselineRepository.readOverrides(_projectId);
      emit(OverridesReady(manifest: manifest, overrides: overrides));
    } catch (e) {
      emit(OverridesError(e.toString()));
    }
  }
}
