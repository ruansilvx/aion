// presentation/screens/ticket_detail_screen.dart — Ticket detail screen and comment widgets (presentation layer).

import 'dart:async';

import 'package:flutter/material.dart'
    show Material, MaterialType, TextField, InputDecoration;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/data/services/active_ticket_view_registry.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_state.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/comments_state.dart';
import 'package:aion/features/tickets/presentation/cubit/pending_tool_proposal.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:aion/features/tickets/presentation/widgets/chat_compose_field.dart';
import 'package:aion/features/tickets/presentation/widgets/chat_transcript_pane.dart';
import 'package:aion/features/tickets/presentation/widgets/comment_author_avatar.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_metadata_section.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_overflow_menu.dart';

/// The `/tickets/:id` route. [TicketsCubit] is read from the root-level
/// provider; [CommentsCubit]/[ChatCubit] are provided per-route by
/// [appRouter](../../../../core/routing/app_router.dart) since they're
/// screen-scoped. Layout splits on `ticket.type`:
/// - **`chat` tickets** render no screen-level header at all — a single
///   [ChatTranscriptPane] fills the body, whose own collapsing header
///   (metadata content collapsing into a compact `ChatMetaHeader` as
///   the transcript scrolls) replaces it — plus a [ChatComposeField]
///   pinned at the bottom. See
///   `aion-arch/changes/chat-transcript-ux-redesign/design.md` §8.
/// - **Every other type** keeps the original layout: a screen-level
///   [AppHeader], [TicketMetadataSection] (ticket meta, and for
///   `epic`/`story` an SDD-stage section, for `task` a coding-execution
///   section) inside a `SingleChildScrollView`, a plain [CommentTile]
///   thread via [CommentsCubit], and a single-line pill compose row.
///   For `resource`/`bug` tickets specifically, also renders two
///   Documentation-section sections — Linked Tickets and Backlinks —
///   populated via [TicketsCubit.loadDocumentRelations].
/// `page` tickets never reach either layout: since
/// `page-content-markdown-editor`, a loaded `page` ticket immediately
/// redirects to `PageDetailScreen` via `/workspace/pages/:id` (see the
/// `TicketDetailLoaded` branch below).
///
/// The top-level [BlocListener]'s [TicketDetailLoaded] branch also
/// tracks [_wasAdvancingStageForCurrentChat] so a `chat` ticket that is
/// itself the live target of a [TicketsCubit] stage-advance spawn
/// re-loads its [ChatCubit] messages the instant that spawn's reply
/// lands — the reply is posted through a static helper this screen's
/// own [ChatCubit] instance never observes directly. Classified
/// [TicketsError] toasts (`invalidParent`/`codingExecutionBlocked`/
/// `executionBudgetOverageDetected`/etc.) are no longer shown from this
/// screen's listener at all — they're now handled app-wide by
/// `WorkspaceNavShell`. Added for
/// `aion-arch/changes/board-execution-indicators-and-notifications`.
class TicketDetailScreen extends StatefulWidget {
  /// Creates a [TicketDetailScreen] for the ticket with internal id [ticketId].
  const TicketDetailScreen({super.key, required this.ticketId});

  /// Internal UUID of the ticket to display.
  final String ticketId;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  final _commentController = TextEditingController();

  /// The human-readable `ticketId` this screen registered as "active"
  /// with [ActiveTicketViewRegistry], once its [TicketDetailLoaded]
  /// state arrives (unknown before then). `null` on mobile/web, where
  /// [ActiveTicketViewRegistry] isn't provided at all (see
  /// `WorkspaceShell`) — reads are guarded with [_tryReadRegistry]
  /// rather than assuming desktop.
  String? _registeredTicketId;

  /// The internal ticket id [loadDocumentRelations] was last triggered
  /// for — guards against re-triggering on every re-emitted
  /// [TicketDetailLoaded] (that method itself re-emits
  /// [TicketDetailLoaded] once it resolves, which would otherwise loop).
  String? _relationsLoadedForId;

  /// The most recently loaded ticket, updated by the top-level
  /// [BlocListener]'s [TicketDetailLoaded] branch — used by
  /// [_sendComment] to decide whether to post through [ChatCubit] or
  /// [CommentsCubit], since the composer row sits outside the ticket
  /// [BlocBuilder]'s subtree.
  Ticket? _currentTicket;

  /// The persisted SDD-stage-triggering [AutomationConfidence], loaded
  /// once per screen instance (no polling) — see
  /// `aion-arch/changes/sdd-ticket-execution/design.md`'s
  /// "Precondition check on ticket-detail load" section.
  AutomationConfidence? _automationConfidence;

  /// `'<ticketId>:<sddStage>'` key of the last ticket+stage this screen
  /// already auto-advanced, so a rebuild doesn't re-trigger
  /// [TicketsCubit.advanceSddStage] repeatedly while
  /// [_automationConfidence] is [AutomationConfidence.auto] and the
  /// precondition remains (momentarily) satisfied.
  String? _autoAdvancedKey;

  /// Whether a [TicketsCubit.retryDesignSync] call is currently in
  /// flight — drives `_RetryValidationButton`'s disabled/spinning state
  /// (design.md §4.3) so a second tap can't fire a concurrent retry
  /// while the first is still running. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  bool _retryingDesignSync = false;

  /// Whether the top-level [BlocListener]'s most recently seen
  /// [TicketDetailLoaded] had `isAdvancingStage: true` for the
  /// currently-viewed `chat` ticket — tracked so the listener can detect
  /// the `true` → `false` transition (the spawned stage-advance turn
  /// finishing) and re-trigger [ChatCubit.loadMessages], since
  /// `TicketsCubit._runStageChatTurn` posts the reply through a static
  /// helper this screen's own [ChatCubit] instance never observes. Reset
  /// implicitly whenever a different ticket loads (its id doesn't match
  /// [_currentTicket] anymore, so the flip check is naturally scoped to
  /// the ticket currently on screen). Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  bool _wasAdvancingStageForCurrentChat = false;

  /// Calls [TicketsCubit.retryDesignSync], toggling [_retryingDesignSync]
  /// around the call so `_RetryValidationButton` can show its in-flight
  /// state and ignore further taps until this one resolves.
  Future<void> _retryDesignSync(Ticket designSyncChat) async {
    if (_retryingDesignSync) return;
    setState(() => _retryingDesignSync = true);
    try {
      await context.read<TicketsCubit>().retryDesignSync(designSyncChat);
    } finally {
      if (mounted) setState(() => _retryingDesignSync = false);
    }
  }

  @override
  void initState() {
    super.initState();
    context.read<TicketsCubit>().getTicketById(widget.ticketId);
    context.read<CommentsCubit>().loadComments(widget.ticketId);
    context.read<ChatCubit>().loadMessages(widget.ticketId);
    unawaited(
      context
          .read<AutomationSettingsRepository>()
          .getConfidence(AutomationContext.sddStage)
          .then((confidence) {
            if (mounted) setState(() => _automationConfidence = confidence);
          }),
    );
  }

  /// Calls [TicketsCubit.advanceSddStage] once for [ticket]'s current
  /// stage when [_automationConfidence] is [AutomationConfidence.auto]
  /// and [canAdvance] is `true`, guarded by [_autoAdvancedKey] so a
  /// rebuild before the resulting state change lands doesn't fire it
  /// again for the same ticket+stage.
  void _maybeAutoAdvanceSddStage(Ticket ticket, bool canAdvance) {
    if (_automationConfidence != AutomationConfidence.auto || !canAdvance) {
      return;
    }
    final key = '${ticket.id}:${ticket.sddStage?.name}';
    if (_autoAdvancedKey == key) return;
    _autoAdvancedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<TicketsCubit>().advanceSddStage(ticket));
    });
  }

  /// Calls [TicketsCubit.advanceSddStage] for an explicit gated/manual
  /// "Advance" tap (or a `_StageAdvanceFailureBanner` retry, which reuses
  /// this same handler — see `TicketMetadataSection`'s
  /// `onRetryStageAdvance` wiring), then navigates to the spawned chat
  /// ticket once it exists — an intentional user action, unlike
  /// [_maybeAutoAdvanceSddStage]'s passive auto-advance, which never
  /// yanks the user off the screen they're already viewing. Since
  /// `aion-arch/changes/board-execution-indicators-and-notifications`,
  /// [TicketsCubit.advanceSddStage] resolves once the chat ticket is
  /// created, **not** once its first AI reply lands — the destination
  /// screen shows a "Waiting for reply…" indicator (see
  /// `ChatTranscriptPane`) until that reply arrives.
  Future<void> _advanceSddStage(Ticket ticket) async {
    final chatId = await context.read<TicketsCubit>().advanceSddStage(ticket);
    if (chatId != null && mounted) {
      context.go('/workspace/tickets/$chatId');
    }
  }

  @override
  void dispose() {
    final registeredId = _registeredTicketId;
    if (registeredId != null) {
      final registry = _tryReadRegistry(context);
      if (registry?.activeTicketId.value == registeredId) {
        registry!.activeTicketId.value = null;
      }
    }
    _commentController.dispose();
    super.dispose();
  }

  /// [ActiveTicketViewRegistry] is only provided on desktop with a
  /// resolved project directory (see `WorkspaceShell`) — `null` on
  /// mobile/web rather than a thrown `ProviderNotFoundException`.
  ActiveTicketViewRegistry? _tryReadRegistry(BuildContext context) {
    try {
      return context.read<ActiveTicketViewRegistry>();
    } catch (_) {
      return null;
    }
  }

  void _registerActiveTicket(String ticketId) {
    if (_registeredTicketId == ticketId) return;
    final registry = _tryReadRegistry(context);
    if (registry == null) return;
    registry.activeTicketId.value = ticketId;
    _registeredTicketId = ticketId;
  }

  /// Whether [ticket] should show the sync badge/repair banner: a
  /// `resource` type (the only type still rendered by this screen — see
  /// the class doc comment), **and** sync tracking is actually active
  /// (desktop with a resolved project directory — [ActiveTicketViewRegistry]
  /// presence is used as that signal, rather than assuming desktop).
  /// Without the second check, a `resource` ticket on mobile/web would
  /// show a "SYNCED" badge implying a sync mechanism that doesn't exist
  /// there at all.
  bool _isSyncable(Ticket ticket) {
    if (ticket.type != TicketType.resource) {
      return false;
    }
    return _tryReadRegistry(context) != null;
  }

  /// Posts [_commentController]'s text via [ChatCubit.sendMessage] when
  /// [_currentTicket] is a `chat` ticket, or [CommentsCubit.addComment]
  /// otherwise. The model is resolved per-phase by
  /// `ChatCubit.sendMessage` itself; see `providers.md`. The chat path
  /// wires `onToolCall` to [TicketsCubit.handleChatToolCall], bound to
  /// [_currentTicket] — `ChatCubit` resolves which tool(s) the turn
  /// offers itself (see [ChatCubit.sendMessage]'s dartdoc) but can't
  /// execute a `branch_ticket`/`close_branch` call itself, since that
  /// logic lives on [TicketsCubit]. Added for
  /// `aion-arch/changes/mid-task-chat-branching`.
  void _sendComment() {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;
    final chat = _currentTicket;
    if (chat?.type == TicketType.chat) {
      context.read<ChatCubit>().sendMessage(
        chatTicketId: widget.ticketId,
        content: content,
        onToolCall: (toolCallId, toolName, arguments) => context
            .read<TicketsCubit>()
            .handleChatToolCall(chat!, toolCallId, toolName, arguments),
      );
    } else {
      context.read<CommentsCubit>().addComment(
        ticketId: widget.ticketId,
        content: content,
      );
    }
    _commentController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return BlocListener<TicketsCubit, TicketsState>(
      listener: (context, state) {
        if (state is TicketTrashed) {
          context.go('/workspace/tickets');
        } else if (state is TicketDetailLoaded) {
          final ticket = state.ticket;
          if (ticket.type == TicketType.page) {
            // `page` tickets moved to their own module in
            // page-content-markdown-editor — bounce a stale
            // `/workspace/tickets/:id` link to the new route instead of
            // rendering the (no-longer-applicable) page UI here.
            context.go(ticketDetailRoute(ticket));
            return;
          }
          // A stage-advance turn just finished for the chat ticket
          // currently on screen (see _wasAdvancingStageForCurrentChat's
          // dartdoc) — re-load its messages so the real reply replaces
          // the "Waiting for reply…" indicator.
          if (ticket.type == TicketType.chat &&
              ticket.id == _currentTicket?.id &&
              _wasAdvancingStageForCurrentChat &&
              !state.isAdvancingStage) {
            context.read<ChatCubit>().loadMessages(ticket.id);
          }
          _wasAdvancingStageForCurrentChat =
              ticket.type == TicketType.chat && state.isAdvancingStage;
          _currentTicket = ticket;
          _registerActiveTicket(ticket.ticketId);
          if ((ticket.type == TicketType.resource ||
                  ticket.type == TicketType.bug) &&
              _relationsLoadedForId != ticket.id) {
            _relationsLoadedForId = ticket.id;
            context.read<TicketsCubit>().loadDocumentRelations(ticket.id);
          }
        }
      },
      child: ColoredBox(
        color: c.background,
        child: Column(
          children: [
            BlocBuilder<TicketsCubit, TicketsState>(
              builder: (context, state) {
                // A `chat` ticket renders its own compact/collapsing
                // header (`ChatMetaHeader`, inside `ChatTranscriptPane`)
                // in place of this screen-level header — see
                // `aion-arch/changes/chat-transcript-ux-redesign`.
                if (state is TicketDetailLoaded &&
                    state.ticket.type == TicketType.chat) {
                  return const SizedBox.shrink();
                }
                final title = state is TicketDetailLoaded
                    ? state.ticket.ticketId
                    : '…';
                return AppHeader(
                  title: title,
                  showBack: true,
                  onBack: () => context.go('/workspace/tickets'),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  trailing: state is TicketDetailLoaded
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isSyncable(state.ticket)) ...[
                              SyncStatusBadge(status: state.ticket.syncStatus),
                              const SizedBox(width: 12),
                            ],
                            TicketOverflowMenu(ticket: state.ticket),
                          ],
                        )
                      : PhosphorIcon(
                          PhosphorIcons.dotsThreeLight,
                          size: 20,
                          color: c.textSecondary,
                        ),
                );
              },
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: BlocBuilder<TicketsCubit, TicketsState>(
                      builder: (context, state) {
                        if (state is! TicketDetailLoaded) {
                          return const SizedBox.shrink();
                        }
                        final ticket = state.ticket;
                        if (ticket.type == TicketType.chat) {
                          // Own scrolling region: metadata collapses into
                          // ChatMetaHeader as the transcript scrolls — see
                          // design.md §8. No SingleChildScrollView/
                          // TicketMetadataSection wrapper here; both live
                          // inside ChatTranscriptPane's collapsing header.
                          return ChatTranscriptPane(
                            ticketId: widget.ticketId,
                            ticket: ticket,
                            automationConfidence: _automationConfidence,
                            onAdvanceSddStage: (t) => _advanceSddStage(t),
                            onMaybeAutoAdvance: (t, canAdvance) =>
                                _maybeAutoAdvanceSddStage(t, canAdvance),
                            isAdvancingStage: state.isAdvancingStage,
                          );
                        }
                        return SingleChildScrollView(
                          child: ContentMaxWidth(
                            variant: ContentWidthVariant.reading,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TicketMetadataSection(
                                  ticket: ticket,
                                  automationConfidence: _automationConfidence,
                                  onAdvanceSddStage: (t) => _advanceSddStage(t),
                                  onMaybeAutoAdvance: (t, canAdvance) =>
                                      _maybeAutoAdvanceSddStage(t, canAdvance),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    16,
                                    20,
                                    0,
                                  ),
                                  child: BlocBuilder<CommentsCubit, CommentsState>(
                                    builder: (context, state) {
                                      return switch (state) {
                                        CommentsLoading() => const Center(
                                          child: AppSpinner(),
                                        ),
                                        CommentsError(:final message) => Text(
                                          message,
                                          style: AionText.body.copyWith(
                                            color: c.danger,
                                          ),
                                        ),
                                        CommentsLoaded(:final comments) ||
                                        CommentAdding(:final comments) ||
                                        CommentAdded(:final comments) => Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              context.l10n
                                                  .ticketDetailCommentsCount(
                                                    comments.length,
                                                  ),
                                              style: AionText.caption.copyWith(
                                                color: c.textMuted,
                                              ),
                                            ),
                                            const SizedBox(
                                              height: AionSpacing.sp12,
                                            ),
                                            ListView.builder(
                                              shrinkWrap: true,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              itemCount: comments.length,
                                              itemBuilder: (context, index) =>
                                                  CommentTile(
                                                    comment: comments[index],
                                                  ),
                                            ),
                                          ],
                                        ),
                                        _ => const SizedBox.shrink(),
                                      };
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Container(color: c.border, height: 1),
                  // "Retry validation" bar (design.md §4) — shown only for
                  // a "Design Sync — <Story>" chat whose most recent AI
                  // reply says PENDING. Added for
                  // aion-arch/changes/sdd-design-gate. AnimatedSize per
                  // design.md §4.1 — the bar grows/shrinks in rather than
                  // popping instantly as the gate flips.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.topCenter,
                    child: BlocBuilder<TicketsCubit, TicketsState>(
                      builder: (context, ticketsState) {
                        if (ticketsState is! TicketDetailLoaded) {
                          return const SizedBox.shrink();
                        }
                        final chatTicket = ticketsState.ticket;
                        if (chatTicket.type != TicketType.chat ||
                            !chatTicket.title.startsWith('Design Sync — ')) {
                          return const SizedBox.shrink();
                        }
                        return BlocBuilder<ChatCubit, ChatState>(
                          builder: (context, chatState) {
                            if (chatState is! ChatLoaded ||
                                chatState.comments.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final mostRecent = chatState.comments.reduce(
                              (a, b) =>
                                  a.createdAt.isAfter(b.createdAt) ? a : b,
                            );
                            final isPending =
                                mostRecent.authorType == CommentAuthorType.ai &&
                                mostRecent.content.contains(
                                  'DESIGN GATE: PENDING',
                                );
                            if (!isPending) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _RetryValidationButton(
                                  isLoading: _retryingDesignSync,
                                  onRetry: () => _retryDesignSync(chatTicket),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // Pinned above the compose field, between
                  // ChatTranscriptPane and ChatComposeField (design.md §5)
                  // — shown only while a branch_ticket/close_branch call
                  // awaits confirmation (AutomationConfidence.gated).
                  // AnimatedSize per the same grow/shrink treatment the
                  // retry-validation bar above uses. Added for
                  // aion-arch/changes/mid-task-chat-branching.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.topCenter,
                    child: BlocBuilder<TicketsCubit, TicketsState>(
                      builder: (context, ticketsState) {
                        if (ticketsState is! TicketDetailLoaded ||
                            ticketsState.ticket.type != TicketType.chat) {
                          return const SizedBox.shrink();
                        }
                        final proposal = ticketsState.pendingToolProposal;
                        if (proposal == null) return const SizedBox.shrink();
                        final chatId = ticketsState.ticket.id;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                          child: switch (proposal) {
                            BranchProposal(:final title, :final description) =>
                              _ToolProposalBanner(
                                kind: ToolProposalKind.branch,
                                proposedTitle: title,
                                description: description,
                                onConfirm: () => context
                                    .read<TicketsCubit>()
                                    .confirmPendingToolProposal(chatId),
                                onReject: () => context
                                    .read<TicketsCubit>()
                                    .rejectPendingToolProposal(chatId),
                              ),
                            CloseBranchProposal(:final summary) =>
                              _ToolProposalBanner(
                                kind: ToolProposalKind.close,
                                summary: summary,
                                onConfirm: () => context
                                    .read<TicketsCubit>()
                                    .confirmPendingToolProposal(chatId),
                                onReject: () => context
                                    .read<TicketsCubit>()
                                    .rejectPendingToolProposal(chatId),
                              ),
                          },
                        );
                      },
                    ),
                  ),
                  ColoredBox(
                    color: c.background,
                    child: ContentMaxWidth(
                      variant: ContentWidthVariant.reading,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                        child: _currentTicket?.type == TicketType.chat
                            ? ChatComposeField(
                                controller: _commentController,
                                onSend: _sendComment,
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: c.secondary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SizedBox(
                                      width: 34,
                                      height: 34,
                                      child: Center(
                                        child: Text(
                                          'U',
                                          style: AionText.key.copyWith(
                                            color: const Color(0xFFFFFFFF),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: c.surface,
                                        border: Border.all(
                                          color: c.border,
                                          width: 1,
                                        ),
                                        borderRadius: BorderRadius.all(
                                          AionRadius.pill,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 15,
                                          vertical: 10,
                                        ),
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: TextField(
                                            controller: _commentController,
                                            maxLines: 1,
                                            style: AionText.bodySm.copyWith(
                                              color: c.textPrimary,
                                              fontSize: 13,
                                            ),
                                            decoration:
                                                InputDecoration.collapsed(
                                                  hintText: context
                                                      .l10n
                                                      .ticketDetailCommentHint,
                                                  hintStyle: AionText.bodySm
                                                      .copyWith(
                                                        color: c.textMuted,
                                                        fontSize: 13,
                                                      ),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Semantics(
                                    button: true,
                                    label: context.l10n.ticketDetailSendComment,
                                    child: GestureDetector(
                                      onTap: _sendComment,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: c.primary,
                                          borderRadius: BorderRadius.circular(
                                            19,
                                          ),
                                          boxShadow: AionShadows.fab(
                                            c,
                                            t.isDark,
                                          ),
                                        ),
                                        child: SizedBox(
                                          width: 38,
                                          height: 38,
                                          child: Center(
                                            child: PhosphorIcon(
                                              PhosphorIcons.paperPlaneTiltLight,
                                              size: 17,
                                              color: const Color(
                                                0xFFFFFFFF,
                                              ), // white glyph
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single comment bubble: avatar, author label, timestamp, and content.
/// Visually distinguishes [CommentAuthorType.ai] comments (primary-tinted
/// bubble, sparkle avatar, "AI" tag, `via <model>` footer) from
/// [CommentAuthorType.human] ones.
class CommentTile extends StatelessWidget {
  /// Creates a [CommentTile] rendering [comment].
  const CommentTile({super.key, required this.comment});

  /// The comment this tile represents.
  final TicketComment comment;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isAi = comment.authorType == CommentAuthorType.ai;
    final isSystem = comment.authorType == CommentAuthorType.system;

    return Semantics(
      label: '${comment.authorType.name} comment: ${comment.content}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AionSpacing.sp16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommentAuthorAvatar(
              colors: c,
              isAi: isAi,
              isSystem: isSystem,
              isDark: t.isDark,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (isAi) ...[
                        Text(
                          context.l10n.ticketDetailAiAuthor,
                          style: AionText.cardTitle.copyWith(
                            fontSize: 12.5,
                            color: c.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: AionSpacing.sp4),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.primarySubtle,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              context.l10n.ticketDetailAiTag,
                              style: AionText.prioritySm.copyWith(
                                color: c.primary,
                              ),
                            ),
                          ),
                        ),
                      ] else if (isSystem)
                        Text(
                          context.l10n.ticketDetailSystemAuthor,
                          style: AionText.cardTitle.copyWith(
                            fontSize: 12.5,
                            color: c.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        Text(
                          context.l10n.ticketDetailYouAuthor,
                          style: AionText.cardTitle.copyWith(
                            fontSize: 12.5,
                            color: c.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        _formatTime(comment.createdAt),
                        style: AionText.time.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AionSpacing.sp4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        topRight: AionRadius.lg,
                        bottomLeft: AionRadius.lg,
                        bottomRight: AionRadius.lg,
                      ),
                      color: isAi ? c.primarySubtle : c.surface,
                      border: Border.all(
                        color: isAi
                            ? c.primary.withValues(
                                alpha: t.isDark ? 0.42 : 0.28,
                              )
                            : c.border,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        comment.content,
                        style: AionText.bodySm.copyWith(
                          color: isSystem ? c.textSecondary : c.textPrimary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  if (isAi && comment.aiModel != null) ...[
                    const SizedBox(height: AionSpacing.sp4),
                    Text(
                      context.l10n.ticketDetailViaModel(comment.aiModel!),
                      style: AionText.time.copyWith(color: c.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// A plain, always-available control for re-running
/// [SddStage.designSync]'s validation after a `DESIGN GATE: PENDING`
/// verdict — styled like [_ManualAdvanceButton] (no banner framing,
/// since this is a recovery utility, not a proactive suggestion), with
/// a refresh glyph instead of a caret. See design.md §4. Added for
/// `aion-arch/changes/sdd-design-gate`.
class _RetryValidationButton extends StatefulWidget {
  const _RetryValidationButton({required this.onRetry, this.isLoading = false});

  final VoidCallback onRetry;

  /// Disabled/spinning-glyph state (design.md §4.3) while a retry is
  /// already in flight — `IgnorePointer`, `0.45` opacity, `textMuted`
  /// glyph/text, glyph spinning via a 900ms linear loop. Added for
  /// `aion-arch/changes/sdd-design-gate`.
  final bool isLoading;

  @override
  State<_RetryValidationButton> createState() => _RetryValidationButtonState();
}

class _RetryValidationButtonState extends State<_RetryValidationButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isLoading) _spinController.repeat();
  }

  @override
  void didUpdateWidget(_RetryValidationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !oldWidget.isLoading) {
      _spinController.repeat();
    } else if (!widget.isLoading && oldWidget.isLoading) {
      _spinController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final label = context.l10n.chatRetryValidation;
    final glyphColor = widget.isLoading ? c.textMuted : c.primary;
    final button = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceHover.withValues(alpha: widget.isLoading ? 0.45 : 1),
        border: Border.all(
          color: c.borderStrong.withValues(alpha: widget.isLoading ? 0.45 : 1),
          width: 1,
        ),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _spinController,
              child: PhosphorIcon(
                PhosphorIcons.arrowsClockwiseLight,
                size: 14,
                color: glyphColor,
              ),
            ),
            const SizedBox(width: 7),
            Text(label, style: AionText.button.copyWith(color: glyphColor)),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      label: label,
      enabled: !widget.isLoading,
      child: IgnorePointer(
        ignoring: widget.isLoading,
        child: GestureDetector(onTap: widget.onRetry, child: button),
      ),
    );
  }
}

/// Content variant [_ToolProposalBanner] renders — maps 1:1 to the two
/// app-defined tools (`branch_ticket`/`close_branch`). Added for
/// `aion-arch/changes/mid-task-chat-branching`; see that change's
/// design.md's Component Spec §7.
enum ToolProposalKind {
  /// `branch_ticket` awaiting confirm — the proposed-child well (§3.1).
  branch,

  /// `close_branch` awaiting confirm — the resolution-summary well (§3.2).
  close,
}

/// A turn-blocking Confirm/Reject surface pinned above the compose field
/// in a `chat` ticket's detail screen (see `_TicketDetailScreenState.build`),
/// shown while a `branch_ticket`/`close_branch` call awaits the user
/// (`AutomationConfidence.chatBranching == gated`). One shell, two content
/// variants selected by [kind]. Reads as a deliberate decision point, not
/// a transcript entry: a tinted `typeChat` frame, `AionText.dialogTitle`
/// headline weight, and a full-width action row, none of which a chat
/// message bubble has. Placement mirrors the existing Design Sync
/// retry-validation bar (`_RetryValidationButton`). Added for
/// `aion-arch/changes/mid-task-chat-branching`; see that change's
/// design.md's Component Spec §1–§4.
class _ToolProposalBanner extends StatefulWidget {
  /// Creates a [_ToolProposalBanner] for [kind], with
  /// [proposedTitle]/[description] ([ToolProposalKind.branch]) or
  /// [summary] ([ToolProposalKind.close]) content, wired to [onConfirm]/
  /// [onReject].
  const _ToolProposalBanner({
    required this.kind,
    this.proposedTitle,
    this.description,
    this.summary,
    required this.onConfirm,
    required this.onReject,
  });

  /// Which content variant this banner renders.
  final ToolProposalKind kind;

  /// The proposed child chat's title — [ToolProposalKind.branch] only.
  final String? proposedTitle;

  /// The AI's optional rationale for the branch — [ToolProposalKind.branch]
  /// only; the description node is omitted entirely when `null`.
  final String? description;

  /// The AI's resolution summary — [ToolProposalKind.close] only.
  final String? summary;

  /// Called on a Confirm tap. `null` disables the Confirm button (a
  /// confirm/reject request is already posting).
  final VoidCallback? onConfirm;

  /// Called on a Reject tap. `null` disables the Reject button.
  final VoidCallback? onReject;

  @override
  State<_ToolProposalBanner> createState() => _ToolProposalBannerState();
}

class _ToolProposalBannerState extends State<_ToolProposalBanner>
    with TickerProviderStateMixin {
  /// Drives the glyph tile's breathing halo (§2.3a) — 2000ms, slower/
  /// softer than the streaming glow, reading as "breathing" not "working."
  late final AnimationController _haloController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  /// Drives the status-line pulsing dot (§2.3b) — 1400ms, the same
  /// low-key liveness pulse as the live tool-use dot.
  late final AnimationController _dotController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool _startedAnimating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_startedAnimating && !MediaQuery.of(context).disableAnimations) {
      _startedAnimating = true;
      _haloController.repeat(reverse: true);
      _dotController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _haloController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.chatTint(t.isDark),
        border: Border.all(color: c.chatBorderTint(t.isDark), width: 1),
        borderRadius: BorderRadius.all(AionRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ToolProposalHeader(
              kind: widget.kind,
              haloController: _haloController,
              dotController: _dotController,
              reducedMotion: reducedMotion,
            ),
            const SizedBox(height: 12),
            widget.kind == ToolProposalKind.branch
                ? _BranchProposalWell(
                    title: widget.proposedTitle ?? '',
                    description: widget.description,
                  )
                : _CloseProposalWell(summary: widget.summary ?? ''),
            const SizedBox(height: 12),
            _ToolProposalActionRow(
              onConfirm: widget.onConfirm,
              onReject: widget.onReject,
            ),
          ],
        ),
      ),
    );
  }
}

/// [_ToolProposalBanner]'s header row: leading glyph tile (with the
/// breathing halo, §2.3a) + title/status column (with the pulsing status
/// dot, §2.3b). Split out from [_ToolProposalBannerState] as a plain
/// [StatelessWidget] driven by the two [AnimationController]s the parent
/// owns, rather than re-animating the whole banner (content well + action
/// row) every frame. Per design.md's Component Spec §2.2/§2.3.
class _ToolProposalHeader extends StatelessWidget {
  const _ToolProposalHeader({
    required this.kind,
    required this.haloController,
    required this.dotController,
    required this.reducedMotion,
  });

  final ToolProposalKind kind;
  final AnimationController haloController;
  final AnimationController dotController;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isBranch = kind == ToolProposalKind.branch;
    final haloAnimation = Tween<double>(
      begin: 0.35,
      end: 0.85,
    ).animate(haloController);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: haloAnimation,
          builder: (context, child) {
            final glowT = reducedMotion ? 0.85 : haloAnimation.value;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: c.pressedAccentTint(c.typeChat, t.isDark),
                borderRadius: BorderRadius.all(AionRadius.md),
                boxShadow: [
                  BoxShadow(
                    color: c.typeChat.withValues(
                      alpha: (t.isDark ? 0.55 : 0.40) * glowT,
                    ),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: PhosphorIcon(
                isBranch
                    ? PhosphorIcons.arrowBendDownRightLight
                    : PhosphorIcons.arrowBendUpLeftLight,
                size: 18,
                color: c.typeChat,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isBranch
                    ? context.l10n.ticketDetailToolProposalBranchTitle
                    : context.l10n.ticketDetailToolProposalCloseTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AionText.dialogTitle.copyWith(
                  color: c.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToolProposalStatusDot(
                    controller: dotController,
                    reducedMotion: reducedMotion,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    context.l10n.ticketDetailToolProposalStatusLine,
                    style: AionText.streamStatus.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The `6×6` pulsing status dot preceding [_ToolProposalHeader]'s status
/// line — opacity+scale looping per §2.3b, or a static full-opacity dot
/// under reduced motion. Mirrors `_WaitingForReplyIndicatorState`'s own
/// pulsing-dot treatment.
class _ToolProposalStatusDot extends StatelessWidget {
  const _ToolProposalStatusDot({
    required this.controller,
    required this.reducedMotion,
  });

  final AnimationController controller;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final dot = DecoratedBox(
      decoration: BoxDecoration(color: c.typeChat, shape: BoxShape.circle),
      child: const SizedBox(width: 6, height: 6),
    );
    if (reducedMotion) return dot;
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.0).animate(controller),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1.0).animate(controller),
        child: dot,
      ),
    );
  }
}

/// [ToolProposalKind.branch]'s content well — a recessed echo of how a
/// chat ticket renders elsewhere (a `typeChat` square + a title), so the
/// user sees *what* will be spun off. Per design.md's Component Spec
/// §3.1.
class _BranchProposalWell extends StatelessWidget {
  const _BranchProposalWell({required this.title, this.description});

  /// The proposed child chat ticket's title.
  final String title;

  /// The AI's optional 1–3 sentence rationale — the node is omitted
  /// entirely when `null`.
  final String? description;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.typeChat,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const SizedBox(width: 9, height: 9),
                ),
                const SizedBox(width: 7),
                Text(
                  context.l10n.ticketDetailToolProposalNewChatEyebrow,
                  style: AionText.caption.copyWith(
                    fontSize: 9.5,
                    color: c.typeChat,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AionText.cardTitle.copyWith(color: c.textPrimary),
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AionText.bodySm.copyWith(
                  color: c.textSecondary,
                  height: 1.55,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// [ToolProposalKind.close]'s content well — a summary paragraph rather
/// than a title+description, capped at `maxHeight: 132` with a persistent
/// bottom fade when the summary overflows (mirrors `_ExecutionErrorWell`'s
/// scroll+fade treatment in `ticket_metadata_section.dart`). Per
/// design.md's Component Spec §3.2.
class _CloseProposalWell extends StatelessWidget {
  const _CloseProposalWell({required this.summary});

  /// The AI's account of how the branch's sub-issue was resolved.
  final String summary;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.all(AionRadius.md),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.all(AionRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 132),
          child: Stack(
            children: [
              SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.typeChat,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const SizedBox(width: 9, height: 9),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          context
                              .l10n
                              .ticketDetailToolProposalResolutionEyebrow,
                          style: AionText.caption.copyWith(
                            fontSize: 9.5,
                            color: c.typeChat,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      summary,
                      style: AionText.body.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [c.surface.withValues(alpha: 0), c.surface],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [_ToolProposalBanner]'s action row — Reject (quiet ghost) + Confirm
/// (solid `typeChat`, affirmative weight). Narrow layouts (< ~420 content
/// px) size both buttons equally via `Expanded`; wide layouts size to
/// content and right-align. Per design.md's Component Spec §3.4.
class _ToolProposalActionRow extends StatelessWidget {
  const _ToolProposalActionRow({
    required this.onConfirm,
    required this.onReject,
  });

  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final reject = _ToolProposalButton(
          variant: _ToolProposalButtonVariant.reject,
          label: context.l10n.ticketDetailToolProposalRejectButton,
          onPressed: onReject,
        );
        final confirm = _ToolProposalButton(
          variant: _ToolProposalButtonVariant.confirm,
          label: context.l10n.ticketDetailToolProposalConfirmButton,
          onPressed: onConfirm,
        );
        if (constraints.maxWidth < 420) {
          return Row(
            children: [
              Expanded(child: reject),
              const SizedBox(width: 10),
              Expanded(child: confirm),
            ],
          );
        }
        return Row(
          children: [
            const Spacer(),
            reject,
            const SizedBox(width: 10),
            confirm,
          ],
        );
      },
    );
  }
}

/// The two [_ToolProposalButton] visual treatments — see
/// [_ToolProposalActionRow].
enum _ToolProposalButtonVariant {
  /// Solid `typeChat` fill, `check` glyph, glow — the affirmative action.
  confirm,

  /// Transparent fill, `1px border`, `textSecondary` label — the quiet
  /// decline (never `danger`; see design.md's Component Spec §3.4 "why
  /// Reject is a ghost").
  reject,
}

/// One [_ToolProposalBanner] action button — bespoke rather than
/// `AppButton` (its custom glow/hover-shade/focus-ring don't fit
/// `AppButton`'s existing variant set — see tasks.md T20's non-blocking
/// note). Mirrors `_ExecutionActionButton`'s state machinery (hover/
/// press/focus/disabled), re-keyed to `typeChat` for
/// [_ToolProposalButtonVariant.confirm] and a quiet neutral ghost for
/// [_ToolProposalButtonVariant.reject] — including each variant's own
/// disabled treatment (confirm: independent fill/label alphas; reject: a
/// single blanket `Opacity`), per design.md's Component Spec §3.4/§3.5.
class _ToolProposalButton extends StatefulWidget {
  const _ToolProposalButton({
    required this.variant,
    required this.label,
    required this.onPressed,
  });

  final _ToolProposalButtonVariant variant;
  final String label;

  /// `null` disables the button (§3.5's Disabled state).
  final VoidCallback? onPressed;

  @override
  State<_ToolProposalButton> createState() => _ToolProposalButtonState();
}

class _ToolProposalButtonState extends State<_ToolProposalButton> {
  final ValueNotifier<bool> _isHovered = ValueNotifier(false);
  bool _isPressed = false;
  bool _isFocused = false;

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    return Semantics(
      button: true,
      label: widget.label,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (value) => setState(() => _isFocused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => _isHovered.value = true,
          onExit: (_) => _isHovered.value = false,
          child: GestureDetector(
            onTap: widget.onPressed,
            onTapDown: enabled
                ? (_) => setState(() => _isPressed = true)
                : null,
            onTapUp: enabled ? (_) => setState(() => _isPressed = false) : null,
            onTapCancel: enabled
                ? () => setState(() => _isPressed = false)
                : null,
            child: IgnorePointer(
              ignoring: !enabled,
              child: ValueListenableBuilder<bool>(
                valueListenable: _isHovered,
                builder: (context, hovered, _) =>
                    widget.variant == _ToolProposalButtonVariant.confirm
                    ? _ConfirmButtonFace(
                        enabled: enabled,
                        hovered: hovered,
                        pressed: _isPressed,
                        focused: _isFocused,
                        label: widget.label,
                      )
                    : _RejectButtonFace(
                        enabled: enabled,
                        hovered: hovered,
                        pressed: _isPressed,
                        focused: _isFocused,
                        label: widget.label,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [_ToolProposalButton]'s [_ToolProposalButtonVariant.confirm] visual
/// face — solid `typeChat` fill, `check` glyph, glow. A real widget class
/// (not a private build method) per this project's widget-composition
/// convention, receiving [_ToolProposalButtonState]'s interaction flags
/// as plain constructor parameters.
class _ConfirmButtonFace extends StatelessWidget {
  const _ConfirmButtonFace({
    required this.enabled,
    required this.hovered,
    required this.pressed,
    required this.focused,
    required this.label,
  });

  final bool enabled;
  final bool hovered;
  final bool pressed;
  final bool focused;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final fill = !enabled
        ? c.typeChat.withValues(alpha: 0.45)
        : hovered
        ? Color.lerp(
            c.typeChat,
            t.isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
            0.10,
          )!
        : c.typeChat;
    final glowBlur = !enabled ? 0.0 : (pressed ? 0.0 : (hovered ? 20.0 : 16.0));
    final labelAlpha = enabled ? 1.0 : 0.55;
    return AnimatedScale(
      scale: enabled && pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 80),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.all(AionRadius.md),
          boxShadow: [
            if (glowBlur > 0)
              BoxShadow(
                color: c.typeChat.withValues(alpha: t.isDark ? 0.55 : 0.40),
                blurRadius: glowBlur,
                spreadRadius: -6,
                offset: const Offset(0, 6),
              ),
            if (focused && enabled)
              BoxShadow(
                color: c.typeChat.withValues(alpha: t.isDark ? 0.30 : 0.16),
                blurRadius: 0,
                spreadRadius: 3,
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PhosphorIcon(
                PhosphorIcons.checkLight,
                size: 15,
                color: const Color(0xFFFFFFFF).withValues(alpha: labelAlpha),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AionText.button.copyWith(
                  color: const Color(0xFFFFFFFF).withValues(alpha: labelAlpha),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [_ToolProposalButton]'s [_ToolProposalButtonVariant.reject] visual
/// face — transparent fill, `1px border`, `textSecondary` label, with a
/// single blanket [Opacity] for its disabled state (unlike
/// [_ConfirmButtonFace]'s independent per-layer disabled alphas — see
/// design.md's Component Spec §3.5). A real widget class (not a private
/// build method) per this project's widget-composition convention.
class _RejectButtonFace extends StatelessWidget {
  const _RejectButtonFace({
    required this.enabled,
    required this.hovered,
    required this.pressed,
    required this.focused,
    required this.label,
  });

  final bool enabled;
  final bool hovered;
  final bool pressed;
  final bool focused;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final showHover = enabled && hovered;
    final content = AnimatedScale(
      scale: enabled && pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 80),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: showHover ? c.surfaceHover : const Color(0x00000000),
          border: Border.all(
            color: showHover ? c.borderStrong : c.border,
            width: 1,
          ),
          borderRadius: BorderRadius.all(AionRadius.md),
          boxShadow: [
            if (focused && enabled)
              BoxShadow(
                color: c.typeChat.withValues(alpha: t.isDark ? 0.30 : 0.16),
                blurRadius: 0,
                spreadRadius: 3,
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AionText.button.copyWith(
              color: showHover ? c.textPrimary : c.textSecondary,
            ),
          ),
        ),
      ),
    );
    return enabled ? content : Opacity(opacity: 0.45, child: content);
  }
}
