// domain/entities/chat_turn_result.dart — ChatTurnResult sealed hierarchy (domain layer).

import 'package:equatable/equatable.dart';

/// The outcome of one `ChatCubit.runChatTurn` call. Replaces that
/// method's previous plain `bool` return — a cancelled turn needs to
/// carry its accumulated-but-unpersisted text back to the caller, which
/// a `bool` can't express. See `AIO-1400`
/// §3.
sealed class ChatTurnResult extends Equatable {
  /// Creates a [ChatTurnResult].
  const ChatTurnResult();

  @override
  List<Object?> get props => [];
}

/// The turn completed successfully. `runChatTurn` has already persisted
/// the accumulated reply as one `CommentAuthorType.ai` comment — the
/// caller has nothing further to persist.
class ChatTurnSuccess extends ChatTurnResult {
  /// Creates a [ChatTurnSuccess].
  const ChatTurnSuccess();
}

/// The turn failed (an `AgentErrorEvent` or a thrown exception).
/// `runChatTurn` has already persisted a `'Execution failed: ...'`
/// `CommentAuthorType.ai` comment — the caller has nothing further to
/// persist.
class ChatTurnFailure extends ChatTurnResult {
  /// Creates a [ChatTurnFailure].
  const ChatTurnFailure();
}

/// The turn was cancelled mid-flight (an `AgentCancelledEvent`).
/// `runChatTurn` persists nothing for a cancelled turn — [accumulatedText]
/// carries whatever text had streamed in before the cancellation back to
/// the caller, which decides for itself whether/how to persist it (see
/// `ChatCubit.sendMessage`, `TicketsCubit._runCodingExecution`).
class ChatTurnCancelled extends ChatTurnResult {
  /// Creates a [ChatTurnCancelled] carrying [accumulatedText].
  const ChatTurnCancelled(this.accumulatedText);

  /// The reply text accumulated from `AgentTextEvent` chunks before the
  /// turn was cancelled. May be empty if cancellation happened before
  /// any text streamed in.
  final String accumulatedText;

  @override
  List<Object?> get props => [accumulatedText];
}
