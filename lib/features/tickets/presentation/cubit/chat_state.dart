// presentation/cubit/chat_state.dart — ChatState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';

/// The state emitted by [ChatCubit](chat_cubit.dart).
sealed class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object?> get props => [];
}

/// Before [ChatCubit.loadMessages] has been called.
class ChatInitial extends ChatState {
  /// Creates a [ChatInitial] state.
  const ChatInitial();
}

/// A `chat` ticket's comment thread loaded successfully. Carries the
/// settled [comments] plus, while an AI reply is being generated,
/// [streamingText] — the accumulated (not yet persisted) reply text so
/// far. `null` when no reply is in flight.
class ChatLoaded extends ChatState {
  /// Creates a [ChatLoaded] state carrying [comments] and, optionally,
  /// [streamingText]/[currentToolUse]/[activeRunId].
  const ChatLoaded(
    this.comments, {
    this.streamingText,
    this.currentToolUse,
    this.activeRunId,
  });

  /// The settled comment thread, oldest first (see
  /// [CommentRepository.getCommentsForTicket]).
  final List<TicketComment> comments;

  /// The in-progress AI reply's accumulated text, updated on every
  /// `AgentTextEvent` chunk. `null` when no reply is currently streaming.
  final String? streamingText;

  /// A live "Running `<tool>`..."-style status string, updated on every
  /// `AgentToolUseEvent` and cleared on the next `AgentTextEvent` chunk or
  /// on completion. `null` when no tool call is currently in flight. Added
  /// for `aion-arch/changes/coding-execution-reliability-and-safety`.
  final String? currentToolUse;

  /// The `AgentRequest.runId` of the currently in-flight reply, or `null`
  /// when no reply is streaming. Read by `ChatCubit.cancelReply` to
  /// resolve which run to cancel, and by `_StreamingBubble`'s stop button
  /// to decide whether it's visible. Added for
  /// `aion-arch/changes/parallel-work`; see that change's design.md §3.
  final String? activeRunId;

  @override
  List<Object?> get props => [
    comments,
    streamingText,
    currentToolUse,
    activeRunId,
  ];
}

/// A [ChatCubit.loadMessages] or [ChatCubit.sendMessage] call failed.
class ChatError extends ChatState {
  /// Creates a [ChatError] state carrying a raw, unlocalized [message].
  const ChatError(this.message);

  /// A raw, unlocalized description of what went wrong.
  final String message;

  @override
  List<Object?> get props => [message];
}
