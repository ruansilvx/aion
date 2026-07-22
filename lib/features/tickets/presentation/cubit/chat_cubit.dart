// presentation/cubit/chat_cubit.dart — ChatCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_state.dart';

/// Loads and drives a single `chat`-type ticket's live conversation, via
/// [CommentRepository] (the same append-only store `CommentsCubit` uses
/// for every other ticket type — a chat ticket's comment thread already
/// is its transcript, see
/// `aion-arch/changes/sdd-ticket-execution/proposal.md`'s re-scoping)
/// plus [AgentModelClient] for generating the AI reply. Screen-scoped —
/// provided instead of `CommentsCubit` only when `ticket.type ==
/// TicketType.chat`.
class ChatCubit extends Cubit<ChatState> {
  /// Creates a [ChatCubit] backed by [_repository] and [_client].
  ChatCubit(this._repository, this._client) : super(const ChatInitial());

  final CommentRepository _repository;
  final AgentModelClient _client;

  /// Fetches all comments for [chatTicketId]. Emits [ChatLoaded] on
  /// success (with no `streamingText`), or [ChatError] if the repository
  /// call throws.
  Future<void> loadMessages(String chatTicketId) async {
    try {
      final comments = await _repository.getCommentsForTicket(chatTicketId);
      emit(ChatLoaded(comments));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }

  /// Posts a human comment with [content] on [chatTicketId], then calls
  /// [model] via [AgentModelClient.run], emitting [ChatLoaded] with
  /// `streamingText` updated on every `AgentTextEvent` chunk for live
  /// rendering. On completion, the accumulated reply is persisted as one
  /// [CommentAuthorType.ai] comment (see [runChatTurn]) and the thread is
  /// reloaded. On failure, emits [ChatError] — the human message the user
  /// sent stays persisted; nothing broken is written for the reply.
  Future<void> sendMessage({
    required String chatTicketId,
    required String content,
    required AgentModel model,
  }) async {
    try {
      await _repository.addComment(
        TicketComment(
          id: '',
          ticketId: chatTicketId,
          content: content,
          authorType: CommentAuthorType.human,
          createdAt: DateTime.now(),
        ),
      );
      final afterHuman = await _repository.getCommentsForTicket(chatTicketId);
      emit(ChatLoaded(afterHuman));

      final succeeded = await runChatTurn(
        client: _client,
        commentRepo: _repository,
        chatTicketId: chatTicketId,
        prompt: content,
        model: model,
        onChunk: (textSoFar) => emit(
          ChatLoaded(afterHuman, streamingText: textSoFar),
        ),
      );

      if (!succeeded) {
        emit(ChatError('The model run failed. Please try again.'));
        emit(ChatLoaded(afterHuman));
        return;
      }
      final afterReply = await _repository.getCommentsForTicket(chatTicketId);
      emit(ChatLoaded(afterReply));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }

  /// Calls [client]'s `run` with [prompt]/[model], accumulating every
  /// `AgentTextEvent` chunk (reported to [onChunk], if given) and, on a
  /// successful `AgentDoneEvent` completion, persisting the accumulated
  /// text as one [CommentAuthorType.ai] comment (`aiModel: model.id`) via
  /// [commentRepo]. On failure (an `AgentErrorEvent` or a thrown
  /// exception), persists a `'Execution failed: ...'`
  /// [CommentAuthorType.ai] comment instead — previously a failed run
  /// left no trace for anyone not watching the chat live. Returns `true`
  /// if the turn completed successfully, `false` otherwise. [toolsEnabled]
  /// and [workingDirectory] opt a run into real tool access (file edits,
  /// git, bash) scoped to that directory — only `TicketsCubit`'s
  /// coding-execution path sets these; every other caller leaves them at
  /// their text-only defaults. [onOverageDetected], if given, is called
  /// once per `AgentOverageDetectedEvent`. Shared by [sendMessage] and
  /// `TicketsCubit._spawnStageChat`/coding-execution
  /// (`tickets_cubit.dart`) so all call sites accumulate/persist
  /// identically and can't drift apart.
  static Future<bool> runChatTurn({
    required AgentModelClient client,
    required CommentRepository commentRepo,
    required String chatTicketId,
    required String prompt,
    required AgentModel model,
    void Function(String textSoFar)? onChunk,
    bool toolsEnabled = false,
    String? workingDirectory,
    void Function()? onOverageDetected,
  }) async {
    final buffer = StringBuffer();
    var succeeded = true;
    String? failureMessage;
    try {
      final events = await client.run(
        AgentRequest(
          prompt: prompt,
          model: model.id,
          toolsEnabled: toolsEnabled,
          workingDirectory: workingDirectory,
        ),
      );
      await for (final event in events) {
        switch (event) {
          case AgentTextEvent(:final text):
            buffer.write(text);
            onChunk?.call(buffer.toString());
          case AgentDoneEvent():
            break;
          case AgentOverageDetectedEvent():
            onOverageDetected?.call();
          case AgentErrorEvent(:final message):
            succeeded = false;
            failureMessage = message;
        }
      }
    } catch (e) {
      succeeded = false;
      failureMessage = e.toString();
    }

    if (succeeded && buffer.isNotEmpty) {
      await commentRepo.addComment(
        TicketComment(
          id: '',
          ticketId: chatTicketId,
          content: buffer.toString(),
          authorType: CommentAuthorType.ai,
          aiModel: model.id,
          createdAt: DateTime.now(),
        ),
      );
    } else if (!succeeded) {
      await commentRepo.addComment(
        TicketComment(
          id: '',
          ticketId: chatTicketId,
          content: 'Execution failed: ${failureMessage ?? 'unknown error'}',
          authorType: CommentAuthorType.ai,
          aiModel: model.id,
          createdAt: DateTime.now(),
        ),
      );
    }
    return succeeded;
  }
}
