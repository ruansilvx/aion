// presentation/cubit/active_project_state.dart — ActiveProjectState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/projects/domain/entities/project.dart';

/// The state emitted by [ActiveProjectCubit].
sealed class ActiveProjectState extends Equatable {
  const ActiveProjectState();

  @override
  List<Object?> get props => [];
}

/// No project is open — the user is at the Hub. The initial state, and
/// gates every `/workspace/*` route (see
/// `aion-arch/changes/multi-project-hub/design.md` §9) to redirect to
/// `/hub`.
class ActiveProjectNone extends ActiveProjectState {
  /// Creates an [ActiveProjectNone] state.
  const ActiveProjectNone();
}

/// A [ActiveProjectCubit.switchTo] call is in flight: the previously
/// active project's workspace subtree (and its [AppDatabase]
/// connection) is being torn down and the new one built. Transient —
/// shown as a loading transition rather than a flash of empty content.
class ActiveProjectSwitching extends ActiveProjectState {
  /// Creates an [ActiveProjectSwitching] state carrying the project
  /// being left ([from], `null` if none) and the project being opened
  /// ([to]).
  const ActiveProjectSwitching({required this.from, required this.to});

  /// The project that was active before this switch, if any.
  final Project? from;

  /// The project being switched to.
  final Project to;

  @override
  List<Object?> get props => [from, to];
}

/// [project] is the active project and its workspace subtree is ready.
class ActiveProjectOpen extends ActiveProjectState {
  /// Creates an [ActiveProjectOpen] state carrying [project] and whether
  /// the codebase-analysis offer should be shown on first ticket-list
  /// open.
  const ActiveProjectOpen(this.project, {this.offerCodebaseAnalysis = false});

  /// The currently active project.
  final Project project;

  /// Whether `TicketsListScreen` should show the opt-in
  /// codebase-summarization offer banner the next time it builds.
  /// `true` only immediately after [ActiveProjectCubit.switchTo] was
  /// called with `offerCodebaseAnalysis: true` (i.e. [project] was just
  /// created from an already-git-tracked directory) — in-memory only,
  /// not persisted, so it's naturally "shown once, right after
  /// creation" rather than a standing flag.
  /// [ActiveProjectCubit.consumeCodebaseAnalysisOffer] clears it back to
  /// `false` once the screen has read it. Added for
  /// `aion-arch/changes/new-project-onboarding`.
  final bool offerCodebaseAnalysis;

  @override
  List<Object?> get props => [project, offerCodebaseAnalysis];
}
