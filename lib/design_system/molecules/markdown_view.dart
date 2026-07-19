// design_system/molecules/markdown_view.dart — MarkdownView read-only Markdown renderer (design-system layer).

import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:aion/design_system/tokens/aion_colors.dart';
import 'package:aion/design_system/tokens/aion_radius.dart';
import 'package:aion/design_system/tokens/aion_text.dart';
import 'package:aion/design_system/tokens/theme_scope.dart';

/// Read-only rendering of a Markdown string, parsed via `package:markdown`
/// (CommonMark + GFM extensions — tables, strikethrough, task lists,
/// autolinks) and styled with [AionText]/[AionColors] tokens. Non-Material
/// — no `flutter_markdown` or similar rendering dependency; only the
/// upstream package's pure-Dart parser is used, never a Flutter rendering
/// dependency. Any node the parser produces that isn't one of the
/// recognized tags below falls back to rendering its concatenated text
/// content as a plain paragraph, so this widget never throws on
/// unexpected input. Per
/// `aion-arch/changes/page-content-markdown-editor/design.md` §2.
class MarkdownView extends StatelessWidget {
  /// Creates a [MarkdownView] rendering [source].
  const MarkdownView({super.key, required this.source});

  /// The raw Markdown source to parse and render.
  final String source;

  static final _document = md.Document(extensionSet: md.ExtensionSet.gitHubWeb);

  @override
  Widget build(BuildContext context) {
    final nodes = _document.parse(source);
    final blocks = _buildBlocks(context, nodes, depth: 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
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
}) {
  final widgets = <Widget>[];
  for (var i = 0; i < nodes.length; i++) {
    if (i > 0) widgets.add(const SizedBox(height: AionSpacing.sp12));
    widgets.add(_buildBlock(context, nodes[i], depth: depth));
  }
  return widgets;
}

/// Converts a single block-level [node] into a widget, dispatching on
/// [md.Element.tag]. Falls back to a plain-text paragraph for any
/// unrecognized tag or bare [md.Text] encountered at block level.
Widget _buildBlock(BuildContext context, md.Node node, {required int depth}) {
  final t = ThemeScope.of(context);
  final c = t.colors;

  if (node is! md.Element) {
    return _buildParagraph(context, [node], color: c.textPrimary);
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
      );
    case 'ul':
      return _buildList(context, node, ordered: false, depth: depth);
    case 'ol':
      return _buildList(context, node, ordered: true, depth: depth);
    case 'pre':
      return _buildCodeBlock(context, node);
    case 'blockquote':
      return _buildBlockquote(context, node, depth: depth);
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
      );
  }
}

/// Builds a paragraph from [inlineNodes] (already inline-parsed by
/// [md.Document.parse]) as a single [Text.rich] of [TextSpan] runs — bold,
/// italic, strikethrough, inline code, and links per design.md §2.2.
Widget _buildParagraph(
  BuildContext context,
  List<md.Node> inlineNodes, {
  required Color color,
}) {
  final c = ThemeScope.of(context).colors;
  final baseStyle = AionText.body.copyWith(color: color, height: 1.5);
  return Text.rich(
    TextSpan(
      style: baseStyle,
      children: _buildInlineSpans(inlineNodes, baseStyle, c),
    ),
  );
}

/// Recursively converts inline [nodes] (children of a `p`/`li`/etc.) into
/// [InlineSpan]s, applying the corresponding style delta for each inline
/// tag per design.md §2.2.
List<InlineSpan> _buildInlineSpans(
  List<md.Node> nodes,
  TextStyle style,
  AionColors c,
) {
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    if (node is md.Text) {
      spans.add(TextSpan(text: node.text));
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
            ),
          ),
        );
      default:
        spans.add(TextSpan(text: node.textContent));
    }
  }
  return spans;
}

/// Builds a bullet/ordered/task list from [node] (an `ul`/`ol` element),
/// recursing for nested sub-lists per design.md §2.3–§2.6.
Widget _buildList(
  BuildContext context,
  md.Element node, {
  required bool ordered,
  required int depth,
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
                ),
              ),
            )
          : _buildParagraph(context, contentNodes, color: c.textPrimary),
      for (final nested in nestedLists) ...[
        const SizedBox(height: AionSpacing.sp8),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: _buildList(
            context,
            nested,
            ordered: nested.tag == 'ol',
            depth: depth + 1,
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
              children: _buildBlocks(context, children, depth: depth),
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
