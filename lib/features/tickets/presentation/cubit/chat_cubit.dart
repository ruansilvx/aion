// presentation/cubit/chat_cubit.dart — ChatCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_state.dart';

/// Loads and drives a single `chat`-type ticket's live conversation, via
/// [CommentRepository] (the same append-only store `CommentsCubit` uses
/// for every other ticket type — a chat ticket's comment thread already
/// is its transcript, see
/// `aion-arch/changes/sdd-ticket-execution/proposal.md`'s re-scoping)
/// plus [AgentModelClient] for generating the AI reply. Screen-scoped —
/// provided instead of `CommentsCubit` only when `ticket.type ==
/// TicketType.chat`. [_ticketRepository]/[_modelRoutingRepository] are
/// used to infer which [ModelPhase] a chat belongs to (see
/// [_phaseForChat]) so [sendMessage] can resolve the phase-appropriate
/// model itself, added for
/// `aion-arch/changes/per-phase-tier-based-model-routing`.
class ChatCubit extends Cubit<ChatState> {
  /// Creates a [ChatCubit] backed by [_repository], [_client],
  /// [_ticketRepository], and [_modelRoutingRepository].
  ChatCubit(
    this._repository,
    this._client,
    this._ticketRepository,
    this._modelRoutingRepository,
  ) : super(const ChatInitial());

  final CommentRepository _repository;
  final AgentModelClient _client;
  final TicketRepository _ticketRepository;
  final ModelRoutingRepository _modelRoutingRepository;

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

  /// Posts a human comment with [content] on [chatTicketId], resolves the
  /// model via [_phaseForChat]/[_modelRoutingRepository], then calls it
  /// via [AgentModelClient.run], emitting [ChatLoaded] with
  /// `streamingText` updated on every `AgentTextEvent` chunk, and
  /// `currentToolUse` updated on every `AgentToolUseEvent`, for live
  /// rendering. On completion, the accumulated reply is persisted as one
  /// [CommentAuthorType.ai] comment (see [runChatTurn]) and the thread is
  /// reloaded. On failure, emits [ChatError] — the human message the user
  /// sent stays persisted; nothing broken is written for the reply.
  Future<void> sendMessage({
    required String chatTicketId,
    required String content,
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

      final phase = await _phaseForChat(chatTicketId);
      final model = await _modelRoutingRepository.getModelForPhase(phase);

      final succeeded = await runChatTurn(
        client: _client,
        commentRepo: _repository,
        chatTicketId: chatTicketId,
        prompt: content,
        model: model,
        onChunk: (textSoFar) => emit(
          ChatLoaded(afterHuman, streamingText: textSoFar),
        ),
        onToolUse: (toolName, summary) => emit(
          ChatLoaded(
            afterHuman,
            currentToolUse: summary == null
                ? 'Running $toolName...'
                : 'Running $toolName: $summary...',
          ),
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

  /// Infers which [ModelPhase] governs [chatTicketId]'s model calls, from
  /// its parent ticket: an `epic`/`story` parent's current
  /// `Ticket.sddStage` (via [SddStageModelPhase.modelPhase]), or
  /// [ModelPhase.execution] for a `task` parent. Every chat ticket in the
  /// app is spawned exclusively by `TicketsCubit._spawnStageChat`/
  /// `_runCodingExecution` (the only two `createTicket` call sites for
  /// `TicketType.chat` in the codebase), so a chat always has a
  /// resolvable parent in real usage — the [ModelPhase.capable] fallback
  /// below only matters defensively (a malformed/orphaned chat in tests).
  /// Added for `aion-arch/changes/per-phase-tier-based-model-routing`.
  Future<ModelPhase> _phaseForChat(String chatTicketId) async {
    final chat = await _ticketRepository.getTicketById(chatTicketId);
    final parentId = chat?.parentId;
    if (parentId == null) return ModelPhase.capable;
    final parent = await _ticketRepository.getTicketById(parentId);
    if (parent == null) return ModelPhase.capable;
    if (parent.type == TicketType.task) return ModelPhase.execution;
    return parent.sddStage?.modelPhase ?? ModelPhase.capable;
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
  /// once per `AgentOverageDetectedEvent`. [onToolUse], if given, is
  /// called once per `AgentToolUseEvent` with the tool's name and short
  /// summary — added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety` so a
  /// long-running turn has live progress visibility. Shared by
  /// [sendMessage] and `TicketsCubit._spawnStageChat`/coding-execution
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
    void Function(String toolName, String? summary)? onToolUse,
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
          case AgentToolUseEvent(:final toolName, :final summary):
            onToolUse?.call(toolName, summary);
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
