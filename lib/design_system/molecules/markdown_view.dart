// design_system/molecules/markdown_view.dart — MarkdownView read-only Markdown renderer (design-system layer).

import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:aion/core/markdown/wikilink_extractor.dart';
import 'package:aion/design_system/molecules/interactive_link_span.dart';
import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';

/// Read-only rendering of a Markdown string, parsed via `package:markdown`
/// (CommonMark + GFM extensions — tables, strikethrough, task lists,
/// autolinks) and styled with [AionText]/[AionColors] tokens. Non-Material —
/// no `flutter_markdown` or similar rendering dependency; only the upstream
/// package's pure-Dart parser is used, never a Flutter rendering dependency.
/// Any node the parser produces that isn't one of the recognized tags below
/// falls back to rendering its concatenated text content as a plain paragraph,
/// so this widget never throws on unexpected input. Per `AIO-1350` §2.
///
/// [resolveWikilink]/[onWikilinkTap]/[onCreateWikilinkTarget] add optional
/// inline `[[Target]]`/`[[Target|Alias]]` recognition (a non-standard-syntax
/// extension, same precedent as this widget's existing GFM-extension handling)
/// — see design.md §5/§6. All three default to `null`, so every other consumer
/// (comments, descriptions, anywhere Markdown renders outside a page) is
/// unaffected: `[[...]]` text there just isn't specially recognized, identical
/// to before. Per `AIO-963`.
class MarkdownView extends StatelessWidget {
  /// Creates a [MarkdownView] rendering [source].
  const MarkdownView({
    super.key,
    required this.source,
    this.resolveWikilink,
    this.onWikilinkTap,
    this.onCreateWikilinkTarget,
  });

  /// The raw Markdown source to parse and render.
  final String source;

  /// Resolves a wikilink match's target (title or `Ticket.ticketId`) to
  /// the live [Ticket] it refers to, or `null` if unresolved. `null`
  /// (the default) leaves every `[[...]]` sequence unrecognized.
  final Ticket? Function(String target)? resolveWikilink;

  /// Called when a resolved wikilink span is tapped.
  final void Function(Ticket ticket)? onWikilinkTap;

  /// Called with an unresolved wikilink's target when its span is
  /// tapped — only reachable when the target doesn't itself look like a
  /// `Ticket.ticketId` (see [WikilinkExtractor.looksLikeTicketId]'s
  /// dartdoc: an unresolved id means the target was trashed/deleted, not
  /// a new-page candidate). `null` (the default) keeps every unresolved
  /// span fully inert.
  final void Function(String title)? onCreateWikilinkTarget;

  static final _document = md.Document(extensionSet: md.ExtensionSet.gitHubWeb);

  @override
  Widget build(BuildContext context) {
    final nodes = _document.parse(source);
    final wikilink = _WikilinkContext(
      resolve: resolveWikilink,
      onTap: onWikilinkTap,
      onCreate: onCreateWikilinkTarget,
      isDark: ThemeScope.of(context).isDark,
    );
    final blocks = _buildBlocks(context, nodes, depth: 0, wikilink: wikilink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}

/// Bundles [MarkdownView]'s three optional wikilink callbacks plus the
/// active theme's `isDark` flag (needed for the unresolved chip's
/// alpha — see its linked Documentation page, §1.3) into one value
/// threaded through the
/// block/inline builder functions below, rather than widening every one
/// of their signatures by three separate parameters.
class _WikilinkContext {
  const _WikilinkContext({
    required this.resolve,
    required this.onTap,
    required this.onCreate,
    required this.isDark,
  });

  final Ticket? Function(String target)? resolve;
  final void Function(Ticket ticket)? onTap;
  final void Function(String title)? onCreate;
  final bool isDark;
}

/// Derived mono text style for inline `code` spans (design.md §2.10).
TextStyle _codeInlineStyle(AionColors c) => TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 13,
  fontWeight: FontWeight.w500,
  color: c.textPrimary,
  height: 1.5,
);

/// Derived mono text style for fenced/indented code blocks (design.md
/// §2.10).
TextStyle _codeBlockStyle(AionColors c) => TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 13,
  fontWeight: FontWeight.w400,
  color: c.textPrimary,
  height: 1.55,
);

/// Builds one widget per top-level block in [nodes], joined by
/// [AionSpacing.sp12] gaps (design.md §2's default inter-block gap).
List<Widget> _buildBlocks(
  BuildContext context,
  List<md.Node> nodes, {
  required int depth,
  required _WikilinkContext wikilink,
}) {
  final widgets = <Widget>[];
  for (var i = 0; i < nodes.length; i++) {
    if (i > 0) widgets.add(const SizedBox(height: AionSpacing.sp12));
    widgets.add(_buildBlock(context, nodes[i], depth: depth, wikilink: wikilink));
  }
  return widgets;
}

/// Converts a single block-level [node] into a widget, dispatching on
/// [md.Element.tag]. Falls back to a plain-text paragraph for any
/// unrecognized tag or bare [md.Text] encountered at block level.
Widget _buildBlock(
  BuildContext context,
  md.Node node, {
  required int depth,
  required _WikilinkContext wikilink,
}) {
  final t = ThemeScope.of(context);
  final c = t.colors;

  if (node is! md.Element) {
    return _buildParagraph(context, [node], color: c.textPrimary, wikilink: wikilink);
  }

  switch (node.tag) {
    case 'h1':
      return Text(
        node.textContent,
        style: AionText.h1.copyWith(color: c.textPrimary),
      );
    case 'h2':
      return Text(
        node.textContent,
        style: AionText.h2.copyWith(color: c.textPrimary),
      );
    case 'h3':
      return Text(
        node.textContent,
        style: AionText.dialogTitle.copyWith(color: c.textPrimary),
      );
    case 'h4':
      return Text(
        node.textContent,
        style: AionText.body.copyWith(
          color: c.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      );
    case 'h5':
      return Text(
        node.textContent,
        style: AionText.cardTitle.copyWith(color: c.textPrimary),
      );
    case 'h6':
      return Text(
        node.textContent.toUpperCase(),
        style: AionText.caption.copyWith(color: c.textSecondary),
      );
    case 'p':
      return _buildParagraph(
        context,
        node.children ?? const [],
        color: c.textPrimary,
        wikilink: wikilink,
      );
    case 'ul':
      return _buildList(context, node, ordered: false, depth: depth, wikilink: wikilink);
    case 'ol':
      return _buildList(context, node, ordered: true, depth: depth, wikilink: wikilink);
    case 'pre':
      return _buildCodeBlock(context, node);
    case 'blockquote':
      return _buildBlockquote(context, node, depth: depth, wikilink: wikilink);
    case 'hr':
      return DecoratedBox(
        decoration: BoxDecoration(color: c.border),
        child: const SizedBox(height: 1, width: double.infinity),
      );
    case 'table':
      return _buildTable(context, node);
    default:
      return _buildParagraph(
        context,
        [md.Text(node.textContent)],
        color: c.textPrimary,
        wikilink: wikilink,
      );
  }
}

/// Builds a paragraph from [inlineNodes] (already inline-parsed by
/// [md.Document.parse]) as a single [Text.rich] of [TextSpan] runs — bold,
/// italic, strikethrough, inline code, links, and (when [wikilink] carries a
/// non-`null` `resolve`) `[[...]]` wikilink spans per design.md §2.2 and
/// `AIO-963` §5/§6.
Widget _buildParagraph(
  BuildContext context,
  List<md.Node> inlineNodes, {
  required Color color,
  required _WikilinkContext wikilink,
}) {
  final c = ThemeScope.of(context).colors;
  final baseStyle = AionText.body.copyWith(color: color, height: 1.5);
  return Text.rich(
    TextSpan(
      style: baseStyle,
      children: _buildInlineSpans(inlineNodes, baseStyle, c, wikilink),
    ),
  );
}

/// Recursively converts inline [nodes] (children of a `p`/`li`/etc.) into
/// [InlineSpan]s, applying the corresponding style delta for each inline
/// tag per design.md §2.2. Bare [md.Text] runs are additionally split on
/// any `[[...]]` wikilink occurrence via [_buildWikilinkAwareTextSpans]
/// when [wikilink] carries a non-`null` `resolve`.
List<InlineSpan> _buildInlineSpans(
  List<md.Node> nodes,
  TextStyle style,
  AionColors c,
  _WikilinkContext wikilink,
) {
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    if (node is md.Text) {
      spans.addAll(
        _buildWikilinkAwareTextSpans(node.text, style, c, wikilink),
      );
      continue;
    }
    if (node is! md.Element) continue;

    switch (node.tag) {
      case 'strong':
        spans.add(
          TextSpan(
            style: const TextStyle(fontWeight: FontWeight.w800),
            children: _buildInlineSpans(
              node.children ?? const [],
              style,
              c,
              wikilink,
            ),
          ),
        );
      case 'em':
        spans.add(
          TextSpan(
            style: const TextStyle(fontStyle: FontStyle.italic),
            children: _buildInlineSpans(
              node.children ?? const [],
              style,
              c,
              wikilink,
            ),
          ),
        );
      case 'del':
        spans.add(
          TextSpan(
            style: TextStyle(
              decoration: TextDecoration.lineThrough,
              decorationColor: c.textMuted,
            ),
            children: _buildInlineSpans(
              node.children ?? const [],
              style,
              c,
              wikilink,
            ),
          ),
        );
      case 'code':
        spans.add(
          TextSpan(text: node.textContent, style: _codeInlineStyle(c)),
        );
      case 'a':
        spans.add(
          TextSpan(
            style: TextStyle(
              color: c.primary,
              decoration: TextDecoration.underline,
              decorationColor: c.primary.withValues(alpha: 0.4),
            ),
            children: _buildInlineSpans(
              node.children ?? const [],
              style,
              c,
              wikilink,
            ),
          ),
        );
      default:
        spans.add(TextSpan(text: node.textContent));
    }
  }
  return spans;
}

/// Splits [text] on every `[[Target]]`/`[[Target|Alias]]` occurrence
/// (via [WikilinkExtractor.extractReferences]) into a mix of plain
/// [TextSpan]s and wikilink spans — resolved (design.md §5: brackets
/// dropped, `typePage`-colored, underlined, tappable — see [style]'s
/// dartdoc for the interactive-states caveat) or unresolved (§6: brackets
/// kept, muted `neutralTint` chip, tappable-to-create only when
/// eligible). Returns `[TextSpan(text: text)]` unchanged when
/// [_WikilinkContext.resolve] is `null` or [text] has no `[[...]]`
/// occurrence — the exact behavior every other `MarkdownView` consumer
/// had before this extension existed.
List<InlineSpan> _buildWikilinkAwareTextSpans(
  String text,
  // The ambient paragraph/list-item style a resolved wikilink's
  // `InteractiveLinkSpan` needs explicitly — unlike a plain `TextSpan`, a
  // `WidgetSpan`'s child doesn't inherit style from its `TextSpan` ancestors,
  // so it can't rely on `Text.rich`'s usual style-merge the way every other
  // span in this file does. Added for `AIO-1998`'s `/verify` fix-up.
  TextStyle style,
  AionColors c,
  _WikilinkContext wikilink,
) {
  final resolve = wikilink.resolve;
  if (resolve == null) return [TextSpan(text: text)];
  final matches = WikilinkExtractor.extractReferences(text);
  if (matches.isEmpty) return [TextSpan(text: text)];

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    final index = text.indexOf(match.raw, cursor);
    if (index == -1) continue;
    if (index > cursor) spans.add(TextSpan(text: text.substring(cursor, index)));

    final resolved = resolve(match.target);
    if (resolved != null) {
      final onTap = wikilink.onTap;
      final label = match.alias ?? resolved.title;
      if (onTap == null) {
        // No tap handler wired — stays fully inert, same as before this
        // widget existed (see this function's own dartoc): no cursor, no
        // recognizer, no `InteractiveLinkSpan` (which requires a
        // non-null callback).
        spans.add(
          TextSpan(
            text: label,
            style: TextStyle(
              color: c.typePage,
              decoration: TextDecoration.underline,
              decorationColor: c.typePage.withValues(alpha: 0.4),
            ),
          ),
        );
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: InteractiveLinkSpan(
              text: label,
              style: style,
              color: c.typePage,
              // No dedicated `typePage`-hover token exists (unlike
              // `primary`/`primaryHover`) — inventing one is out of
              // scope for a `/verify` fix-up, so hover here still gets
              // the custom-offset underline, click cursor, focus ring,
              // and pressed dimming; only the hue itself doesn't shift.
              hoverColor: c.typePage,
              onTap: () => onTap(resolved),
              semanticsLabel: label,
            ),
          ),
        );
      }
    } else {
      final onCreate = wikilink.onCreate;
      final canCreate =
          onCreate != null && !WikilinkExtractor.looksLikeTicketId(match.target);
      final chipBackground = Paint()
        ..color = c.textSecondary.withValues(alpha: wikilink.isDark ? 0.14 : 0.09);
      final recognizer = canCreate
          ? (TapGestureRecognizer()..onTap = () => onCreate(match.target))
          : null;
      final displayText = match.alias ?? match.target;
      spans.add(
        TextSpan(
          mouseCursor: canCreate ? SystemMouseCursors.click : MouseCursor.defer,
          children: [
            TextSpan(
              text: '[[',
              style: TextStyle(color: c.textMuted, background: chipBackground),
              recognizer: recognizer,
            ),
            TextSpan(
              text: displayText,
              style: TextStyle(
                color: c.textSecondary,
                background: chipBackground,
              ),
              recognizer: recognizer,
            ),
            TextSpan(
              text: ']]',
              style: TextStyle(color: c.textMuted, background: chipBackground),
              recognizer: recognizer,
            ),
          ],
        ),
      );
    }
    cursor = index + match.raw.length;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}

/// Builds a bullet/ordered/task list from [node] (an `ul`/`ol` element),
/// recursing for nested sub-lists per design.md §2.3–§2.6.
Widget _buildList(
  BuildContext context,
  md.Element node, {
  required bool ordered,
  required int depth,
  required _WikilinkContext wikilink,
}) {
  final items = node.children ?? const [];
  final rows = <Widget>[];

  var index = 1;
  for (final item in items) {
    if (rows.isNotEmpty) rows.add(const SizedBox(height: AionSpacing.sp8));
    if (item is md.Element && item.tag == 'li') {
      rows.add(
        _buildListItem(
          context,
          item,
          ordered: ordered,
          index: index,
          depth: depth,
          wikilink: wikilink,
        ),
      );
    }
    index++;
  }

  return Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
  );
}

/// Builds a single `li` row: a marker (bullet/number/task checkbox) plus
/// its inline/nested-block content, per design.md §2.3–§2.6.
Widget _buildListItem(
  BuildContext context,
  md.Element item, {
  required bool ordered,
  required int index,
  required int depth,
  required _WikilinkContext wikilink,
}) {
  final c = ThemeScope.of(context).colors;
  final isTaskItem = item.attributes['class'] == 'task-list-item';
  final children = item.children ?? const [];

  bool? checked;
  final contentNodes = <md.Node>[];
  final nestedLists = <md.Element>[];
  for (final child in children) {
    if (isTaskItem &&
        child is md.Element &&
        child.tag == 'input' &&
        checked == null) {
      checked = child.attributes.containsKey('checked');
      continue;
    }
    if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
      nestedLists.add(child);
      continue;
    }
    if (child is md.Element && child.tag == 'p') {
      contentNodes.addAll(child.children ?? const []);
    } else {
      contentNodes.add(child);
    }
  }

  final Widget marker;
  if (isTaskItem) {
    marker = Padding(
      padding: const EdgeInsets.only(top: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: checked == true ? c.primary : c.surface,
          border: checked == true
              ? null
              : Border.all(color: c.borderStrong, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const SizedBox(width: 16, height: 16),
      ),
    );
  } else if (ordered) {
    marker = SizedBox(
      width: 24,
      child: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Text(
          '$index.',
          textAlign: TextAlign.right,
          style: AionText.body.copyWith(color: c.textSecondary),
        ),
      ),
    );
  } else {
    final size = switch (depth) {
      0 => 5.0,
      1 => 5.0,
      _ => 6.0,
    };
    marker = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: depth == 1
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.textMuted, width: 1.5),
              )
            : BoxDecoration(color: c.textSecondary, shape: BoxShape.circle),
        child: SizedBox(width: size, height: size),
      ),
    );
  }

  final content = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      isTaskItem
          ? Text.rich(
              TextSpan(
                style: AionText.body.copyWith(
                  color: checked == true ? c.textMuted : c.textPrimary,
                  decoration: checked == true
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: c.textMuted,
                ),
                children: _buildInlineSpans(
                  contentNodes,
                  AionText.body,
                  c,
                  wikilink,
                ),
              ),
            )
          : _buildParagraph(
              context,
              contentNodes,
              color: c.textPrimary,
              wikilink: wikilink,
            ),
      for (final nested in nestedLists) ...[
        const SizedBox(height: AionSpacing.sp8),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: _buildList(
            context,
            nested,
            ordered: nested.tag == 'ol',
            depth: depth + 1,
            wikilink: wikilink,
          ),
        ),
      ],
    ],
  );

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      marker,
      const SizedBox(width: 10),
      Expanded(child: content),
    ],
  );
}

/// Builds a fenced/indented code block (`pre` > `code`) — a horizontally
/// scrollable, monospace, non-wrapping block per design.md §2.7.
Widget _buildCodeBlock(BuildContext context, md.Element pre) {
  final c = ThemeScope.of(context).colors;
  final codeElements = (pre.children ?? const []).whereType<md.Element>();
  final codeElement = codeElements.isEmpty ? null : codeElements.first;
  final code = codeElement?.textContent ?? pre.textContent;
  final languageClass = codeElement?.attributes['class'];
  final language = languageClass != null && languageClass.startsWith('language-')
      ? languageClass.substring('language-'.length)
      : null;

  return DecoratedBox(
    decoration: BoxDecoration(
      color: c.surfaceHover,
      border: Border.all(color: c.border, width: 1),
      borderRadius: const BorderRadius.all(AionRadius.md),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language != null && language.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                language,
                style: AionText.caption.copyWith(color: c.textMuted),
              ),
            ),
            const SizedBox(height: AionSpacing.sp4),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code.trimRight(),
              softWrap: false,
              style: _codeBlockStyle(c),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Builds a blockquote: a left accent bar plus its recursively-rendered
/// child blocks, colored [AionColors.textSecondary], per design.md §2.8.
Widget _buildBlockquote(
  BuildContext context,
  md.Element node, {
  required int depth,
  required _WikilinkContext wikilink,
}) {
  final t = ThemeScope.of(context);
  final c = t.colors;
  final children = node.children ?? const [];

  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.primary.withValues(alpha: t.isDark ? 0.55 : 0.40),
            borderRadius: BorderRadius.circular(2),
          ),
          child: const SizedBox(width: 3),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: DefaultTextStyle.merge(
            style: TextStyle(color: c.textSecondary, fontStyle: FontStyle.italic),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildBlocks(
                context,
                children,
                depth: depth,
                wikilink: wikilink,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Builds a GFM table via Flutter's [Table] layout primitive (never
/// `DataTable`, which is Material) per design.md §2.9.
Widget _buildTable(BuildContext context, md.Element node) {
  final c = ThemeScope.of(context).colors;
  final rows = <TableRow>[];
  final columnAlignments = <int, Alignment>{};

  for (final section in node.children ?? const <md.Node>[]) {
    if (section is! md.Element) continue;
    final isHead = section.tag == 'thead';
    if (section.tag != 'thead' && section.tag != 'tbody') continue;

    for (final rowNode in section.children ?? const <md.Node>[]) {
      if (rowNode is! md.Element || rowNode.tag != 'tr') continue;
      final cells = <Widget>[];
      var colIndex = 0;
      for (final cellNode in rowNode.children ?? const <md.Node>[]) {
        if (cellNode is! md.Element) continue;
        final align = cellNode.attributes['align'];
        final alignment = switch (align) {
          'center' => Alignment.center,
          'right' => Alignment.centerRight,
          _ => Alignment.centerLeft,
        };
        columnAlignments[colIndex] = alignment;
        cells.add(
          Container(
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isHead ? c.surfaceHover : c.surface,
              border: Border(
                bottom: BorderSide(color: c.border, width: 1),
              ),
            ),
            child: Text(
              cellNode.textContent,
              style: isHead
                  ? AionText.cardTitle.copyWith(color: c.textPrimary)
                  : AionText.bodySm.copyWith(color: c.textSecondary),
            ),
          ),
        );
        colIndex++;
      }
      rows.add(TableRow(children: cells));
    }
  }

  if (rows.isEmpty) return const SizedBox.shrink();

  return ClipRRect(
    borderRadius: const BorderRadius.all(AionRadius.md),
    child: DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: c.border, width: 1)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        ),
      ),
    ),
  );
}
