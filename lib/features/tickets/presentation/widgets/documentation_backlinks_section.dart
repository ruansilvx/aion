// presentation/widgets/documentation_backlinks_section.dart — DocumentationBacklinksSection widget (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// A ticket-detail section listing other `page`/`resource` tickets that
/// link to this one via `TicketLink` — derived, not authored, so this
/// section has no "+ Add" affordance and is omitted entirely when
/// [tickets] is empty. Grouping logic (which links belong here vs.
/// [DocumentationLinkedTicketsSection]) lives in `TicketsCubit
/// .loadDocumentRelations`, not this widget. Per design.md §8.4.
class DocumentationBacklinksSection extends StatelessWidget {
  /// Creates a [DocumentationBacklinksSection] listing [tickets]. Renders
  /// nothing when [tickets] is empty.
  const DocumentationBacklinksSection({
    super.key,
    required this.tickets,
    required this.onTap,
  });

  /// The backlinking `page`/`resource` tickets to render.
  final List<Ticket> tickets;

  /// Called with a row's ticket id when it's tapped.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) return const SizedBox.shrink();

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
                  context.l10n.documentationBacklinksLabel,
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
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
            ),
            const SizedBox(height: AionSpacing.sp12),
            Column(
              children: [
                for (final ticket in tickets) ...[
                  _BacklinkRow(ticket: ticket, onTap: () => onTap(ticket.id)),
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

/// A single tappable backlink row: a type-icon chip (page vs. resource)
/// instead of [TypeChip], since every row here is always page/resource.
class _BacklinkRow extends StatefulWidget {
  const _BacklinkRow({required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  State<_BacklinkRow> createState() => _BacklinkRowState();
}

class _BacklinkRowState extends State<_BacklinkRow> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final ticket = widget.ticket;
    final isPage = ticket.type == TicketType.page;
    final typeColor = isPage ? c.typePage : c.typeResource;

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
                        color: typeColor.withValues(alpha: t.fillAlpha),
                        borderRadius: BorderRadius.all(AionRadius.iconBtnSm),
                      ),
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: Center(
                          child: PhosphorIcon(
                            isPage
                                ? PhosphorIcons.fileTextLight
                                : PhosphorIcons.bookmarkSimpleLight,
                            size: 15,
                            color: typeColor,
                          ),
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
                    const SizedBox(width: 10),
                    Text(
                      (isPage
                              ? context.l10n.ticketTypePage
                              : context.l10n.ticketTypeResource)
                          .toUpperCase(),
                      style: AionText.chip.copyWith(color: typeColor),
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
