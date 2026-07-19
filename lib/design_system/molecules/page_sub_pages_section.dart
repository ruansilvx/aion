// design_system/molecules/page_sub_pages_section.dart — PageSubPagesSection widget (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/atoms/app_button.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// A `page` ticket detail's "Sub-pages" section: a flat list of its direct
/// `page`/`resource` children, plus a header "+ Add" affordance that opens
/// the create-sub-page flow with this page pre-seeded as parent. Promoted
/// from `TicketDetailScreen`'s formerly-private `_SubPagesSection` (per
/// `project.md`'s Pattern 2) so `PageDetailScreen` can reuse it too — no
/// `Ticket`-type-specific business logic beyond a `List<Ticket>` and
/// callbacks. Per
/// `aion-arch/changes/page-content-markdown-editor/design.md` §4.
class PageSubPagesSection extends StatelessWidget {
  /// Creates a [PageSubPagesSection] listing [childDocs].
  const PageSubPagesSection({
    super.key,
    required this.childDocs,
    required this.onTap,
    required this.onAdd,
  });

  /// The direct `page`/`resource` children to render.
  final List<Ticket> childDocs;

  /// Called with a row's ticket id when it's tapped.
  final ValueChanged<String> onTap;

  /// Called when the header's "+ Add" affordance is tapped.
  final VoidCallback onAdd;

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
              children: [
                Text(
                  context.l10n.documentationSubPagesLabel,
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
                if (childDocs.isNotEmpty) ...[
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
                        '${childDocs.length}',
                        style: AionText.key.copyWith(color: c.textSecondary),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                AppButton(
                  label: context.l10n.documentationAddAction,
                  icon: PhosphorIcons.plusLight,
                  variant: AppButtonVariant.ghost,
                  onPressed: onAdd,
                ),
              ],
            ),
            const SizedBox(height: AionSpacing.sp12),
            if (childDocs.isEmpty)
              Text(
                context.l10n.documentationSubPagesEmpty,
                style: AionText.bodySm.copyWith(color: c.textMuted),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.border, width: 1),
                  borderRadius: const BorderRadius.all(AionRadius.lg),
                ),
                child: Column(
                  children: [
                    for (final child in childDocs) ...[
                      _SubPageRow(ticket: child, onTap: () => onTap(child.id)),
                      if (child != childDocs.last)
                        DecoratedBox(
                          decoration: BoxDecoration(color: c.border),
                          child: const SizedBox(height: 1),
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
}

/// A single tappable sub-page row: page icon, title, trailing chevron. Per
/// design.md §4.2.
class _SubPageRow extends StatefulWidget {
  const _SubPageRow({required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  State<_SubPageRow> createState() => _SubPageRowState();
}

class _SubPageRowState extends State<_SubPageRow> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;

    return Semantics(
      button: true,
      label: widget.ticket.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: _isPressed
                ? c.border
                : (_isHovered ? c.surfaceHover : const Color(0x00000000)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PhosphorIcon(
                    PhosphorIcons.fileTextLight,
                    size: 18,
                    color: c.typePage,
                  ),
                  const SizedBox(width: 10),
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
                  PhosphorIcon(
                    PhosphorIcons.caretRightLight,
                    size: 16,
                    color: c.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
