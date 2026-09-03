// presentation/widgets/comment_author_avatar.dart — CommentAuthorAvatar shared avatar disc (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/design_system/design_system.dart';

/// A comment/message's leading avatar disc — a sparkle glyph square for
/// AI-authored content, a quiet neutral hexagon-glyph square for system
/// content, a "U" initial circle otherwise. Shared by `CommentTile` (the
/// plain, non-chat ticket comment thread) and `ChatMessageBubble` (the
/// chat transcript) — promoted from a `TicketDetailScreen`-private
/// `_Avatar` class to its own file so both can use it across files. Per
/// `AIO-482` §1.0.
class CommentAuthorAvatar extends StatelessWidget {
  /// Creates a [CommentAuthorAvatar]. Exactly one of [isAi]/[isSystem]
  /// should be `true`, or neither (human).
  const CommentAuthorAvatar({
    super.key,
    required this.colors,
    required this.isAi,
    required this.isSystem,
    required this.isDark,
  });

  /// The active theme's color tokens.
  final AionColors colors;

  /// Whether this avatar represents an AI-authored comment.
  final bool isAi;

  /// Whether this avatar represents a system-authored comment.
  final bool isSystem;

  /// Whether the active theme is Obsidian (dark) — drives the AI glow's
  /// opacity via [AionShadows.aiGlow].
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    if (isAi) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: BorderRadius.circular(9),
          boxShadow: AionShadows.aiGlow(c, isDark),
        ),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: PhosphorIcon(
              PhosphorIcons.sparkleLight,
              size: 14,
              color: const Color(0xFFFFFFFF), // white glyph
            ),
          ),
        ),
      );
    }

    if (isSystem) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceHover,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.border, width: 1),
        ),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: PhosphorIcon(
              PhosphorIcons.hexagonLight,
              size: 14,
              color: c.textMuted,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Text(
            'U',
            style: AionText.prioritySm.copyWith(color: const Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
  }
}
