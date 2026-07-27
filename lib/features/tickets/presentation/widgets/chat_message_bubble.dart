// presentation/widgets/chat_message_bubble.dart — ChatMessageBubble left/right-aligned message bubble (presentation layer).

import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket_comment.dart';
import 'package:aion/features/tickets/domain/enums/comment_author_type.dart';
import 'package:aion/features/tickets/presentation/widgets/comment_author_avatar.dart';

/// A single chat-transcript message. Human messages render right-aligned
/// with plain text; AI and system messages render left-aligned, AI
/// content rendered as Markdown via [MarkdownView]. Adapted from
/// `CommentTile`'s structure (author label/timestamp/bubble/"via
/// `<model>`" caption) but with per-author alignment, a capped bubble
/// width, and asymmetric "tail" corners instead of `CommentTile`'s
/// uniform left-aligned, full-width, plain-text rendering. Per
/// `aion-arch/changes/chat-transcript-ux-redesign/design.md` §1.
class ChatMessageBubble extends StatelessWidget {
  /// Creates a [ChatMessageBubble] rendering [comment].
  const ChatMessageBubble({super.key, required this.comment});

  /// The comment this bubble represents.
  final TicketComment comment;

  @override
  Widget build(BuildContext context) {
    final isAi = comment.authorType == CommentAuthorType.ai;
    final isHuman = comment.authorType == CommentAuthorType.human;

    return Semantics(
      label: '${comment.authorType.name} comment: ${comment.content}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AionSpacing.sp16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxBubbleWidth =
                constraints.maxWidth * (isHuman ? 0.82 : 0.88);
            return isHuman
                ? _HumanMessage(comment: comment, maxWidth: maxBubbleWidth)
                : _AiOrSystemMessage(
                    comment: comment,
                    isAi: isAi,
                    maxWidth: maxBubbleWidth,
                  );
          },
        ),
      ),
    );
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

/// The left-aligned layout shared by [CommentAuthorType.ai] and
/// [CommentAuthorType.system] messages — design.md §1.2/§1.3.
class _AiOrSystemMessage extends StatelessWidget {
  const _AiOrSystemMessage({
    required this.comment,
    required this.isAi,
    required this.maxWidth,
  });

  final TicketComment comment;
  final bool isAi;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CommentAuthorAvatar(
          colors: c,
          isAi: isAi,
          isSystem: !isAi,
          isDark: t.isDark,
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
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
                  ] else
                    Text(
                      context.l10n.ticketDetailSystemAuthor,
                      style: AionText.cardTitle.copyWith(
                        fontSize: 12.5,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w700,
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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(5),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    color: isAi ? c.primarySubtle : c.surfaceHover,
                    border: Border.all(
                      color: isAi ? c.aiBubbleBorder(t.isDark) : c.border,
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: isAi
                        ? const EdgeInsets.fromLTRB(13, 11, 13, 11)
                        : const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 9,
                          ),
                    child: isAi
                        ? MarkdownView(source: comment.content)
                        : Text(
                            comment.content,
                            style: AionText.bodySm.copyWith(
                              color: c.textSecondary,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                  ),
                ),
              ),
              if (isAi && comment.aiModel != null) ...[
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

/// Formats [date] as a bare `HH:mm` time string — matches
/// `CommentTile._formatTime`.
String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
