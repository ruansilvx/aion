// presentation/widgets/documentation_linked_tickets_section.dart — DocumentationLinkedTicketsSection widget (presentation layer).

import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/presentation/screens/tickets_list_screen.dart'
    show TypeChip, PriorityBadge;

/// A ticket-detail section listing the board tickets (epic/story/task/
/// chat) a `page`/`resource` ticket links to via `TicketLink`. Given
/// [tickets] and an [onTap] callback — grouping logic (which links belong
/// here vs. [DocumentationBacklinksSection]) lives in `TicketsCubit
/// .loadDocumentRelations`, not this widget. Per design.md §8.3.
class DocumentationLinkedTicketsSection extends StatelessWidget {
  /// Creates a [DocumentationLinkedTicketsSection] listing [tickets].
  const DocumentationLinkedTicketsSection({
    super.key,
    required this.tickets,
    required this.onTap,
  });

  /// The linked board tickets to render, most relevant order as provided
  /// by the caller.
  final List<Ticket> tickets;

  /// Called with a row's ticket id when it's tapped.
  final ValueChanged<String> onTap;

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

/// A single tappable link row, shared shape with
/// [DocumentationBacklinksSection]'s row — kept private/duplicated per
/// file (rather than factored into a shared widget) since each carries a
/// different leading indicator (type chip here vs. type-icon chip there).
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

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final ticket = widget.ticket;

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
                    TypeChip(type: ticket.type),
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
                    PriorityBadge(priority: ticket.priority),
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
