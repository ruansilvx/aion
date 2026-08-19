// test/design_system/molecules/markdown_view_test.dart — MarkdownView widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/domain/entities/ticket.dart';
import 'package:aion/features/tickets/domain/enums/ticket_type.dart';

/// Wraps [child] with the minimum ancestry [MarkdownView] needs:
/// [Directionality] (required by any text-rendering widget) and
/// [ThemeScope] (Aion's sole theming mechanism).
Widget _wrap(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(theme: aionThemeArctic, child: child),
  );
}

void main() {
  group('MarkdownView', () {
    testWidgets('renders headings 1-6', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MarkdownView(
            source: '# H1\n\n## H2\n\n### H3\n\n#### H4\n\n##### H5\n\n###### H6',
          ),
        ),
      );

      expect(find.text('H1'), findsOneWidget);
      expect(find.text('H2'), findsOneWidget);
      expect(find.text('H3'), findsOneWidget);
      expect(find.text('H4'), findsOneWidget);
      expect(find.text('H5'), findsOneWidget);
      expect(find.text('H6'), findsOneWidget);
    });

    testWidgets('renders a paragraph with mixed inline emphasis and a link', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MarkdownView(
            source:
                'Plain **bold** *italic* ~~strike~~ `code` [link](https://example.com) text.',
          ),
        ),
      );

      final richText = tester.widgetList<RichText>(find.byType(RichText));
      final combined = richText
          .map((w) => w.text.toPlainText())
          .join();
      expect(combined, contains('bold'));
      expect(combined, contains('italic'));
      expect(combined, contains('strike'));
      expect(combined, contains('code'));
      expect(combined, contains('link'));
    });

    testWidgets('renders bullet, ordered, nested, and task lists', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MarkdownView(
            source: '''
- Bullet one
- Bullet two
  - Nested bullet

1. Ordered one
2. Ordered two

- [ ] Unchecked task
- [x] Checked task
''',
          ),
        ),
      );

      expect(find.textContaining('Bullet one'), findsOneWidget);
      expect(find.textContaining('Bullet two'), findsOneWidget);
      expect(find.textContaining('Nested bullet'), findsOneWidget);
      expect(find.textContaining('Ordered one'), findsOneWidget);
      expect(find.textContaining('Ordered two'), findsOneWidget);
      expect(find.textContaining('Unchecked task'), findsOneWidget);
      expect(find.textContaining('Checked task'), findsOneWidget);
    });

    testWidgets('renders a fenced code block', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MarkdownView(
            source: '```dart\nfinal x = 1;\n```',
          ),
        ),
      );

      expect(find.textContaining('final x = 1;'), findsOneWidget);
    });

    testWidgets('renders a blockquote', (tester) async {
      await tester.pumpWidget(
        _wrap(const MarkdownView(source: '> A quoted line.')),
      );

      expect(find.textContaining('A quoted line.'), findsOneWidget);
    });

    testWidgets('renders a horizontal rule', (tester) async {
      await tester.pumpWidget(
        _wrap(const MarkdownView(source: 'Above\n\n---\n\nBelow')),
      );

      expect(find.textContaining('Above'), findsOneWidget);
      expect(find.textContaining('Below'), findsOneWidget);
      expect(find.byType(DecoratedBox), findsWidgets);
    });

    testWidgets('renders a GFM table', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MarkdownView(
            source: '''
| A | B |
|---|---|
| 1 | 2 |
''',
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('falls back to plain text for unrecognized input without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const MarkdownView(source: '<custom>raw html-ish content</custom>')),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('raw html-ish content'), findsOneWidget);
    });
  });

  group('MarkdownView wikilink spans', () {
    final targetTicket = Ticket(
      id: 't1',
      ticketId: 'AIO-42',
      type: TicketType.page,
      title: 'Target Title',
      status: 'backlog',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    testWidgets(
      'a resolved [[TicketId]] reference renders the target\'s live title and is tappable',
      (tester) async {
        Ticket? tapped;
        await tester.pumpWidget(
          _wrap(
            MarkdownView(
              source: '[[AIO-42]]',
              resolveWikilink: (target) =>
                  target == 'AIO-42' ? targetTicket : null,
              onWikilinkTap: (t) => tapped = t,
            ),
          ),
        );

        expect(find.text('Target Title'), findsOneWidget);
        await tester.tap(find.text('Target Title'));
        expect(tapped, targetTicket);
      },
    );

    testWidgets(
      'a resolved [[Target|Alias]] reference renders the literal alias verbatim, not the live title',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            MarkdownView(
              source: '[[AIO-42|Custom Label]]',
              resolveWikilink: (target) =>
                  target == 'AIO-42' ? targetTicket : null,
            ),
          ),
        );

        expect(find.text('Custom Label'), findsOneWidget);
        expect(find.text('Target Title'), findsNothing);
      },
    );

    testWidgets(
      'an unresolved reference renders the chip-backed treatment and is '
      'tappable-to-create when onCreateWikilinkTarget is supplied and the '
      'target does not look like a ticketId',
      (tester) async {
        String? createdTitle;
        await tester.pumpWidget(
          _wrap(
            MarkdownView(
              source: '[[Missing Page]]',
              resolveWikilink: (target) => null,
              onCreateWikilinkTarget: (title) => createdTitle = title,
            ),
          ),
        );

        final richText = tester.widgetList<RichText>(find.byType(RichText));
        final combined = richText.map((w) => w.text.toPlainText()).join();
        expect(combined, contains('[['));
        expect(combined, contains('Missing Page'));
        expect(combined, contains(']]'));

        await tester.tap(find.byType(RichText).first);
        expect(createdTitle, 'Missing Page');
      },
    );

    testWidgets(
      'an unresolved id-anchored reference is not tappable-to-create even '
      'when onCreateWikilinkTarget is supplied',
      (tester) async {
        String? createdTitle;
        await tester.pumpWidget(
          _wrap(
            MarkdownView(
              source: '[[AIO-99]]',
              resolveWikilink: (target) => null,
              onCreateWikilinkTarget: (title) => createdTitle = title,
            ),
          ),
        );

        await tester.tap(find.byType(RichText).first);
        expect(createdTitle, isNull);
      },
    );

    testWidgets(
      'every callback defaulting to null leaves [[...]] text unrecognized '
      '(existing non-page consumers unaffected)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const MarkdownView(source: 'See [[Some Page]] here.')),
        );

        final richText = tester.widgetList<RichText>(find.byType(RichText));
        final combined = richText.map((w) => w.text.toPlainText()).join();
        expect(combined, 'See [[Some Page]] here.');
      },
    );
  });
}
