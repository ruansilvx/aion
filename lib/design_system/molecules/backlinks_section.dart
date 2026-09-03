// design_system/molecules/backlinks_section.dart — BacklinksSection widget (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/entities/backlink_ref.dart';
import 'package:aion/features/tickets/domain/enums/backlink_origin.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// A ticket-detail section listing other `page`/`resource` tickets that
/// reference this one — either an explicit `TicketLink`
/// ([BacklinkOrigin.explicitLink]) or an inline `[[wikilink]]` discovered
/// by parsing another doc's content ([BacklinkOrigin.wikilink]). Fully
/// derived, not authored, so this section has no "+ Add" affordance and
/// is omitted entirely when [backlinks] is empty. Grouping logic (which
/// links belong here vs. [LinkedTicketsSection]) lives in the caller, not
/// this widget. Promoted from `DocumentationBacklinksSection` (per
/// `project.md`'s Pattern 2) — already fully generic (only
/// `List<BacklinkRef>` + callback), so promoted as-is. Per
/// `AIO-1350` §5 and
/// `AIO-963` §2–§3 (the
/// wikilink-origin row variant).
class BacklinksSection extends StatelessWidget {
  /// Creates a [BacklinksSection] listing [backlinks]. Renders nothing
  /// when [backlinks] is empty.
  const BacklinksSection({
    super.key,
    required this.backlinks,
    required this.onTap,
  });

  /// The backlinking rows to render, each carrying its origin.
  final List<BacklinkRef> backlinks;

  /// Called with a row's ticket id when it's tapped.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (backlinks.isEmpty) return const SizedBox.shrink();

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
                      '${backlinks.length}',
                      style: AionText.key.copyWith(color: c.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AionSpacing.sp12),
            Column(
              children: [
                for (final ref in backlinks) ...[
                  _BacklinkRow(ref: ref, onTap: () => onTap(ref.ticket.id)),
                  if (ref != backlinks.last)
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
/// instead of a colored dot, since every row here is always page/resource,
/// plus — when [BacklinkRef.origin] is [BacklinkOrigin.wikilink] — the
/// origin tag (design.md §3.2) inserted before the type label.
class _BacklinkRow extends StatefulWidget {
  const _BacklinkRow({required this.ref, required this.onTap});

  final BacklinkRef ref;
  final VoidCallback onTap;

  @override
  State<_BacklinkRow> createState() => _BacklinkRowState();
}

class _BacklinkRowState extends State<_BacklinkRow> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final ticket = widget.ref.ticket;
    final isPage = ticket.type == TicketType.page;
    final typeColor = isPage ? c.typePage : c.typeResource;
    final isWikilink = widget.ref.origin == BacklinkOrigin.wikilink;
    final isActive = _isFocused;

    return Semantics(
      button: true,
      label: ticket.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: FocusableActionDetector(
          onShowFocusHighlight: (focused) =>
              setState(() => _isFocused = focused),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
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
                    color: isActive
                        ? c.primary
                        : _isHovered
                        ? c.borderStrong
                        : c.border,
                    width: isActive ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.all(AionRadius.md),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: c.focusRing(t.isDark),
                            spreadRadius: 3,
                          ),
                        ]
                      : null,
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
                      const SizedBox(width: 8),
                      if (isWikilink) ...[
                        _WikilinkOriginTag(colors: c, fillAlpha: t.fillAlpha),
                        const SizedBox(width: 8),
                      ],
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
      ),
    );
  }
}

/// The "In text" pill marking a backlink row as content-derived
/// ([BacklinkOrigin.wikilink]) rather than explicitly authored — design.md
/// §3.2. Decoration only: no independent hover/press/focus state of its
/// own, matching `_BacklinkRow`'s "only the row itself is interactive"
/// contract.
class _WikilinkOriginTag extends StatelessWidget {
  const _WikilinkOriginTag({required this.colors, required this.fillAlpha});

  final AionColors colors;
  final double fillAlpha;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.typePage.withValues(alpha: fillAlpha),
        borderRadius: BorderRadius.all(AionRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CustomPaint(
              size: const Size(13, 13),
              painter: _BracketPairPainter(color: c.typePage),
            ),
            const SizedBox(width: 5),
            Text(
              context.l10n.wikilinkBacklinkOriginTag,
              style: AionText.badgeLabel.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the feature's signature `⟦ ⟧` bracket-pair glyph — design.md
/// §1.4: two thin 1.5px bracket strokes, not literal `[[`/`]]` text, so it
/// renders crisply at small sizes and never inherits the surrounding
/// font's bracket kerning. Shared by [_WikilinkOriginTag] (13px) and any
/// other wikilink-accent affordance that wants the same mark.
class _BracketPairPainter extends CustomPainter {
  const _BracketPairPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final armLength = size.width * 0.34;

    void drawBracket(double x, bool pointsRight) {
      final dx = pointsRight ? armLength : -armLength;
      final path = Path()
        ..moveTo(x + dx, 0)
        ..lineTo(x, 0)
        ..lineTo(x, size.height)
        ..lineTo(x + dx, size.height);
      canvas.drawPath(path, paint);
    }

    drawBracket(size.width * 0.18, true);
    drawBracket(size.width * 0.82, false);
  }

  @override
  bool shouldRepaint(covariant _BracketPairPainter oldDelegate) =>
      oldDelegate.color != color;
}
