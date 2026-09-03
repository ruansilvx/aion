// design_system/molecules/wikilink_suggestion_list.dart — WikilinkSuggestionItem + WikilinkSuggestionList overlay body (design-system layer).

import 'package:flutter/widgets.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// A single candidate row for [WikilinkSuggestionList] — a small,
/// feature-agnostic value type, not a `Ticket`, keeping `MarkdownEditor`
/// domain-free. [ticketId] is what actually gets inserted into the
/// editor on selection; [title]/[breadcrumb] back the row's display only.
class WikilinkSuggestionItem {
  /// Creates a [WikilinkSuggestionItem].
  const WikilinkSuggestionItem({
    required this.ticketId,
    required this.title,
    this.breadcrumb,
  });

  /// The candidate's `Ticket.ticketId` — inserted verbatim as `[[ticketId]]`.
  final String ticketId;

  /// The candidate's display title.
  final String title;

  /// An optional ancestor-path subtitle, omitted (not empty) for a
  /// root-level candidate.
  final String? breadcrumb;
}

/// The `[[`-triggered autocomplete overlay's full body — panel chrome,
/// header strip, scrollable candidate rows, the empty-query populated
/// state, and the no-matches block — everything inside `MarkdownEditor`'s
/// `CompositedTransformFollower`. `MarkdownEditor` owns only the caret-
/// anchored positioning and `Escape`/outside-tap dismissal; this widget
/// is otherwise self-contained and reusable, following the same
/// promotion-eligible genericness every other `design_system/` widget
/// holds to (`items`/[onSelected] carry no domain-entity type). Per
/// `AIO-963` §4.
class WikilinkSuggestionList extends StatefulWidget {
  /// Creates a [WikilinkSuggestionList]. [items] is the already-filtered
  /// candidate set for the live [query] (empty [query] with non-empty
  /// [items] renders design.md §4.4's populated empty-query state; empty
  /// [items] renders §4.5's no-matches block). [onCreatePressed] wires
  /// the no-matches block's "Press ↵ to create it" line — omit (leave
  /// `null`) to render that block informational-only, per design.md
  /// §4.5's stated MVP fallback.
  const WikilinkSuggestionList({
    super.key,
    required this.items,
    required this.onSelected,
    this.query = '',
    this.onCreatePressed,
    this.highlightedIndex = 0,
  });

  /// The already-filtered candidates to render as rows.
  final List<WikilinkSuggestionItem> items;

  /// Called with the chosen item when a row is selected (tap, Enter, or
  /// Space on a focused row).
  final ValueChanged<WikilinkSuggestionItem> onSelected;

  /// The live in-progress query text, echoed in the header strip and
  /// (when [items] is empty) the no-matches message.
  final String query;

  /// Called when the no-matches block's create affordance is activated.
  /// `null` renders that block informational-only, with no create
  /// affordance and no Enter-key behavior — `MarkdownEditor` is the one
  /// that actually binds the `Enter` key to this callback, since it
  /// already owns the overlay's outer `Focus`/`onKeyEvent` wrapper for
  /// `Escape`.
  final VoidCallback? onCreatePressed;

  /// The keyboard-highlighted row index (design.md §4.3's "Focused"
  /// state), driven externally by [MarkdownEditor] rather than by real
  /// Flutter focus — the text field itself must keep actual keyboard
  /// focus while `[[query` is being typed, so `↑`/`↓`/`Enter` are
  /// intercepted at that level and reflected here as a plain index
  /// rather than moving focus onto a row. Defaults to `0` (first row),
  /// matching design.md §4.2/§4.4's "first row autofocuses on open".
  /// Ignored (no row highlighted) when out of range for [items].
  final int highlightedIndex;

  @override
  State<WikilinkSuggestionList> createState() => _WikilinkSuggestionListState();
}

class _WikilinkSuggestionListState extends State<WikilinkSuggestionList> {
  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context);
    final c = t.colors;
    final items = widget.items;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border, width: 1),
        borderRadius: const BorderRadius.all(AionRadius.lg),
        boxShadow: [
          // §1.3 `overlayShadow` — routed through a commented literal
          // (not `Colors.black`, which pulls in `material.dart` for a
          // bare color constant) since no existing `AionShadows` method
          // matches these exact values (40 blur / -12 spread / (0, 18)
          // offset / 0.66-0.22 alpha).
          BoxShadow(
            color: const Color(0xFF000000).withValues(
              alpha: t.isDark ? 0.66 : 0.22,
            ),
            blurRadius: 40,
            spreadRadius: -12,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(AionRadius.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 300,
            maxWidth: 300,
            maxHeight: 284,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  '[[ ${widget.query}',
                  style: AionText.caption.copyWith(color: c.textMuted),
                ),
              ),
              Flexible(
                child: items.isEmpty
                    ? _NoMatches(
                        query: widget.query,
                        onCreatePressed: widget.onCreatePressed,
                      )
                    : SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < items.length; i++)
                              _SuggestionRow(
                                item: items[i],
                                query: widget.query,
                                highlighted: i == widget.highlightedIndex,
                                onTap: () => widget.onSelected(items[i]),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// design.md §4.2/§4.3 — a single selectable candidate row. Not built on
/// `OverlayMenuItem`: that wrapper doesn't expose its internal hover/
/// focus state back to a caller-supplied `child`, and this row needs that
/// state to conditionally show the "↵ inserts this" hint (§4.2's item 3)
/// — so this mirrors `OverlayMenuItem`'s own
/// `MouseRegion`/`FocusableActionDetector`/`GestureDetector` nesting and
/// fill formula directly instead (same precedent
/// `TicketParentPicker._CandidateRow` already sets for a self-contained
/// overlay row).
class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({
    required this.item,
    required this.query,
    required this.highlighted,
    required this.onTap,
  });

  final WikilinkSuggestionItem item;
  final String query;

  /// Whether `MarkdownEditor`'s own `↑`/`↓` handling currently highlights
  /// this row — see [WikilinkSuggestionList.highlightedIndex]'s dartdoc
  /// for why this is a plain external flag rather than real Flutter
  /// focus.
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final isActive = _isHovered || _isFocused || widget.highlighted;
    final fill = _isPressed
        ? c.border
        : isActive
        ? c.surfaceHover
        : const Color(0x00000000);

    return Semantics(
      button: true,
      label: widget.item.title,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: FocusableActionDetector(
          onShowFocusHighlight: (v) => setState(() => _isFocused = v),
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              decoration: BoxDecoration(color: fill),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.typePage,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 7, height: 7),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AionText.cardTitle.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                          if (widget.item.breadcrumb != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.item.breadcrumb!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AionText.breadcrumb.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Text(
                        '↵',
                        style: AionText.caption.copyWith(
                          color: c.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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

/// design.md §4.5 — the centered informational block shown when [query]
/// matched no candidates. Enter-to-create itself is handled by
/// `MarkdownEditor`'s own outer `Focus`; this block's "Press ↵ to create
/// it" line is a plain (optionally tappable, when [onCreatePressed] is
/// supplied) hint, not a second key binding.
class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query, required this.onCreatePressed});

  final String query;
  final VoidCallback? onCreatePressed;

  @override
  Widget build(BuildContext context) {
    final c = ThemeScope.of(context).colors;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(18, 18),
            painter: _BracketPairPainter(color: c.textMuted),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.wikilinkSuggestionNoMatches(query),
            textAlign: TextAlign.center,
            style: AionText.body.copyWith(color: c.textSecondary),
          ),
          if (onCreatePressed != null) ...[
            const SizedBox(height: 10),
            Text(
              context.l10n.wikilinkSuggestionCreateHint,
              textAlign: TextAlign.center,
              style: AionText.bodySm.copyWith(color: c.typePage),
            ),
          ],
        ],
      ),
    );
    if (onCreatePressed == null) return body;
    return GestureDetector(onTap: onCreatePressed, child: body);
  }
}

/// Draws the feature's signature `⟦ ⟧` bracket-pair glyph — design.md
/// §1.4: two thin 1.5px bracket strokes, not literal `[[`/`]]` text, so it
/// renders crisply at small sizes and never inherits the surrounding
/// font's bracket kerning. A small, self-contained duplicate of
/// `backlinks_section.dart`'s identical private painter — promoting a
/// two-line `CustomPainter` to its own shared file would be more
/// indirection than the glyph itself warrants.
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
