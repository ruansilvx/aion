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
  /// "Advance" tap, then navigates to the spawned chat ticket once it and
  /// its first AI reply are ready — an intentional user action, unlike
  /// [_maybeAutoAdvanceSddStage]'s passive auto-advance, which never
  /// yanks the user off the screen they're already viewing.
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
  /// `ChatCubit.sendMessage` itself; see `providers.md`.
  void _sendComment() {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;
    if (_currentTicket?.type == TicketType.chat) {
      context.read<ChatCubit>().sendMessage(
        chatTicketId: widget.ticketId,
        content: content,
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
        } else if (state is TicketsError &&
            state.reason == TicketsErrorReason.invalidParent) {
          AppToast.show(context, context.l10n.ticketInvalidParentError);
        } else if (state is TicketsError &&
            state.reason == TicketsErrorReason.codingExecutionBlocked) {
          AppToast.show(
            context,
            context.l10n.ticketCodingExecutionBlockedError,
          );
        } else if (state is TicketsError &&
            state.reason == TicketsErrorReason.executionBudgetOverageDetected) {
          AppToast.show(
            context,
            context.l10n.executionBudgetOverageDetectedToast,
          );
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
