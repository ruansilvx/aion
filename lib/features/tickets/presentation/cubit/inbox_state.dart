// presentation/cubit/inbox_state.dart — InboxState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/inbox_purpose.dart';

/// The state emitted by [InboxCubit](inbox_cubit.dart).
sealed class InboxState extends Equatable {
  const InboxState();

  @override
  List<Object?> get props => [];
}

/// Before [InboxCubit.load] has been called. Nothing to render but an
/// empty shell.
class InboxInitial extends InboxState {
  /// Creates an [InboxInitial] state.
  const InboxInitial();
}

/// An [InboxCubit.load] call is in flight and nothing is on screen yet.
/// UI should show [AppSpinner](../../../../design_system/design_system.dart).
class InboxLoading extends InboxState {
  /// Creates an [InboxLoading] state.
  const InboxLoading();
}

/// The Inbox history list loaded successfully.
class InboxLoaded extends InboxState {
  /// Creates an [InboxLoaded] state carrying [history].
  const InboxLoaded({required this.history});

  /// Every Inbox-spawned `chat` ticket (`inboxPurpose != null`), sorted
  /// by `createdAt` descending.
  final List<Ticket> history;

  @override
  List<Object?> get props => [history];
}

/// A purpose launch ([InboxCubit.startBrainDump]/[startWhatNextGuidance]/
/// [startReleasePlanning]/[startQa]) is in flight — spawning the chat
/// ticket and running its opening turn. Carries which [purpose] is
/// launching, for the launcher UI's own per-card loading state, plus
/// [history] — the last successfully loaded history, carried forward
/// (rather than dropped) so the Recent section doesn't flash empty for
/// the whole launch — see `AIO-2821`.
class InboxLaunching extends InboxState {
  /// Creates an [InboxLaunching] state carrying which [purpose] is
  /// launching, plus the [history] to keep showing meanwhile.
  const InboxLaunching(this.purpose, {this.history = const []});

  /// The Inbox purpose currently launching.
  final InboxPurpose purpose;

  /// The last successfully loaded history — kept visible in the Recent
  /// section while this launch is in flight. Fixed for `AIO-2821`: before
  /// this field existed, the Recent section (built from `state.history`
  /// only when `state is InboxLoaded`) fell straight to its empty state
  /// the instant a launch began, with no loading indicator, for the
  /// entire multi-second launch — see [InboxCubit._currentHistory].
  final List<Ticket> history;

  @override
  List<Object?> get props => [purpose, history];
}

/// An [InboxCubit.load]/`start*` call failed.
class InboxError extends InboxState {
  /// Creates an [InboxError] state carrying [message], plus the
  /// [history] to keep showing meanwhile — same `AIO-2821` fix as
  /// [InboxLaunching.history], for a `start*` call that fails after
  /// already having cleared the screen to [InboxLaunching].
  const InboxError(this.message, {this.history = const []});

  /// A raw, unlocalized description of what went wrong.
  final String message;

  /// The last successfully loaded history — kept visible in the Recent
  /// section despite the failure. Empty when [InboxCubit.load] itself is
  /// what failed, since there's nothing to carry forward yet.
  final List<Ticket> history;

  @override
  List<Object?> get props => [message, history];
}
