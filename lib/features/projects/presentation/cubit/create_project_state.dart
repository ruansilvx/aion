// presentation/cubit/create_project_state.dart — CreateProjectState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/projects/domain/entities/project.dart';

/// The state emitted by [CreateProjectCubit].
sealed class CreateProjectState extends Equatable {
  const CreateProjectState();

  @override
  List<Object?> get props => [];
}

/// Before [CreateProjectCubit.submit] has been called.
class CreateProjectInitial extends CreateProjectState {
  /// Creates a [CreateProjectInitial] state.
  const CreateProjectInitial();
}

/// [CreateProjectCubit.submit]'s validation invariants (name non-empty
/// and unique; desktop: chosen directory not already an Aion project)
/// are being checked.
class CreateProjectValidating extends CreateProjectState {
  /// Creates a [CreateProjectValidating] state.
  const CreateProjectValidating();
}

/// Validation passed — the form's input is ready to persist. Carries the
/// values that passed validation so the widget layer can, if useful,
/// confirm exactly what will be created.
class CreateProjectReady extends CreateProjectState {
  /// Creates a [CreateProjectReady] state carrying the validated form
  /// values.
  const CreateProjectReady({
    required this.name,
    this.rootPath,
    required this.baselineVersion,
  });

  /// The validated, trimmed project name.
  final String name;

  /// The validated directory, desktop only. `null` on mobile/web.
  final String? rootPath;

  /// The baseline version the new project will pin.
  final String baselineVersion;

  @override
  List<Object?> get props => [name, rootPath, baselineVersion];
}

/// The repository call to persist the new project is in flight.
class CreateProjectSubmitting extends CreateProjectState {
  /// Creates a [CreateProjectSubmitting] state.
  const CreateProjectSubmitting();
}

/// The project was created successfully. Carries the new [Project] so
/// the widget layer can navigate straight into it.
class CreateProjectSuccess extends CreateProjectState {
  /// Creates a [CreateProjectSuccess] state carrying [project].
  const CreateProjectSuccess(this.project);

  /// The newly created project.
  final Project project;

  @override
  List<Object?> get props => [project];
}

/// Categorizes a [CreateProjectFailure] so it can be localized at the
/// widget layer without [CreateProjectCubit] needing a `BuildContext`.
/// `null` on [CreateProjectFailure.reason] means the failure carries
/// only a raw, unlocalized [CreateProjectFailure.message] (e.g. a
/// forwarded repository exception).
enum CreateProjectFailureReason {
  /// [CreateProjectCubit.submit] was called with an empty/whitespace-only
  /// name.
  emptyName,

  /// The chosen name collides with an existing project's name
  /// (case-insensitive, trimmed).
  duplicateName,

  /// The chosen directory has no `.aion/manifest.json` check performed
  /// yet, or the check found the directory is already used by another
  /// project.
  directoryAlreadyInUse,

  /// Desktop only: no directory was chosen before submitting.
  directoryNotChosen,
}

/// A [CreateProjectCubit.submit] call failed. Carries either a
/// classified [reason] — resolved to localized text at the widget layer
/// — or a raw, unlocalized [message] when no more specific reason
/// applies. [reason] takes precedence over [message] for display
/// whenever it's non-null.
class CreateProjectFailure extends CreateProjectState {
  /// Creates a [CreateProjectFailure] state. Pass [reason] for a
  /// classified, localizable error; otherwise [message] is shown as-is.
  const CreateProjectFailure(this.message, {this.reason});

  /// A raw, unlocalized description of what went wrong. Ignored in
  /// favor of [reason] when [reason] is non-null.
  final String message;

  /// A classified failure reason, if this failure corresponds to a
  /// known, localizable case. `null` for generic/forwarded exceptions.
  final CreateProjectFailureReason? reason;

  @override
  List<Object?> get props => [message, reason];
}
