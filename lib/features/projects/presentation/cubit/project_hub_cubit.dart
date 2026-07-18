// presentation/cubit/project_hub_cubit.dart — ProjectHubCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/projects/domain/repositories/project_repository.dart';
import 'package:aion/features/projects/presentation/cubit/project_hub_state.dart';

/// Loads and lists every known project via [ProjectRepository], for the
/// Hub screen. Root-scoped — provided above the workspace subtree, not
/// inside it, since the Hub is reachable with no active project.
class ProjectHubCubit extends Cubit<ProjectHubState> {
  /// Creates a [ProjectHubCubit] backed by [_repository].
  ProjectHubCubit(this._repository) : super(const ProjectHubInitial());

  final ProjectRepository _repository;

  /// Fetches every known project, sorted most-recently-opened first.
  /// Emits [ProjectHubLoading] first, then [ProjectHubEmpty] if none
  /// exist or [ProjectHubLoaded] otherwise, or [ProjectHubError] if the
  /// repository call throws.
  Future<void> load() async {
    emit(const ProjectHubLoading());
    try {
      final projects = await _repository.getAllProjects();
      if (projects.isEmpty) {
        emit(const ProjectHubEmpty());
        return;
      }
      final sorted = List<Project>.of(projects)
        ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      emit(ProjectHubLoaded(sorted));
    } catch (e) {
      emit(ProjectHubError(e.toString()));
    }
  }

  /// Removes [projectId]'s registry entry via
  /// [ProjectRepository.removeProject] (on-disk data is left intact —
  /// see [ProjectRepository.removeProject]'s own docs), then reloads
  /// the list via [load].
  Future<void> removeProject(String projectId) async {
    try {
      await _repository.removeProject(projectId);
      await load();
    } catch (e) {
      emit(ProjectHubError(e.toString()));
    }
  }
}
