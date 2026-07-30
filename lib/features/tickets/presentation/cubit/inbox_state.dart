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
/// launching, for the launcher UI's own per-card loading state.
class InboxLaunching extends InboxState {
  /// Creates an [InboxLaunching] state carrying which [purpose] is
  /// launching.
  const InboxLaunching(this.purpose);

  /// The Inbox purpose currently launching.
  final InboxPurpose purpose;

  @override
  List<Object?> get props => [purpose];
}

/// An [InboxCubit.load]/`start*` call failed.
class InboxError extends InboxState {
  /// Creates an [InboxError] state carrying [message].
  const InboxError(this.message);

  /// A raw, unlocalized description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
