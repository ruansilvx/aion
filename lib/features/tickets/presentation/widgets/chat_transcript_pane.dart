// presentation/widgets/chat_transcript_pane.dart — ChatTranscriptPane collapsing-header transcript (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_cubit.dart';
import 'package:aion/features/tickets/presentation/cubit/chat_state.dart';
import 'package:aion/features/tickets/presentation/widgets/chat_message_bubble.dart';
import 'package:aion/features/tickets/presentation/widgets/chat_meta_header.dart';
import 'package:aion/features/tickets/presentation/widgets/comment_author_avatar.dart';
import 'package:aion/features/tickets/presentation/widgets/ticket_metadata_section.dart';

/// A `chat`-type ticket's message transcript: a single scrolling region
/// (`CustomScrollView`) whose top is [ticket]'s full metadata content
/// ([TicketMetadataSection]) and whose messages ([ChatMessageBubble])
/// follow beneath it. Scrolling down collapses the metadata into a
/// compact pinned [ChatMetaHeader]; scrolling back up re-expands it —
/// nothing is dropped, just collapsible. Auto-scrolls to the newest
/// message on load and on every streaming update. Replaces the old
/// non-scrolling, `shrinkWrap` chat list embedded in the whole page's
/// shared scroll. Per
/// `aion-arch/changes/chat-transcript-ux-redesign/design.md` §2 and §8.
class ChatTranscriptPane extends StatefulWidget {
  /// Creates a [ChatTranscriptPane] for the chat ticket [ticketId].
  const ChatTranscriptPane({
    super.key,
    required this.ticketId,
    required this.ticket,
    required this.automationConfidence,
    required this.onAdvanceSddStage,
    required this.onMaybeAutoAdvance,
    this.isAdvancingStage = false,
  });

  /// Internal id of the chat ticket whose transcript this pane renders.
  final String ticketId;

  /// The chat ticket itself — rendered by the collapsing header's
  /// [TicketMetadataSection]/[ChatMetaHeader] content.
  final Ticket ticket;

  /// Forwarded to [TicketMetadataSection] — see that widget's
  /// constructor doc comment.
  final AutomationConfidence? automationConfidence;

  /// Forwarded to [TicketMetadataSection].
  final void Function(Ticket ticket) onAdvanceSddStage;

  /// Forwarded to [TicketMetadataSection].
  final void Function(Ticket ticket, bool canAdvance) onMaybeAutoAdvance;

  /// Whether [ticket] itself is the live target of a
  /// `TicketsCubit._runStageChatTurn` spawn (`TicketDetailLoaded
  /// .isAdvancingStage`, sourced from `ticket_detail_screen.dart`'s own
  /// `TicketsCubit` subscription) — drives [_WaitingForReplyIndicator]
  /// at the transcript's tail while `true`. Added for
  /// `aion-arch/changes/board-execution-indicators-and-notifications`.
  final bool isAdvancingStage;

  @override
  State<ChatTranscriptPane> createState() => _ChatTranscriptPaneState();
}

class _ChatTranscriptPaneState extends State<ChatTranscriptPane> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    return BlocConsumer<ChatCubit, ChatState>(
      listener: (context, state) {
        if (state is ChatLoaded) _scrollToBottom();
      },
      builder: (context, state) {
        return switch (state) {
          ChatInitial() => const Center(child: AppSpinner()),
          ChatError(:final message) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AionSpacing.sp20),
              child: Text(
                message,
                style: AionText.body.copyWith(color: c.danger),
              ),
            ),
          ),
          ChatLoaded(
            :final comments,
            :final streamingText,
            :final currentToolUse,
          ) =>
            comments.isEmpty && streamingText == null && currentToolUse == null
                ? _ChatEmptyState(
                    ticket: widget.ticket,
                    automationConfidence: widget.automationConfidence,
                    onAdvanceSddStage: widget.onAdvanceSddStage,
                    onMaybeAutoAdvance: widget.onMaybeAutoAdvance,
                  )
                : CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _CollapsingChatHeaderDelegate(
                          ticket: widget.ticket,
                          automationConfidence: widget.automationConfidence,
                          onAdvanceSddStage: widget.onAdvanceSddStage,
                          onMaybeAutoAdvance: widget.onMaybeAutoAdvance,
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _TranscriptListItem(
                              comments: comments,
                              streamingText: streamingText,
                              currentToolUse: currentToolUse,
                              index: index,
                            ),
                            childCount:
                                1 +
                                comments.length +
                                (streamingText != null || currentToolUse != null
                                    ? 1
                                    : 0),
                          ),
                        ),
                      ),
                      // TicketsCubit._runStageChatTurn runs outside this
                      // screen's own ChatCubit, so streamingText/
                      // currentToolUse never reflect it — this is the
                      // only "something is happening" signal available
                      // while its reply is still in flight.
                      if (widget.isAdvancingStage &&
                          streamingText == null &&
                          currentToolUse == null)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                          sliver: const SliverToBoxAdapter(
                            child: _WaitingForReplyIndicator(),
                          ),
                        ),
                    ],
                  ),
        };
      },
    );
  }
}

/// One item in the transcript's `SliverList` — the `"MESSAGES · n"` count
/// header at [index] `0`, a [ChatMessageBubble] per comment, and a
/// trailing [_StreamingBubble] while a reply is in flight. A private
/// widget class (not a `Widget`-returning method) per
/// flutter-conventions.md's widget-composition rule — see
/// `ChatTranscriptPane`'s `SliverChildBuilderDelegate`.
class _TranscriptListItem extends StatelessWidget {
  const _TranscriptListItem({
    required this.comments,
    required this.streamingText,
    required this.currentToolUse,
    required this.index,
  });

  final List<TicketComment> comments;
  final String? streamingText;
  final String? currentToolUse;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    if (index == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AionSpacing.sp12),
        child: Text(
          context.l10n.ticketDetailChatMessagesCount(comments.length),
          style: AionText.caption.copyWith(color: c.textMuted),
        ),
      );
    }
    final messageIndex = index - 1;
    if (messageIndex < comments.length) {
      return ChatMessageBubble(comment: comments[messageIndex]);
    }
    return _StreamingBubble(text: streamingText, toolUse: currentToolUse);
  }
}

/// A freshly-spawned chat ticket with no messages yet — the collapsing
/// header at its fully-expanded height (no transcript to scroll, so no
/// `CustomScrollView`) above a centered sparkle glyph + caption. Design.md
/// §2.4.
class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({
    required this.ticket,
    required this.automationConfidence,
    required this.onAdvanceSddStage,
    required this.onMaybeAutoAdvance,
  });

  final Ticket ticket;
  final AutomationConfidence? automationConfidence;
  final void Function(Ticket ticket) onAdvanceSddStage;
  final void Function(Ticket ticket, bool canAdvance) onMaybeAutoAdvance;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    return Column(
      children: [
        _StaticExpandedHeader(
          delegate: _CollapsingChatHeaderDelegate(
            ticket: ticket,
            automationConfidence: automationConfidence,
            onAdvanceSddStage: onAdvanceSddStage,
            onMaybeAutoAdvance: onMaybeAutoAdvance,
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PhosphorIcon(
                  PhosphorIcons.sparkleFill,
                  size: 40,
                  color: c.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: AionSpacing.sp12),
                Text(
                  context.l10n.ticketDetailChatEmptyTitle,
                  style: AionText.cardTitle.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: AionSpacing.sp4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    context.l10n.ticketDetailChatEmptyCaption,
                    textAlign: TextAlign.center,
                    style: AionText.bodySm.copyWith(color: c.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The compact/expanded metadata header (design.md §8.3) rendered as a
/// `SliverPersistentHeader` delegate — cross-fades [TicketMetadataSection]
/// (expanded) into [ChatMetaHeader] (collapsed) as `shrinkOffset` grows.
/// [_expandedHeight]/[_collapsedHeight] are fixed estimates rather than
/// dynamically measured (design.md §8.3 explicitly allows either); a
/// `chat` ticket's [TicketMetadataSection] never renders the SDD-stage
/// tracker, coding-execution section, or linked-tickets/backlinks
/// (those are gated to `epic`/`story`/`task`/`resource` respectively),
/// so its real height is well-bounded — content taller than
/// [_expandedHeight] (e.g. an unusually long description) clips rather
/// than overflows, via [ClipRect] + [OverflowBox].
class _CollapsingChatHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CollapsingChatHeaderDelegate({
    required this.ticket,
    required this.automationConfidence,
    required this.onAdvanceSddStage,
    required this.onMaybeAutoAdvance,
  });

  final Ticket ticket;
  final AutomationConfidence? automationConfidence;
  final void Function(Ticket ticket) onAdvanceSddStage;
  final void Function(Ticket ticket, bool canAdvance) onMaybeAutoAdvance;

  static const _expandedHeight = 560.0;
  // Generous fixed estimate for ChatMetaHeader's natural height (nav row
  // + a 2-line title + meta row) — confirmed via manual testing that
  // 140 overflowed by ~53px for a real long title; 210 leaves headroom.
  static const _collapsedHeight = 210.0;

  @override
  double get minExtent => _collapsedHeight;

  @override
  double get maxExtent => _expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final c = ThemeScope.of(context).colors;
    final range = maxExtent - minExtent;
    final progress = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    // `shrinkOffset` isn't guaranteed to stay within [0, maxExtent -
    // minExtent] even for a pinned delegate — fast-flung scrolls/
    // overscroll can transiently report a larger value, which would
    // otherwise drive currentHeight below minExtent and overflow
    // ChatMetaHeader's content (observed via manual testing).
    final currentHeight = (maxExtent - shrinkOffset).clamp(
      minExtent,
      maxExtent,
    );

    return ColoredBox(
      color: c.background,
      child: SizedBox(
        height: currentHeight,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: progress > 0.5,
                  child: Opacity(
                    opacity: 1 - progress,
                    child: OverflowBox(
                      minHeight: 0,
                      maxHeight: _expandedHeight,
                      alignment: Alignment.topCenter,
                      child: TicketMetadataSection(
                        ticket: ticket,
                        automationConfidence: automationConfidence,
                        onAdvanceSddStage: onAdvanceSddStage,
                        onMaybeAutoAdvance: onMaybeAutoAdvance,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: progress < 0.5,
                  child: Opacity(
                    opacity: progress,
                    child: ChatMetaHeader(
                      ticket: ticket,
                      onBack: () => context.go('/workspace/tickets'),
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

  @override
  bool shouldRebuild(covariant _CollapsingChatHeaderDelegate oldDelegate) {
    return ticket != oldDelegate.ticket ||
        automationConfidence != oldDelegate.automationConfidence;
  }
}

/// Renders the compact/expanded metadata header outside a
/// `CustomScrollView` (the chat's empty state has no messages to
/// scroll, so it uses a plain, always-expanded header at
/// [SliverPersistentHeaderDelegate.maxExtent] instead of a
/// `SliverPersistentHeader`).
class _StaticExpandedHeader extends StatelessWidget {
  const _StaticExpandedHeader({required this.delegate});

  /// The delegate to render at [SliverPersistentHeaderDelegate.maxExtent].
  final SliverPersistentHeaderDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: delegate.maxExtent,
      child: delegate.build(context, 0, false),
    );
  }
}

/// Shown at the tail of a chat ticket's transcript while a spawned
/// [TicketsCubit] stage-advance turn (see `TicketsCubit
/// ._runStageChatTurn`) hasn't posted its reply for *this* chat ticket
/// yet. Reuses [_StreamingBubble]'s pulsing-dot pre-text treatment
/// (design.md §2.3a) — fixed text only, no `{tool}` emphasis, since
/// `_runStageChatTurn` calls `ChatCubit.runChatTurn`'s static helper
/// directly rather than through this screen's own [ChatCubit], so
/// there's no live `currentToolUse`/`streamingText` to show instead.
/// Removed the instant the real reply lands and
/// `ChatTranscriptPane.isAdvancingStage` flips to `false` (driving
/// `ticket_detail_screen.dart`'s `BlocListener` to call
/// `ChatCubit.loadMessages`, which replaces this row with the real
/// reply bubble). Added for
/// `aion-arch/changes/board-execution-indicators-and-notifications`.
class _WaitingForReplyIndicator extends StatefulWidget {
  const _WaitingForReplyIndicator();

  @override
  State<_WaitingForReplyIndicator> createState() =>
      _WaitingForReplyIndicatorState();
}

class _WaitingForReplyIndicatorState extends State<_WaitingForReplyIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _startedPulsing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_startedPulsing && !MediaQuery.of(context).disableAnimations) {
      _startedPulsing = true;
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final dot = DecoratedBox(
      decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
      child: const SizedBox(width: 7, height: 7),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          reducedMotion
              ? dot
              : ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.8,
                    end: 1.0,
                  ).animate(_pulseController),
                  child: FadeTransition(
                    opacity: Tween<double>(
                      begin: 0.35,
                      end: 1.0,
                    ).animate(_pulseController),
                    child: dot,
                  ),
                ),
          const SizedBox(width: 8),
          Text(
            context.l10n.ticketDetailWaitingForReply,
            style: AionText.streamStatus.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Renders an in-progress AI reply at the tail of the transcript —
/// [toolUse] (design.md §2.3a, "Running `<tool>`…") shown ahead of
/// [text] once streaming begins, flat (no bubble) matching a settled
/// `_AiMessage`'s treatment — a pulsing dot (pre-text) and a blinking
/// caret (once text arrives) are the only "in progress" signals; there
/// is no bubble edge left to glow around (design.md §9.3, supersedes
/// the former animated-border-glow treatment). Adapted from the former
/// `TicketDetailScreen._StreamingBubble`: renders [text] via
/// [MarkdownView] instead of a plain `TextSpan`, and adds [toolUse]
/// (previously tracked by [ChatState] but never rendered anywhere).
class _StreamingBubble extends StatefulWidget {
  const _StreamingBubble({required this.text, required this.toolUse});

  /// The accumulated reply text so far, `null` before any text chunk
  /// has streamed in.
  final String? text;

  /// The current "Running `<tool>`…" status, `null` when no tool call
  /// is in flight.
  final String? toolUse;

  @override
  State<_StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<_StreamingBubble>
    with TickerProviderStateMixin {
  late final AnimationController _caretController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _caretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AionSpacing.sp16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CommentAuthorAvatar(
            colors: c,
            isAi: true,
            isSystem: false,
            isDark: t.isDark,
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.ticketDetailAiAuthor,
                      style: AionText.cardTitle.copyWith(
                        fontSize: 12.5,
                        color: c.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      context.l10n.ticketDetailTyping,
                      style: AionText.time.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.toolUse != null && widget.text == null) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _caretController,
                              builder: (context, _) => Opacity(
                                opacity: 0.35 + (_caretController.value * 0.65),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: c.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const SizedBox(width: 7, height: 7),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                widget.toolUse!,
                                style: AionText.streamStatus.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.text != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: MarkdownView(source: widget.text!)),
                            const SizedBox(width: 3),
                            FadeTransition(
                              opacity: _caretController,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.primary,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                                child: const SizedBox(width: 2, height: 15),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
