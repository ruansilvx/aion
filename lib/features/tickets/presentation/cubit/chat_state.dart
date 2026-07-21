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
  /// [streamingText].
  const ChatLoaded(this.comments, {this.streamingText});

  /// The settled comment thread, oldest first (see
  /// [CommentRepository.getCommentsForTicket]).
  final List<TicketComment> comments;

  /// The in-progress AI reply's accumulated text, updated on every
  /// `AgentTextEvent` chunk. `null` when no reply is currently streaming.
  final String? streamingText;

  @override
  List<Object?> get props => [comments, streamingText];
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
