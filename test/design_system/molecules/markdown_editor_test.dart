// test/design_system/molecules/markdown_editor_test.dart — MarkdownEditor autocomplete widget tests.

import 'package:flutter/material.dart' show TextField;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

/// Wraps [child] in a `WidgetsApp` with `home` (not `builder`), so the
/// `Overlay`/`Localizations` ancestry [MarkdownEditor]'s own `[[`-triggered
/// [WikilinkSuggestionList] overlay and `AppTextField`'s `TextField` both
/// need are present — mirrors `linked_tickets_section_test.dart`'s
/// `_wrap`. A wide [width] (above the 640 narrow/wide breakpoint) keeps
/// the raw textarea always visible, without needing to first tap through
/// the narrow layout's view/edit toggle; wrapped in a
/// [SingleChildScrollView] since every real host (e.g.
/// `PageDetailScreen`) does the same for `MarkdownEditor`'s `_Wide`
/// raw/preview split.
Widget _wrap(Widget child, {double width = 800}) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(800, 600)),
    child: ThemeScope(
      theme: aionThemeArctic,
      child: WidgetsApp(
        color: aionThemeArctic.colors.primary,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
            PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (context, _, _) => builder(context),
            ),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 600,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
}

String _currentText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  group('MarkdownEditor [[ autocomplete', () {
    testWidgets(
      'typing [[ opens the caret-anchored overlay when wikilinkSuggestions is supplied',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            MarkdownEditor(
              initialValue: '',
              onCommit: (_) async {},
              semanticsLabel: 'content',
              wikilinkSuggestions: (query) => const [
                WikilinkSuggestionItem(ticketId: 'AIO-1', title: 'Auth Notes'),
              ],
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), '[[');
        await tester.pump();

        expect(find.byType(WikilinkSuggestionList), findsOneWidget);
        expect(find.text('Auth Notes'), findsOneWidget);
      },
    );

    testWidgets(
      'typing [[ is a no-op (no overlay) when wikilinkSuggestions is null',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            MarkdownEditor(
              initialValue: '',
              onCommit: (_) async {},
              semanticsLabel: 'content',
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), '[[');
        await tester.pump();

        expect(find.byType(WikilinkSuggestionList), findsNothing);
      },
    );

    testWidgets(
      'selecting a suggestion inserts [[<ticketId>]], not the title',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            MarkdownEditor(
              initialValue: '',
              onCommit: (_) async {},
              semanticsLabel: 'content',
              wikilinkSuggestions: (query) => const [
                WikilinkSuggestionItem(ticketId: 'AIO-1', title: 'Auth Notes'),
              ],
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), '[[Auth');
        await tester.pump();
        await tester.tap(find.text('Auth Notes'));
        await tester.pump();

        expect(_currentText(tester), '[[AIO-1]]');
        expect(find.byType(WikilinkSuggestionList), findsNothing);
      },
    );

    testWidgets(
      "the no-matches state's Enter key calls onCreatePage and inserts its "
      'result when supplied',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            MarkdownEditor(
              initialValue: '',
              onCommit: (_) async {},
              semanticsLabel: 'content',
              wikilinkSuggestions: (query) => const [],
              onCreatePage: (title) async =>
                  WikilinkSuggestionItem(ticketId: 'AIO-9', title: title),
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), '[[New Page');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(_currentText(tester), '[[AIO-9]]');
      },
    );

    testWidgets(
      "the no-matches state's Enter key is a no-op when onCreatePage is not "
      'supplied',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            MarkdownEditor(
              initialValue: '',
              onCommit: (_) async {},
              semanticsLabel: 'content',
              wikilinkSuggestions: (query) => const [],
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), '[[New Page');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(_currentText(tester), '[[New Page');
      },
    );

    testWidgets('Escape dismisses the overlay without inserting', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MarkdownEditor(
            initialValue: '',
            onCommit: (_) async {},
            semanticsLabel: 'content',
            wikilinkSuggestions: (query) => const [
              WikilinkSuggestionItem(ticketId: 'AIO-1', title: 'Auth Notes'),
            ],
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '[[');
      await tester.pump();
      expect(find.byType(WikilinkSuggestionList), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(WikilinkSuggestionList), findsNothing);
      expect(_currentText(tester), '[[');
    });

    testWidgets('an outside tap dismisses the overlay without inserting', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MarkdownEditor(
            initialValue: '',
            onCommit: (_) async {},
            semanticsLabel: 'content',
            wikilinkSuggestions: (query) => const [
              WikilinkSuggestionItem(ticketId: 'AIO-1', title: 'Auth Notes'),
            ],
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '[[');
      await tester.pump();
      expect(find.byType(WikilinkSuggestionList), findsOneWidget);

      // Far outside the overlay panel's own bounds (top-left of the
      // 800x600 test viewport, well below/right of the caret-anchored
      // panel) — the full-screen scrim behind the panel handles this.
      await tester.tapAt(const Offset(790, 590));
      await tester.pump();

      expect(find.byType(WikilinkSuggestionList), findsNothing);
      expect(_currentText(tester), '[[');
    });
  });
}
