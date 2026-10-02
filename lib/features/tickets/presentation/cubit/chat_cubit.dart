// presentation/cubit/chat_cubit.dart — ChatCubit business logic (presentation layer).

import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/agent_session_handle.dart';
import 'package:aion/core/contracts/agent_tool_definition.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/tickets/domain/entities/chat_turn_result.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/inbox_purpose.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/domain/repositories/comment_repository.dart';
import 'package:aion/features/tickets/domain/repositories/sdd_stage_config_repository.dart';
import 'package:aion/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_branch_tool_definitions.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_state.dart';
import 'package:aion/features/tickets/presentation/cubit/ticket_crud_tool_definitions.dart';

/// Loads and drives a single `chat`-type ticket's live conversation, via
/// [CommentRepository] (the same append-only store `CommentsCubit` uses for
/// every other ticket type — a chat ticket's comment thread already is its
/// transcript, see `AIO-1856`'s re-scoping) plus [ProviderRegistry] to resolve
/// the [AgentProvider] that generates the AI reply. Screen-scoped — provided
/// instead of `CommentsCubit` only when `ticket.type == TicketType.chat`.
/// [_ticketRepository]/[_modelRoutingRepository] are used to infer which
/// [ModelPhase] a chat belongs to (see [_phaseForChat]) so [sendMessage] can
/// resolve the phase-appropriate model/provider itself, added for `AIO-1491`.
/// [_ticketRepository] is also used by [_toolsFor] to decide which of
/// [branchTicketToolDefinition]/[closeBranchToolDefinition] a chat's next turn
/// offers — [sendMessage] resolves this itself rather than depending on
/// `TicketsCubit`, but still needs its caller to supply an `onToolCall`
/// handler (that logic lives on `TicketsCubit`, which owns ticket-mutation
/// domain logic). Added for `AIO-1118`.
class ChatCubit extends Cubit<ChatState> {
  /// Creates a [ChatCubit] backed by [_repository], [_providerRegistry],
  /// [_ticketRepository], and [_modelRoutingRepository].
  ChatCubit(
    this._repository,
    this._providerRegistry,
    this._ticketRepository,
    this._modelRoutingRepository, {
    String? sourceRootPath,
    SddStageConfigRepository? sddStageConfigRepository,
  }) : super(const ChatInitial()) {
    _sourceRootPath = sourceRootPath;
    _sddStageConfigRepository = sddStageConfigRepository;
  }

  final CommentRepository _repository;
  final ProviderRegistry _providerRegistry;
  final TicketRepository _ticketRepository;
  final ModelRoutingRepository _modelRoutingRepository;

  /// Resolves a project's per-stage display-name overrides, so
  /// [_stageOwningChat] can recognize a stage chat whose title uses an
  /// overridden name. `null` (tests, contexts with no project) means only the
  /// hardcoded names are matched. Added for `AIO-3056`.
  late final SddStageConfigRepository? _sddStageConfigRepository;

  /// The active project's checkout root, threaded through from
  /// `app_router.dart` (mirrors `InboxCubit`'s own `sourceRootPath` wiring)
  /// — `null` in tests/contexts with no project open. Used by
  /// [_isLiveSddStageChat]'s caller ([sendMessage]) to give a live
  /// SDD-stage chat's human follow-up turns the same codebase read access
  /// its auto-fired first turn gets. See `AIO-2962` and the gap this fixes.
  late final String? _sourceRootPath;
  static const _uuid = Uuid();

  /// Max gap between provider stream events before a turn is treated as
  /// stalled. Generous enough to survive one long individual tool call —
  /// tool execution does not block the event stream from eventually emitting
  /// a completion event, so the gap we guard against is a genuinely dead
  /// stream, not a slow AgentToolCallEvent.
  static const Duration turnInactivityTimeout = Duration(minutes: 3);

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
  /// model/provider via [_phaseForChat]/[_resolveModelAndProvider], then calls
  /// it via [AgentModelClient.run], emitting [ChatLoaded] with `streamingText`
  /// updated on every `AgentTextEvent` chunk, and `currentToolUse` updated on
  /// every `AgentToolUseEvent`, for live rendering. On completion, the
  /// accumulated reply is persisted as one [CommentAuthorType.ai] comment (see
  /// [runChatTurn]) and the thread is reloaded. On failure, emits [ChatError]
  /// — the human message the user sent stays persisted; nothing broken is
  /// written for the reply. [onToolCall], if given, is threaded through to
  /// [runChatTurn] as its `onToolCall` — the tools offered are resolved
  /// internally via [_toolsFor], but their actual execution logic lives on
  /// `TicketsCubit` (ticket creation, automation-confidence gating), so the
  /// caller (`TicketDetailScreen`) supplies it. Added for `AIO-1118`.
  ///
  /// Generates a fresh `runId` (`const Uuid().v4()`) for this turn, threaded
  /// through to [AgentRequest.runId] via [runChatTurn] and stored on
  /// [ChatLoaded.activeRunId] for the whole turn's duration — [cancelReply]
  /// resolves it from there. On [ChatTurnCancelled], persists
  /// [ChatTurnCancelled.accumulatedText] as one [CommentAuthorType.ai] comment
  /// if non-empty (a hard failure/success already persisted its own comment
  /// inside [runChatTurn] — only a cancelled turn needs the caller to do it),
  /// then reloads the thread and clears
  /// `streamingText`/`currentToolUse`/`activeRunId`. Added for `AIO-1400`; see
  /// its linked Documentation page, §3.
  ///
  /// This [ChatCubit] is route-scoped (see `app_router.dart`'s
  /// `/workspace/tickets/:id`), so it can be closed by navigation while a
  /// turn is still running. Every `emit` after an `await` is guarded with
  /// `if (isClosed) return;`, including inside the [runChatTurn]
  /// `onChunk`/`onToolUse` callbacks — without that guard, a closed-cubit
  /// `emit` throws, `runChatTurn`'s own generic catch reports it as an
  /// ordinary model failure, and the real accumulated reply is discarded
  /// instead of persisted. Fixed for `AIO-2933`; confirmed live during
  /// `AIO-2919`'s own follow-up-reply chat.
  ///
  /// Resolves [_isLiveSddStageChat] to decide this turn's `readOnlyTools`/
  /// `workingDirectory` — a live SDD-stage chat's human follow-up gets the
  /// same read-only codebase access (`Read`/`Grep`/`Glob`, scoped to
  /// [_sourceRootPath]) its auto-fired first turn already does, instead of
  /// silently falling back to [runChatTurn]'s text-only default. Discovered
  /// live via AIO-2949's own Propose-stage chat.
  Future<void> sendMessage({
    required String chatTicketId,
    required String content,
    Future<Map<String, dynamic>> Function(
      String toolCallId,
      String toolName,
      Map<String, dynamic> arguments,
      AgentSessionHandle? session,
    )?
    onToolCall,
  }) async {
    final List<TicketComment> afterHuman;
    try {
      // Diagnostic logging: record the human message persist attempt.
      debugPrint(
        '[ChatCubit.sendMessage] persisting human comment '
        '(chatTicketId=$chatTicketId, contentLength=${content.length})',
      );
      await _repository.addComment(
        TicketComment(
          id: '',
          ticketId: chatTicketId,
          content: content,
          authorType: CommentAuthorType.human,
          createdAt: DateTime.now(),
        ),
      );
      debugPrint(
        '[ChatCubit.sendMessage] human comment persisted successfully',
      );
      afterHuman = await _repository.getCommentsForTicket(chatTicketId);
    } catch (e) {
      // The human message itself failed to persist — rethrow (after the
      // existing internal-state emit) so the caller (`_sendComment`'s
      // await-then-clear) can detect this specific failure and retain the
      // user's typed text, per AIO-2998's "failure can't silently swallow
      // the user's typed text" requirement. Distinct from a downstream
      // model-turn failure below, where the human message DID persist and
      // clearing the compose field is the correct behavior.
      if (isClosed) return;
      emit(ChatError(e.toString()));
      rethrow;
    }

    if (isClosed) return;
    emit(ChatLoaded(afterHuman));

    try {
      final phase = await _phaseForChat(chatTicketId);
      final (model, provider) = await _resolveModelAndProvider(phase);
      final runId = _uuid.v4();
      if (isClosed) return;
      // Emitted before the run itself starts (not just from the first
      // onChunk/onToolUse below) so a cancel button has something to act
      // on even before the model's first token streams in.
      emit(ChatLoaded(afterHuman, activeRunId: runId));

      // Tracks the most recent onChunk text so onToolUse can carry it
      // forward instead of blanking it — a tool call fired mid-turn
      // (after some text already streamed) would otherwise reset
      // ChatLoaded.streamingText to null via its constructor default.
      String? latestStreamingText;
      final readOnlyTools = await _isLiveSddStageChat(chatTicketId);
      final result = await runChatTurn(
        client: provider.client,
        provider: provider,
        commentRepo: _repository,
        ticketRepository: _ticketRepository,
        chatTicketId: chatTicketId,
        prompt: buildContinuationPrompt(afterHuman, content),
        model: model,
        runId: runId,
        onChunk: (textSoFar) {
          latestStreamingText = textSoFar;
          // The screen (and this cubit) may have been closed by
          // navigation while this turn was still streaming — emitting
          // into a closed cubit throws `StateError('Cannot emit new
          // states after calling close')`, which runChatTurn's own
          // generic catch then reports as an ordinary model failure,
          // discarding the real accumulated reply instead of persisting
          // it. Guarding here (matching this codebase's established
          // `if (isClosed) return;` idiom, e.g.
          // `TicketsCubit._loadWorkflowStatuses`) lets the `await for`
          // loop finish normally so runChatTurn's own success path
          // still persists the full reply. Added for `AIO-2933`.
          if (isClosed) return;
          emit(
            ChatLoaded(
              afterHuman,
              streamingText: textSoFar,
              activeRunId: runId,
            ),
          );
        },
        onToolUse: (toolName, summary) {
          if (isClosed) return;
          emit(
            ChatLoaded(
              afterHuman,
              streamingText: latestStreamingText,
              currentToolUse: summary == null
                  ? 'Running $toolName...'
                  : 'Running $toolName: $summary...',
              activeRunId: runId,
            ),
          );
        },
        tools: await _toolsFor(chatTicketId),
        onToolCall: onToolCall,
        readOnlyTools: readOnlyTools,
        workingDirectory: readOnlyTools ? _sourceRootPath : null,
      );

      switch (result) {
        case ChatTurnSuccess():
          final afterReply = await _repository.getCommentsForTicket(
            chatTicketId,
          );
          if (isClosed) return;
          emit(ChatLoaded(afterReply));
        case ChatTurnFailure():
          if (isClosed) return;
          emit(ChatError('The model run failed. Please try again.'));
          emit(ChatLoaded(afterHuman));
        case ChatTurnCancelled(:final accumulatedText):
          if (accumulatedText.isNotEmpty) {
            await _repository.addComment(
              TicketComment(
                id: '',
                ticketId: chatTicketId,
                content: accumulatedText,
                authorType: CommentAuthorType.ai,
                aiModel: model.modelId,
                createdAt: DateTime.now(),
              ),
            );
          }
          final afterCancel = await _repository.getCommentsForTicket(
            chatTicketId,
          );
          if (isClosed) return;
          emit(ChatLoaded(afterCancel));
      }
    } catch (e) {
      if (isClosed) return;
      emit(ChatError(e.toString()));
    }
  }

  /// Maximum characters of prior-thread history [buildContinuationPrompt]
  /// replays into a follow-up turn, excluding the thread's opening comment
  /// (always kept) and the new message itself.
  static const int continuationHistoryBudget = 60000;

  /// Builds the prompt for a human follow-up turn in an existing chat.
  /// Every [AgentModelClient.run] starts a fresh, non-resumed model session
  /// (see [runChatTurn]), so sending only [newMessage] leaves the model with
  /// no memory of the thread — including the opening instructions a stage
  /// chat's gate depends on. [thread] is the chat's comments *including* the
  /// just-persisted human [newMessage] as its latest entry; the earlier ones
  /// are replayed as a labelled transcript ahead of [newMessage]. A thread
  /// with nothing before [newMessage] returns it unchanged.
  ///
  /// The opening comment is always kept; beyond it, the oldest comments are
  /// dropped first once the transcript exceeds [continuationHistoryBudget],
  /// with a marker noting how many were omitted. Persisted
  /// `'Execution failed: ...'` AI comments are skipped as noise. Added to fix
  /// missing session continuity across stage-chat follow-up replies.
  @visibleForTesting
  static String buildContinuationPrompt(
    List<TicketComment> thread,
    String newMessage,
  ) {
    final ordered = [...thread]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // Drop the just-persisted new message itself (the latest human entry).
    final lastHuman = ordered.lastIndexWhere(
      (c) => c.authorType == CommentAuthorType.human,
    );
    if (lastHuman != -1 && ordered[lastHuman].content == newMessage) {
      ordered.removeAt(lastHuman);
    }
    final history = ordered
        .where(
          (c) =>
              !(c.authorType == CommentAuthorType.ai &&
                  c.content.startsWith('Execution failed:')),
        )
        .toList();
    if (history.isEmpty) return newMessage;

    String label(TicketComment c) => switch (c.authorType) {
      CommentAuthorType.human => 'User',
      CommentAuthorType.ai => 'Assistant',
      CommentAuthorType.system => 'Instructions',
    };
    String render(TicketComment c) => '[${label(c)}]\n${c.content}';

    final first = history.first;
    final rest = history.sublist(1);
    var used = 0;
    var keepFrom = rest.length;
    while (keepFrom > 0) {
      final cost = render(rest[keepFrom - 1]).length;
      if (used + cost > continuationHistoryBudget) break;
      used += cost;
      keepFrom--;
    }
    final omitted = keepFrom;

    final buffer = StringBuffer()
      ..writeln(
        'This is a continuing conversation. The earlier messages are '
        'reproduced below, oldest first, so you have the full context.',
      )
      ..writeln()
      ..writeln(render(first));
    if (omitted > 0) {
      buffer
        ..writeln()
        ..writeln('[... $omitted earlier message(s) omitted ...]');
    }
    for (final c in rest.sublist(keepFrom)) {
      buffer
        ..writeln()
        ..writeln(render(c));
    }
    buffer
      ..writeln()
      ..writeln('The user has just sent this new message — reply to it:')
      ..writeln()
      ..write(newMessage);
    return buffer.toString();
  }

  /// Cancels [chatTicketId]'s currently in-flight reply, if any — no-op if
  /// [state] isn't [ChatLoaded] or [ChatLoaded.activeRunId] is `null`.
  /// Resolves the same provider [sendMessage] would (via [_phaseForChat]/
  /// [_resolveModelAndProvider]) and calls [AgentModelClient.cancel] with the
  /// active run's id. Added for `AIO-1400`; see its linked Documentation page,
  /// §3.
  Future<void> cancelReply(String chatTicketId) async {
    final current = state;
    if (current is! ChatLoaded) return;
    final runId = current.activeRunId;
    if (runId == null) return;
    final phase = await _phaseForChat(chatTicketId);
    final (_, provider) = await _resolveModelAndProvider(phase);
    provider.client.cancel(runId);
  }

  /// Resolves [phase] to its currently configured [AgentModelDescriptor] (via
  /// [_modelRoutingRepository]) and that model's [AgentProvider] (via
  /// [_providerRegistry]). Shared helper so every model call site resolves the
  /// pair identically — see `AIO-1544` §7.
  Future<(AgentModelDescriptor, AgentProvider)> _resolveModelAndProvider(
    ModelPhase phase,
  ) async {
    final model = await _modelRoutingRepository.getModelForPhase(phase);
    final provider = _providerRegistry.providerById(model.providerId);
    return (model, provider);
  }

  /// Infers which [ModelPhase] governs [chatTicketId]'s model calls, via two
  /// independent resolution paths. First, and parent-independent: if the
  /// chat's own `Ticket.inboxPurpose` is set (an Inbox-spawned chat, see
  /// `AIO-1300` §1.3), resolve directly from [_phaseForInboxPurpose] and
  /// return — Inbox chats are deliberately parentless (see
  /// `TicketsCubit.updateTicketParent`'s reparent guard), so the parent-walk
  /// below would otherwise always hit its defensive fallback for them.
  /// Otherwise, fall back to the original parent-based inference: an
  /// `epic`/`story`/`bug` parent with a live `Ticket.sddStage` resolves via
  /// [SddStageModelPhase.modelPhase] — a `bug` parent is checked for this
  /// first, ahead of the `isExecutable` check below, since `AIO-2898` gave
  /// `bug` its own SDD cycle (see `SddStage.applying`) and a mid-cycle chat
  /// reply (Explore/Propose/Verify) is a judgment call that needs
  /// [ModelPhase.frontier], not the weaker [ModelPhase.execution] tier a
  /// Task's plain-status-flip execution shortcut resolves to (`AIO-2913`). A
  /// `bug` parent with no `sddStage` yet (still on the older plain-execution
  /// shortcut) or already `archived` falls back to [ModelPhase.execution],
  /// matching a Task parent (see `TicketTypeHierarchy.isExecutable`).
  /// Every non-Inbox chat ticket in the app is spawned exclusively by
  /// `TicketsCubit._spawnStageChat`/`_runCodingExecution` (the only other
  /// `createTicket` call sites for `TicketType.chat` in the codebase), so such
  /// a chat always has a resolvable parent in real usage — the
  /// [ModelPhase.capable] fallback below only matters defensively (a
  /// malformed/orphaned chat in tests). Added for `AIO-1491`.
  Future<ModelPhase> _phaseForChat(String chatTicketId) async {
    final chat = await _ticketRepository.getTicketById(chatTicketId);
    final inboxPurpose = chat?.inboxPurpose;
    if (inboxPurpose != null) return _phaseForInboxPurpose(inboxPurpose);

    final parentId = chat?.parentId;
    if (parentId == null) return ModelPhase.capable;
    final parent = await _ticketRepository.getTicketById(parentId);
    if (parent == null) return ModelPhase.capable;
    // The stage the chat itself belongs to wins over wherever the parent has
    // since moved: a follow-up in a Proposed chat is still a Proposed-stage
    // judgment call after the parent reaches Design Brief or Archived
    // (`AIO-3056`). A chat whose title names no stage (a Coding Execution
    // chat, a stage renamed after the chat was created) falls through to the
    // parent-based inference below, unchanged.
    if (parent.type == TicketType.epic ||
        parent.type == TicketType.story ||
        parent.type == TicketType.bug) {
      final ownStage = await _stageOwningChat(chat!);
      if (ownStage != null) return ownStage.modelPhase;
    }
    if (parent.type == TicketType.bug) {
      final stage = parent.sddStage;
      if (stage == null || stage == SddStage.archived) {
        return ModelPhase.execution;
      }
      return stage.modelPhase;
    }
    if (parent.type.isExecutable) return ModelPhase.execution;
    return parent.sddStage?.modelPhase ?? ModelPhase.capable;
  }

  /// The [SddStage] [chat] was spawned for, read back from its title's
  /// `"<stage name> — "` prefix (`TicketsCubit._createStageChat` writes it) —
  /// matching either the stage's project display-name override or its
  /// hardcoded name — or `null` when the title names no stage (e.g. a
  /// `Coding Execution — ` chat, or a stage renamed after this chat was
  /// created). Added for `AIO-3056`.
  Future<SddStage?> _stageOwningChat(Ticket chat) async {
    for (final stage in SddStage.values) {
      final override = await _sddStageConfigRepository?.getDisplayNameOverride(
        stage,
      );
      for (final name in {?override, stage.hardcodedPresentName}) {
        if (chat.title.startsWith('$name — ')) return stage;
      }
    }
    return null;
  }

  /// Tools offered on [chatTicketId]'s next turn, mirroring [_phaseForChat]'s
  /// shape rather than depending on `TicketsCubit`:
  /// [branchTicketToolDefinition] whenever [chatTicketId] isn't itself
  /// parented by a chat (so a branch can't be branched further — see
  /// `TicketsCubit._canBranch`'s depth-cap check, which this mirrors at
  /// registration time so the model is never even offered a tool it would
  /// immediately have declined), [closeBranchToolDefinition] whenever it *is*
  /// parented by a chat, plus [createTicketToolDefinition]/
  /// [addLinkToolDefinition] unconditionally — mirrors
  /// `TicketsCubit._toolsFor`'s combined-list shape (tickets_cubit.dart)
  /// exactly, so create_ticket/add_link work identically from an ordinary
  /// human-initiated chat turn as they already did from SDD-stage and
  /// coding-execution chat turns. `AIO-2108` extended `TicketsCubit._toolsFor`
  /// with these two tools but missed this separate same-named method —
  /// chat_cubit.dart never picked up that change (confirmed via `git log`) —
  /// so an ordinary chat compose turn silently never offered them, and a
  /// request to create/link a ticket produced a model-fabricated "done" reply
  /// instead of ever calling a real tool. Fixed as an ad hoc bug fix, found
  /// during a live `AutomationConfidence` QA sweep. Added for `AIO-1118`; see
  /// its linked Documentation page, §6.
  Future<List<AgentToolDefinition>> _toolsFor(String chatTicketId) async {
    final chat = await _ticketRepository.getTicketById(chatTicketId);
    final parentId = chat?.parentId;
    final branchOrCloseTool = parentId == null
        ? branchTicketToolDefinition
        : (await _ticketRepository.getTicketById(parentId))?.type ==
              TicketType.chat
        ? closeBranchToolDefinition
        : branchTicketToolDefinition;
    return [
      branchOrCloseTool,
      createTicketToolDefinition,
      addLinkToolDefinition,
    ];
  }

  /// Whether [chatTicketId]'s next follow-up turn should get read-only
  /// codebase access (`Read`/`Grep`/`Glob`, scoped to [_sourceRootPath]) —
  /// true whenever its parent is an epic/story/bug currently sitting in a
  /// live SDD stage other than [SddStage.applying]/[SddStage.archived].
  /// `applying` never spawns a stage chat via this mechanism at all — it
  /// fires coding-execution directly instead (which runs in an isolated
  /// worktree, not [_sourceRootPath], and is out of scope here); `archived`
  /// has no stage chat either. Mirrors
  /// `TicketsCubit._runStageChatTurn`'s own `readOnlyTools:
  /// !stageToolsEnabled` grant for a plain (non-attachment) stage chat's
  /// auto-fired first turn — before this, a human's follow-up reply in the
  /// very same chat silently fell back to [runChatTurn]'s text-only
  /// default, discovered live when AIO-2949's own Propose-stage chat could
  /// not ground its decomposition in the real codebase. Deliberately does
  /// not attempt to replicate `_runStageChatTurn`'s
  /// `SkillAttachmentKind.delegatedSkill` case — that chat's worktree is a
  /// temp directory that may already be removed by the time a human
  /// replies, so those chats keep today's text-only follow-up behavior.
  /// See `AIO-2962`.
  Future<bool> _isLiveSddStageChat(String chatTicketId) async {
    final chat = await _ticketRepository.getTicketById(chatTicketId);
    final parentId = chat?.parentId;
    if (parentId == null) return false;
    final parent = await _ticketRepository.getTicketById(parentId);
    if (parent == null) return false;
    if (parent.type != TicketType.epic &&
        parent.type != TicketType.story &&
        parent.type != TicketType.bug) {
      return false;
    }
    final stage = parent.sddStage;
    if (stage == null) return false;
    return stage != SddStage.applying && stage != SddStage.archived;
  }

  /// Maps an Inbox-spawned chat's [InboxPurpose] to the [ModelPhase] its
  /// human-follow-up replies resolve through, per `AIO-1300` §2:
  /// brain-dump/what-next-guidance/release-planning are judgment-heavy
  /// (`frontier`, the same weight as epic/story-level SDD decisions); Q&A is
  /// comparatively mechanical lookup/read-and-answer (`capable`).
  ModelPhase _phaseForInboxPurpose(InboxPurpose purpose) => switch (purpose) {
    InboxPurpose.brainDump ||
    InboxPurpose.whatNextGuidance ||
    InboxPurpose.releasePlanning => ModelPhase.frontier,
    InboxPurpose.qa => ModelPhase.capable,
  };

  /// Calls [client]'s `run` with [prompt]/[model], accumulating every
  /// `AgentTextEvent` chunk (reported to [onChunk], if given) and, on a
  /// successful `AgentDoneEvent` completion, persisting the accumulated text
  /// as one [CommentAuthorType.ai] comment (`aiModel: model.modelId`) via
  /// [commentRepo]. On failure (an `AgentErrorEvent` or a thrown exception),
  /// persists a `'Execution failed: ...'` [CommentAuthorType.ai] comment
  /// instead — previously a failed run left no trace for anyone not watching
  /// the chat live. Returns `true` if the turn completed successfully, `false`
  /// otherwise. [toolsEnabled] and [workingDirectory] opt a run into real tool
  /// access (file edits, git, bash) scoped to that directory — only
  /// `TicketsCubit`'s coding-execution path sets these. [readOnlyTools], when
  /// [toolsEnabled] is `false`, grants the narrower Read/Grep/Glob set
  /// (still scoped to [workingDirectory]) — a live SDD-stage chat's turns
  /// set this (both the auto-fired first turn, via
  /// `TicketsCubit._runStageChatTurn`, and a human's follow-up reply, via
  /// [sendMessage]/[_isLiveSddStageChat]) so they can actually investigate
  /// the codebase without gaining Bash/Edit/Write; every other caller
  /// leaves both at their text-only defaults. See `AIO-2962`. [provider]
  /// maps a raw
  /// `AgentOverageDetectedEvent.message` into a [ConsumptionSignal] (via
  /// `AgentProvider.describeOverage`, reported to [onConsumptionSignal] if
  /// given, once per event) and a raw `AgentErrorEvent.message` into a
  /// vendor-neutral one (via `AgentProvider.normalizeErrorMessage`) before
  /// it's persisted/returned as `failureMessage` — see `AIO-1544` §4.
  /// [onToolUse], if given, is called once per `AgentToolUseEvent` with the
  /// tool's name and short summary — added for `AIO-506` so a long-running
  /// turn has live progress visibility. Shared by [sendMessage] and
  /// `TicketsCubit._spawnStageChat`/coding-execution (`tickets_cubit.dart`) so
  /// all call sites accumulate/persist identically and can't drift apart.
  /// Captures the terminal [AgentDoneEvent]'s `inputTokens`/`outputTokens` and
  /// carries them onto whichever comment (success or hard-failure) it persists
  /// — `null`/ `null` if the stream never reaches a `done` event (e.g. an
  /// [AgentErrorEvent] hard failure). Added for `AIO-833`.
  /// [tools]/[onToolCall] are passed straight through into the underlying
  /// [AgentRequest] — empty/`null` by default, so every call site that
  /// predates `AIO-1118` keeps today's behavior unchanged. An
  /// `AgentToolCallEvent` the run emits is reported through [onToolUse] too
  /// (with a `null` summary), the same live-progress channel
  /// `AgentToolUseEvent` already uses — the actual execution/result round trip
  /// happens inside [client] via [onToolCall], not here. [onToolCall]'s 4th
  /// parameter ([AgentSessionHandle]?) is a pure passthrough into
  /// [AgentRequest.onToolCall] — this method doesn't inspect it itself.
  ///
  /// [runId], if given, is threaded through to [AgentRequest.runId] so a
  /// caller can later cancel this exact turn via [AgentModelClient.cancel].
  /// `null` (the default) for a caller with no cancellation UI wired to it. On
  /// an [AgentCancelledEvent], returns [ChatTurnCancelled] carrying whatever
  /// text had accumulated so far and persists nothing itself — unlike the
  /// success/failure paths below, a cancelled turn's caller decides for itself
  /// whether/how to persist the partial text (see
  /// [sendMessage]/`TicketsCubit._runCodingExecution`). Added for `AIO-1400`;
  /// see its linked Documentation page, §3.
  ///
  /// [ticketRepository] is used to automatically log this turn's elapsed
  /// wall-clock time against [chatTicketId]'s parent ticket, via
  /// [_logElapsedTime] — called unconditionally as the last step before
  /// returning, regardless of terminal outcome (success, failure, or
  /// cancellation). This replaces the model-self-reported `log_time` tool call
  /// as `timeSpent`'s source of truth. Added for `AIO-148`.
  ///
  /// @returns a [ChatTurnResult]: [ChatTurnSuccess] or [ChatTurnFailure]
  /// once this method has already persisted the matching comment itself,
  /// or [ChatTurnCancelled] with nothing persisted.
  static Future<ChatTurnResult> runChatTurn({
    required AgentModelClient client,
    required AgentProvider provider,
    required CommentRepository commentRepo,
    required TicketRepository ticketRepository,
    required String chatTicketId,
    required String prompt,
    required AgentModelDescriptor model,
    String? runId,
    void Function(String textSoFar)? onChunk,
    bool toolsEnabled = false,
    bool readOnlyTools = false,
    String? workingDirectory,
    void Function(ConsumptionSignal signal)? onConsumptionSignal,
    void Function(String toolName, String? summary)? onToolUse,
    List<AgentToolDefinition> tools = const [],
    Future<Map<String, dynamic>> Function(
      String toolCallId,
      String toolName,
      Map<String, dynamic> arguments,
      AgentSessionHandle? session,
    )?
    onToolCall,
    Duration? inactivityTimeout,
  }) async {
    final startedAt = DateTime.now();
    final buffer = StringBuffer();
    var succeeded = true;
    var cancelled = false;
    String? failureMessage;
    AgentDoneEvent? doneEvent;
    try {
      final events = await client.run(
        AgentRequest(
          prompt: prompt,
          model: model.modelId,
          toolsEnabled: toolsEnabled,
          readOnlyTools: readOnlyTools,
          workingDirectory: workingDirectory,
          tools: tools,
          onToolCall: onToolCall,
          runId: runId,
        ),
      );
      final eventStream = inactivityTimeout != null
          ? events.timeout(inactivityTimeout)
          : events;
      await for (final event in eventStream) {
        switch (event) {
          case AgentTextEvent(:final text):
            buffer.write(text);
            onChunk?.call(buffer.toString());
          case AgentToolUseEvent(:final toolName, :final summary):
            onToolUse?.call(toolName, summary);
          case AgentToolCallEvent(:final toolName):
            onToolUse?.call(toolName, null);
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
          case AgentCancelledEvent():
            cancelled = true;
        }
      }
    } catch (e) {
      succeeded = false;
      failureMessage = e.toString();
    }

    final ChatTurnResult result;
    if (cancelled) {
      result = ChatTurnCancelled(buffer.toString());
    } else if (succeeded && buffer.isNotEmpty) {
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
      result = const ChatTurnSuccess();
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
      result = const ChatTurnFailure();
    } else {
      // succeeded but buffer empty — a turn with only tool calls, no
      // text: no comment persisted, ChatTurnSuccess() returned, exactly
      // as before this method had a single trailing return.
      result = const ChatTurnSuccess();
    }

    await _logElapsedTime(ticketRepository, chatTicketId, startedAt);
    return result;
  }

  /// Logs [chatTicketId]'s parent ticket's elapsed time for a turn that
  /// started at [startedAt], via [TicketRepository.addTimeSpent]. No-ops
  /// silently if [chatTicketId] has no resolvable parent (e.g. an
  /// Inbox-spawned chat) — mirrors the removed `log_time` tool's former "No
  /// ticket to log time against" guard. Always logs at least 1 minute
  /// (ceiling-rounded) for any turn that reaches this point, regardless of
  /// terminal outcome — a failed or cancelled turn still consumed real
  /// wall-clock time. Added for `AIO-148`; replaces the model-self-reported
  /// `log_time` tool call as `timeSpent`'s source of truth — see that change's
  /// proposal.md for why.
  static Future<void> _logElapsedTime(
    TicketRepository ticketRepository,
    String chatTicketId,
    DateTime startedAt,
  ) async {
    final chat = await ticketRepository.getTicketById(chatTicketId);
    final parentId = chat?.parentId;
    if (parentId == null) return;
    final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
    final minutes = max(1, (elapsedSeconds / 60).ceil());
    await ticketRepository.addTimeSpent(parentId, minutes);
  }
}
