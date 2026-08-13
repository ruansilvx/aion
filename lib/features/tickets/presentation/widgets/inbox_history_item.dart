// presentation/widgets/inbox_history_item.dart — InboxHistoryItem row widget + inboxAccentFor helper (presentation layer).

import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/inbox_purpose.dart';

/// Maps an [InboxPurpose] to the base `AionColors` accent its launcher
/// card, history badge, and Suggested-row treatments all key off — four
/// aliases of existing type-accent tokens, no new hues. Lives here (this
/// feature's presentation layer), not in `design_system/`, since it
/// takes the feature-local [InboxPurpose] enum and `design_system/` must
/// stay feature-agnostic per project.md's cross-feature rule. See
/// `aion-arch/changes/new-project-onboarding-inbox/design.md` §0.3.
Color inboxAccentFor(InboxPurpose purpose, AionColors c) {
  return switch (purpose) {
    InboxPurpose.brainDump => c.typeIdea,
    InboxPurpose.whatNextGuidance => c.typeStory,
    InboxPurpose.releasePlanning => c.typeRelease,
    InboxPurpose.qa => c.typeChat,
  };
}

/// Returns the short, uppercase badge label for [purpose] (e.g.
/// `"BRAIN DUMP"`, `"Q&A"`) — design.md §5.2.
String inboxPurposeBadgeLabel(BuildContext context, InboxPurpose purpose) {
  final l10n = context.l10n;
  return switch (purpose) {
    InboxPurpose.brainDump => l10n.inboxPurposeBadgeBrainDump,
    InboxPurpose.whatNextGuidance => l10n.inboxPurposeBadgeWhatNext,
    InboxPurpose.releasePlanning => l10n.inboxPurposeBadgeReleasePlanning,
    InboxPurpose.qa => l10n.inboxPurposeBadgeQa,
  };
}

/// A single Inbox history row: a purpose badge (dot + short label pill),
/// the chat's title, and a relative timestamp — whole-row-tappable, no
/// business logic of its own (matches `DocumentationTreeItem`'s
/// precedent). Per design.md §5.
class InboxHistoryItem extends StatefulWidget {
  /// Creates an [InboxHistoryItem] for [ticket] — must have a non-null
  /// [Ticket.inboxPurpose].
  const InboxHistoryItem({super.key, required this.ticket, this.onTap});

  /// The Inbox-spawned `chat` ticket this row represents.
  final Ticket ticket;

  /// Called when the row is tapped or keyboard-activated. Callers
  /// navigate via `ticketDetailRoute(ticket)` — this widget never calls
  /// `context.go` itself, matching `DocumentationTreeItem`'s precedent.
  final VoidCallback? onTap;

  @override
  State<InboxHistoryItem> createState() => _InboxHistoryItemState();
}

class _InboxHistoryItemState extends State<InboxHistoryItem> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final purpose = widget.ticket.inboxPurpose;
    final accent = purpose == null ? c.primary : inboxAccentFor(purpose, c);

    final fill = _isHovered || _isPressed ? c.surfaceHover : c.surface;
    final border = _isHovered || _isPressed ? c.borderStrong : c.border;
    final boxShadow = _isFocused
        ? AionShadows.focus(c, t.isDark)
        : const <BoxShadow>[];

    return Semantics(
      button: true,
      label: widget.ticket.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap?.call();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            child: AnimatedScale(
              scale: _isPressed ? 0.98 : 1.0,
              duration: const Duration(milliseconds: 90),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                height: 56,
                decoration: BoxDecoration(
                  color: fill,
                  border: Border.all(color: border, width: 1),
                  borderRadius: BorderRadius.all(AionRadius.md),
                  boxShadow: boxShadow,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (purpose != null)
                        _PurposeBadge(purpose: purpose, accent: accent),
                      const SizedBox(width: AionSpacing.sp12),
                      Expanded(
                        child: Text(
                          widget.ticket.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AionText.cardTitle.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AionSpacing.sp12),
                      Text(
                        formatRelativeTime(widget.ticket.createdAt),
                        style: AionText.time.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dot-plus-label pill badge (design.md §5.2) — mirrors [TypeChip]'s
/// swatch+label construction so history badges read as siblings of the
/// type chips elsewhere in the app.
class _PurposeBadge extends StatelessWidget {
  const _PurposeBadge({required this.purpose, required this.accent});

  final InboxPurpose purpose;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: t.fillAlpha),
        borderRadius: BorderRadius.all(AionRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 9, 0),
        child: SizedBox(
          height: 22,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                child: const SizedBox(width: 7, height: 7),
              ),
              const SizedBox(width: 6),
              Text(
                inboxPurposeBadgeLabel(context, purpose).toUpperCase(),
                style: AionText.chip.copyWith(color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
