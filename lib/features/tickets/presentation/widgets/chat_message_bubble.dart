// presentation/widgets/chat_message_bubble.dart — ChatMessageBubble per-author-type transcript message rendering (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/presentation/widgets/comment_author_avatar.dart';

/// A single chat-transcript message. Human messages render right-aligned
/// in a bubble with plain text; AI messages render left-aligned and flat
/// (no bubble), content rendered as Markdown via [MarkdownView]; system
/// messages render as a compact centered divider, not a message row at
/// all. Adapted from `CommentTile`'s structure (author label/timestamp/
/// "via `<model>`" caption) but with per-author alignment and a capped
/// content width for human/AI, instead of `CommentTile`'s uniform
/// left-aligned, full-width, plain-text, always-bubbled rendering. Per
/// `AIO-482` §1/§9 (§9
/// supersedes §1.2/§1.3's bubble treatment for `ai`/`system`).
class ChatMessageBubble extends StatelessWidget {
  /// Creates a [ChatMessageBubble] rendering [comment].
  const ChatMessageBubble({super.key, required this.comment});

  /// The comment this bubble represents.
  final TicketComment comment;

  @override
  Widget build(BuildContext context) {
    switch (comment.authorType) {
      case CommentAuthorType.system:
        return Semantics(
          label: 'system comment: ${comment.content}',
          child: Padding(
            // Tighter than the sp16 human/AI messages use (design.md
            // §9.2) — a system divider should read as a light separator,
            // not a peer message, so it gets a smaller trailing gap.
            padding: const EdgeInsets.only(bottom: AionSpacing.sp8),
            child: LayoutBuilder(
              builder: (context, constraints) => _SystemMessage(
                comment: comment,
                maxWidth: constraints.maxWidth * 0.8,
              ),
            ),
          ),
        );
      case CommentAuthorType.human:
      case CommentAuthorType.ai:
        final isHuman = comment.authorType == CommentAuthorType.human;
        return Semantics(
          label: '${comment.authorType.name} comment: ${comment.content}',
          child: Padding(
            padding: const EdgeInsets.only(bottom: AionSpacing.sp16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth * (isHuman ? 0.82 : 0.88);
                return isHuman
                    ? _HumanMessage(comment: comment, maxWidth: maxWidth)
                    : _AiMessage(comment: comment, maxWidth: maxWidth);
              },
            ),
          ),
        );
    }
  }
}

/// The right-aligned layout for a [CommentAuthorType.human] message —
/// design.md §1.1.
class _HumanMessage extends StatelessWidget {
  const _HumanMessage({required this.comment, required this.maxWidth});

  final TicketComment comment;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 41),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(comment.createdAt),
                style: AionText.time.copyWith(color: c.textMuted),
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.ticketDetailYouAuthor,
                style: AionText.cardTitle.copyWith(
                  fontSize: 12.5,
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(5),
                  ),
                  color: c.surface,
                  border: Border.all(color: c.borderStrong, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  child: Text(
                    comment.content,
                    style: AionText.bodySm.copyWith(
                      color: c.textPrimary,
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            CommentAuthorAvatar(
              colors: c,
              isAi: false,
              isSystem: false,
              isDark: t.isDark,
            ),
          ],
        ),
      ],
    );
  }
}

/// The left-aligned, flat (no bubble) layout for a
/// [CommentAuthorType.ai] message — design.md §9.1 (supersedes §1.2's
/// bubble). Content renders directly on `background`, capped to
/// [maxWidth] for line-length readability.
class _AiMessage extends StatelessWidget {
  const _AiMessage({required this.comment, required this.maxWidth});

  final TicketComment comment;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CommentAuthorAvatar(colors: c, isAi: true, isSystem: false, isDark: t.isDark),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
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
                        style: AionText.prioritySm.copyWith(color: c.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _formatTime(comment.createdAt),
                    style: AionText.time.copyWith(color: c.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: MarkdownView(source: comment.content),
                ),
              ),
              if (comment.aiModel != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    context.l10n.ticketDetailViaModel(comment.aiModel!),
                    style: AionText.time.copyWith(color: c.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The compact, centered divider layout for a
/// [CommentAuthorType.system] message — design.md §9.2 (supersedes
/// §1.3's bubble). Not a message row: no avatar, no bubble, no
/// left-alignment — the system note recedes as a light separator
/// between the human/AI turns around it.
class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.comment, required this.maxWidth});

  final TicketComment comment;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;

    // No self-padding here — unlike a bubbled message this widget relies
    // solely on ChatMessageBubble's outer wrapper for its vertical gap
    // (sp8, deliberately tighter than a normal message's sp16), matching
    // how _HumanMessage/_AiMessage also carry no padding of their own.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PhosphorIcon(
              PhosphorIcons.diamondLight,
              size: 10,
              color: c.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                comment.content,
                style: AionText.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: c.textMuted,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text('·', style: AionText.time.copyWith(color: c.textMuted)),
            const SizedBox(width: 6),
            Text(
              _formatTime(comment.createdAt),
              style: AionText.time.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats [date] as a bare `HH:mm` time string — matches
/// `CommentTile._formatTime`.
String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
