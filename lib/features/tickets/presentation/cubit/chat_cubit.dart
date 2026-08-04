// presentation/cubit/chat_cubit.dart — ChatCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/inbox_purpose.dart';
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
/// plus [ProviderRegistry] to resolve the [AgentProvider] that generates
/// the AI reply. Screen-scoped — provided instead of `CommentsCubit` only
/// when `ticket.type == TicketType.chat`.
/// [_ticketRepository]/[_modelRoutingRepository] are used to infer which
/// [ModelPhase] a chat belongs to (see [_phaseForChat]) so [sendMessage]
/// can resolve the phase-appropriate model/provider itself, added for
/// `aion-arch/changes/per-phase-tier-based-model-routing`.
class ChatCubit extends Cubit<ChatState> {
  /// Creates a [ChatCubit] backed by [_repository], [_providerRegistry],
  /// [_ticketRepository], and [_modelRoutingRepository].
  ChatCubit(
    this._repository,
    this._providerRegistry,
    this._ticketRepository,
    this._modelRoutingRepository,
  ) : super(const ChatInitial());

  final CommentRepository _repository;
  final ProviderRegistry _providerRegistry;
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
  /// model/provider via [_phaseForChat]/[_resolveModelAndProvider], then
  /// calls it via [AgentModelClient.run], emitting [ChatLoaded] with
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
      final (model, provider) = await _resolveModelAndProvider(phase);

      // Tracks the most recent onChunk text so onToolUse can carry it
      // forward instead of blanking it — a tool call fired mid-turn
      // (after some text already streamed) would otherwise reset
      // ChatLoaded.streamingText to null via its constructor default.
      String? latestStreamingText;
      final succeeded = await runChatTurn(
        client: provider.client,
        provider: provider,
        commentRepo: _repository,
        chatTicketId: chatTicketId,
        prompt: content,
        model: model,
        onChunk: (textSoFar) {
          latestStreamingText = textSoFar;
          emit(ChatLoaded(afterHuman, streamingText: textSoFar));
        },
        onToolUse: (toolName, summary) => emit(
          ChatLoaded(
            afterHuman,
            streamingText: latestStreamingText,
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

  /// Resolves [phase] to its currently configured [AgentModelDescriptor]
  /// (via [_modelRoutingRepository]) and that model's [AgentProvider]
  /// (via [_providerRegistry]). Shared helper so every model call site
  /// resolves the pair identically — see
  /// `aion-arch/changes/pluggable-provider-abstraction/design.md` §7.
  Future<(AgentModelDescriptor, AgentProvider)> _resolveModelAndProvider(
    ModelPhase phase,
  ) async {
    final model = await _modelRoutingRepository.getModelForPhase(phase);
    final provider = _providerRegistry.providerById(model.providerId);
    return (model, provider);
  }

  /// Infers which [ModelPhase] governs [chatTicketId]'s model calls, via
  /// two independent resolution paths. First, and parent-independent: if
  /// the chat's own `Ticket.inboxPurpose` is set (an Inbox-spawned chat,
  /// see `aion-arch/changes/new-project-onboarding-inbox/design.md` §1.3),
  /// resolve directly from [_phaseForInboxPurpose] and return — Inbox
  /// chats are deliberately parentless (see
  /// `TicketsCubit.updateTicketParent`'s reparent guard), so the
  /// parent-walk below would otherwise always hit its defensive fallback
  /// for them. Otherwise, fall back to the original parent-based
  /// inference: an `epic`/`story` parent's current `Ticket.sddStage` (via
  /// [SddStageModelPhase.modelPhase]), or [ModelPhase.execution] for a
  /// Task or Bug parent (see `TicketTypeHierarchy.isExecutable` —
  /// `aion-arch/changes/bug-ticket-type` gave `bug` full coding-execution
  /// parity with `task`, so a manual chat reply on a Bug's execution
  /// transcript resolves to the same tier a Task's would). Every non-Inbox
  /// chat ticket in the app is spawned exclusively by
  /// `TicketsCubit._spawnStageChat`/`_runCodingExecution` (the only other
  /// `createTicket` call sites for `TicketType.chat` in the codebase), so
  /// such a chat always has a resolvable parent in real usage — the
  /// [ModelPhase.capable] fallback below only matters defensively (a
  /// malformed/orphaned chat in tests). Added for
  /// `aion-arch/changes/per-phase-tier-based-model-routing`.
  Future<ModelPhase> _phaseForChat(String chatTicketId) async {
    final chat = await _ticketRepository.getTicketById(chatTicketId);
    final inboxPurpose = chat?.inboxPurpose;
    if (inboxPurpose != null) return _phaseForInboxPurpose(inboxPurpose);

    final parentId = chat?.parentId;
    if (parentId == null) return ModelPhase.capable;
    final parent = await _ticketRepository.getTicketById(parentId);
    if (parent == null) return ModelPhase.capable;
    if (parent.type.isExecutable) return ModelPhase.execution;
    return parent.sddStage?.modelPhase ?? ModelPhase.capable;
  }

  /// Maps an Inbox-spawned chat's [InboxPurpose] to the [ModelPhase] its
  /// human-follow-up replies resolve through, per
  /// `aion-arch/changes/new-project-onboarding-inbox/design.md` §2:
  /// brain-dump/what-next-guidance/release-planning are judgment-heavy
  /// (`frontier`, the same weight as epic/story-level SDD decisions);
  /// Q&A is comparatively mechanical lookup/read-and-answer (`capable`).
  ModelPhase _phaseForInboxPurpose(InboxPurpose purpose) => switch (purpose) {
    InboxPurpose.brainDump ||
    InboxPurpose.whatNextGuidance ||
    InboxPurpose.releasePlanning => ModelPhase.frontier,
    InboxPurpose.qa => ModelPhase.capable,
  };

  /// Calls [client]'s `run` with [prompt]/[model], accumulating every
  /// `AgentTextEvent` chunk (reported to [onChunk], if given) and, on a
  /// successful `AgentDoneEvent` completion, persisting the accumulated
  /// text as one [CommentAuthorType.ai] comment (`aiModel: model.modelId`)
  /// via [commentRepo]. On failure (an `AgentErrorEvent` or a thrown
  /// exception), persists a `'Execution failed: ...'`
  /// [CommentAuthorType.ai] comment instead — previously a failed run
  /// left no trace for anyone not watching the chat live. Returns `true`
  /// if the turn completed successfully, `false` otherwise. [toolsEnabled]
  /// and [workingDirectory] opt a run into real tool access (file edits,
  /// git, bash) scoped to that directory — only `TicketsCubit`'s
  /// coding-execution path sets these; every other caller leaves them at
  /// their text-only defaults. [provider] maps a raw
  /// `AgentOverageDetectedEvent.message` into a [ConsumptionSignal] (via
  /// `AgentProvider.describeOverage`, reported to [onConsumptionSignal] if
  /// given, once per event) and a raw `AgentErrorEvent.message` into a
  /// vendor-neutral one (via `AgentProvider.normalizeErrorMessage`) before
  /// it's persisted/returned as `failureMessage` — see
  /// `aion-arch/changes/pluggable-provider-abstraction/design.md` §4.
  /// [onToolUse], if given, is called once per `AgentToolUseEvent` with
  /// the tool's name and short summary — added for
  /// `aion-arch/changes/coding-execution-reliability-and-safety` so a
  /// long-running turn has live progress visibility. Shared by
  /// [sendMessage] and `TicketsCubit._spawnStageChat`/coding-execution
  /// (`tickets_cubit.dart`) so all call sites accumulate/persist
  /// identically and can't drift apart. Captures the terminal
  /// [AgentDoneEvent]'s `inputTokens`/`outputTokens` and carries them onto
  /// whichever comment (success or hard-failure) it persists — `null`/
  /// `null` if the stream never reaches a `done` event (e.g. an
  /// [AgentErrorEvent] hard failure). Added for
  /// `aion-arch/changes/dont-spawn-new-chat-ticket-per-execution-trigger`.
  static Future<bool> runChatTurn({
    required AgentModelClient client,
    required AgentProvider provider,
    required CommentRepository commentRepo,
    required String chatTicketId,
    required String prompt,
    required AgentModelDescriptor model,
    void Function(String textSoFar)? onChunk,
    bool toolsEnabled = false,
    String? workingDirectory,
    void Function(ConsumptionSignal signal)? onConsumptionSignal,
    void Function(String toolName, String? summary)? onToolUse,
  }) async {
    final buffer = StringBuffer();
    var succeeded = true;
    String? failureMessage;
    AgentDoneEvent? doneEvent;
    try {
      final events = await client.run(
        AgentRequest(
          prompt: prompt,
          model: model.modelId,
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
          case AgentDoneEvent(:final inputTokens, :final outputTokens):
            doneEvent = AgentDoneEvent(
              inputTokens: inputTokens,
              outputTokens: outputTokens,
            );
          case AgentOverageDetectedEvent(:final message):
            onConsumptionSignal?.call(provider.describeOverage(message));
          case AgentErrorEvent(:final message):
            succeeded = false;
            failureMessage = provider.normalizeErrorMessage(message);
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
          aiModel: model.modelId,
          inputTokens: doneEvent?.inputTokens,
          outputTokens: doneEvent?.outputTokens,
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
          aiModel: model.modelId,
          inputTokens: doneEvent?.inputTokens,
          outputTokens: doneEvent?.outputTokens,
          createdAt: DateTime.now(),
        ),
      );
    }
    return succeeded;
  }
}
