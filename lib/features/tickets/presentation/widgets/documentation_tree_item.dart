// presentation/widgets/documentation_tree_item.dart — DocumentationTreeItem row widget (presentation layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// A single row in the Documentation section's tree (or, in flat variant,
/// its search-result list). Presentational only — no business logic;
/// expand/collapse and navigation are the caller's responsibility via
/// [onTap]/[onToggleExpand]. Per design.md §4.
class DocumentationTreeItem extends StatefulWidget {
  /// Creates a [DocumentationTreeItem] for [ticket].
  const DocumentationTreeItem({
    super.key,
    required this.ticket,
    this.depth = 0,
    this.isExpanded = false,
    this.showChevron = true,
    this.childCount,
    this.breadcrumb,
    this.onTap,
    this.onToggleExpand,
  });

  /// The `page`/`resource` ticket this row represents.
  final Ticket ticket;

  /// Nesting depth in the tree (`0` for root docs). Ignored (`leftPad` is
  /// fixed) when [showChevron] is `false` (the flat/sub-pages variants).
  final int depth;

  /// Whether this row's children are currently expanded (`page` rows
  /// only). Ignored for `resource` rows.
  final bool isExpanded;

  /// Whether to reserve the leading chevron column (tree mode) or omit it
  /// entirely (flat search-result / sub-pages-list variants — design.md
  /// §4.5/§8.2).
  final bool showChevron;

  /// Optional child-count pill shown trailing the title, for a collapsed
  /// `page` row with known children. `null` hides the pill.
  final int? childCount;

  /// Optional ancestor-path subtitle, shown under the title in flat
  /// (search-result) mode. `null` omits the second line.
  final String? breadcrumb;

  /// Called when the row is tapped or keyboard-activated.
  final VoidCallback? onTap;

  /// Called when the leading chevron is tapped (`page` rows only, when
  /// [showChevron] is `true`).
  final VoidCallback? onToggleExpand;

  @override
  State<DocumentationTreeItem> createState() => _DocumentationTreeItemState();
}

class _DocumentationTreeItemState extends State<DocumentationTreeItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  bool get _hasChevron =>
      widget.showChevron && widget.ticket.type == TicketType.page;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final isPage = widget.ticket.type == TicketType.page;
    final typeColor = isPage ? c.typePage : c.typeResource;

    final fill = _isHovered || _isPressed
        ? c.surfaceHover
        : const Color(0x00000000);
    final leftPad = widget.showChevron ? 12 + widget.depth * 20 : 14;

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
          child: AnimatedScale(
            scale: _isPressed ? 0.99 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.all(AionRadius.md),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  leftPad.toDouble(),
                  widget.breadcrumb != null ? 10 : 9,
                  14,
                  widget.breadcrumb != null ? 10 : 9,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (widget.showChevron) ...[
                      SizedBox(
                        width: 18,
                        child: _hasChevron
                            ? GestureDetector(
                                onTap: widget.onToggleExpand,
                                child: AnimatedRotation(
                                  turns: widget.isExpanded ? 0.25 : 0.0,
                                  duration: const Duration(milliseconds: 140),
                                  child: PhosphorIcon(
                                    PhosphorIcons.caretRightLight,
                                    size: 14,
                                    color: _isHovered
                                        ? c.textSecondary
                                        : c.textMuted,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 9),
                    ],
                    PhosphorIcon(
                      isPage
                          ? PhosphorIcons.fileTextLight
                          : PhosphorIcons.bookmarkSimpleLight,
                      size: 20,
                      color: typeColor,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.ticket.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AionText.cardTitle.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                          if (widget.breadcrumb != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                widget.breadcrumb!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AionText.breadcrumb.copyWith(
                                  color: c.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.childCount != null && isPage)
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
                            context.l10n.documentationChildCount(
                              widget.childCount!,
                            ),
                            style: AionText.key.copyWith(color: c.textMuted),
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
