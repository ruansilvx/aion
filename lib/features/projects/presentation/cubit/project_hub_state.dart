// presentation/cubit/project_hub_state.dart — ProjectHubState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/projects/domain/entities/project.dart';

/// The state emitted by [ProjectHubCubit].
sealed class ProjectHubState extends Equatable {
  const ProjectHubState();

  @override
  List<Object?> get props => [];
}

/// Before [ProjectHubCubit.load] has been called. Nothing to render but
/// an empty shell.
class ProjectHubInitial extends ProjectHubState {
  /// Creates a [ProjectHubInitial] state.
  const ProjectHubInitial();
}

/// The project list fetch is in flight. UI should show [AppSpinner].
class ProjectHubLoading extends ProjectHubState {
  /// Creates a [ProjectHubLoading] state.
  const ProjectHubLoading();
}

/// The project list loaded successfully and is non-empty. Carries the
/// projects to render, most-recently-opened first.
class ProjectHubLoaded extends ProjectHubState {
  /// Creates a [ProjectHubLoaded] state carrying [projects].
  const ProjectHubLoaded(this.projects);

  /// The known projects, most-recently-opened first.
  final List<Project> projects;

  @override
  List<Object?> get props => [projects];
}

/// The project list loaded successfully but no projects exist yet
/// (first run). Distinct from [ProjectHubLoaded] carrying an empty list
/// so the Hub can render its onboarding empty state instead of an empty
/// list.
class ProjectHubEmpty extends ProjectHubState {
  /// Creates a [ProjectHubEmpty] state.
  const ProjectHubEmpty();
}

/// A [ProjectHubCubit.load] call failed. Carries a raw, unlocalized
/// description of what went wrong.
class ProjectHubError extends ProjectHubState {
  /// Creates a [ProjectHubError] state carrying [message].
  const ProjectHubError(this.message);

  /// A raw, unlocalized description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
