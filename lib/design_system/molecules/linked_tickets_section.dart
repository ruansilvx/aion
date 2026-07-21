// design_system/molecules/linked_tickets_section.dart — LinkedTicketsSection widget (design-system layer).

import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// A ticket-detail section listing the board tickets (epic/story/task/
/// chat) a `page`/`resource` ticket links to via `TicketLink`. Given
/// [tickets] and an [onTap] callback, plus an optional header [trailing]
/// control (e.g. a link picker) — grouping logic (which links belong here
/// vs. [BacklinksSection]) and the actual link-creation call live in the
/// caller/[trailing] widget, not here. Promoted from
/// `DocumentationLinkedTicketsSection` (per `project.md`'s Pattern 2),
/// dropping its dependency on the tickets-feature-owned `TypeChip`/
/// `PriorityBadge` widgets in favor of a self-contained row so this
/// widget stays design-system-generic. Per
/// `aion-arch/changes/page-content-markdown-editor/design.md` §5.
class LinkedTicketsSection extends StatelessWidget {
  /// Creates a [LinkedTicketsSection] listing [tickets].
  const LinkedTicketsSection({
    super.key,
    required this.tickets,
    required this.onTap,
    this.trailing,
  });

  /// The linked board tickets to render, most relevant order as provided
  /// by the caller.
  final List<Ticket> tickets;

  /// Called with a row's ticket id when it's tapped.
  final ValueChanged<String> onTap;

  /// The header's trailing "+ Add" affordance, e.g. a link picker.
  /// `null` renders no trailing control.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  context.l10n.documentationLinkedTicketsLabel,
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
                if (tickets.isNotEmpty) ...[
                  const SizedBox(width: AionSpacing.sp8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surfaceHover,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        '${tickets.length}',
                        style: AionText.key.copyWith(color: c.textSecondary),
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
            const SizedBox(height: AionSpacing.sp12),
            if (tickets.isEmpty)
              Text(
                context.l10n.documentationLinkedTicketsEmpty,
                style: AionText.bodySm.copyWith(color: c.textMuted),
              )
            else
              Column(
                children: [
                  for (final ticket in tickets) ...[
                    _LinkRow(ticket: ticket, onTap: () => onTap(ticket.id)),
                    if (ticket != tickets.last)
                      const SizedBox(height: AionSpacing.sp8),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A single tappable link row: a type-color dot, mono ticket key, and
/// title. Per design.md §5.2.
class _LinkRow extends StatefulWidget {
  const _LinkRow({required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

class _LinkRowState extends State<_LinkRow> {
  bool _isHovered = false;
  bool _isPressed = false;

  Color _typeColor(AionColors c, TicketType type) => switch (type) {
    TicketType.story => c.typeStory,
    TicketType.epic => c.typeEpic,
    TicketType.resource => c.typeResource,
    TicketType.page => c.typePage,
    TicketType.signal => c.typeSignal,
    TicketType.release => c.typeRelease,
    // `chat` has no dedicated AionColors token yet — TypeChip itself
    // falls into this same task-colored catch-all for `chat` today, see
    // aion-arch/changes/sdd-ticket-foundation/proposal.md's design-sync
    // note. Not a new gap introduced here.
    _ => c.typeTask,
  };

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final ticket = widget.ticket;
    final typeColor = _typeColor(c, ticket.type);

    return Semantics(
      button: true,
      label: ticket.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedScale(
            scale: _isPressed ? 0.99 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: _isHovered ? c.surfaceHover : c.surface,
                border: Border.all(
                  color: _isHovered ? c.borderStrong : c.border,
                  width: 1,
                ),
                borderRadius: BorderRadius.all(AionRadius.md),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: typeColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                    const SizedBox(width: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surfaceHover,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          ticket.ticketId,
                          style: AionText.key.copyWith(color: c.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ticket.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AionText.cardTitle.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
