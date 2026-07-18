// core/contracts/active_project_provider.dart — ActiveProjectProvider abstract interface (core layer).

import 'package:aion/features/projects/domain/entities/project.dart';

/// Cross-feature contract exposing which [Project] is currently active,
/// if any. Implemented by `ActiveProjectCubit`
/// (`features/projects/presentation/cubit/active_project_cubit.dart`)
/// and provided once at the app root.
///
/// Per `project.md`'s Pattern 1 (dependency inversion via `core`), any
/// feature other than `projects` that needs to know the active project
/// depends only on this interface — never on `features/projects/`
/// directly. See
/// `aion-arch/changes/multi-project-hub/design.md` §4.
abstract interface class ActiveProjectProvider {
  /// The currently active project, or `null` when no project is open
  /// (i.e. the user is at the Hub).
  Project? get activeProject;

  /// Emits [activeProject] every time it changes.
  Stream<Project?> get activeProjectStream;
}
