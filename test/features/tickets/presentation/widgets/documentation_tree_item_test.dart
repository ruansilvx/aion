// test/features/tickets/presentation/widgets/documentation_tree_item_test.dart — DocumentationTreeItem widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(400, 200)),
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
        builder: (context, _) => child,
      ),
    ),
  );
}

Ticket _page({String title = 'A page'}) {
  return Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.page,
    title: title,
    status: 'backlog',
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    updatedAt: DateTime.now(),
  );
}

/// The row's own indent `Padding` — identified by its `Row` child, so it
/// isn't confused with any `Padding` introduced elsewhere in the tree
/// (including inside `AnimatedContainer`'s own implementation).
Finder _rowPadding() =>
    find.byWidgetPredicate((widget) => widget is Padding && widget.child is Row);

void main() {
  testWidgets('indent increases normally below the clamp', (tester) async {
    await tester.pumpWidget(
      _wrap(DocumentationTreeItem(ticket: _page(), depth: 3)),
    );

    final padding = tester.widget<Padding>(_rowPadding());
    expect((padding.padding as EdgeInsets).left, 12 + 3 * 20);
  });

  testWidgets(
    'indent is clamped and identical at the clamp depth and past it',
    (tester) async {
      await tester.pumpWidget(
        _wrap(DocumentationTreeItem(ticket: _page(), depth: 6)),
      );
      final atClamp = tester.widget<Padding>(_rowPadding());

      await tester.pumpWidget(
        _wrap(DocumentationTreeItem(ticket: _page(), depth: 10)),
      );
      final pastClamp = tester.widget<Padding>(_rowPadding());

      expect((atClamp.padding as EdgeInsets).left, 12 + 6 * 20);
      expect((pastClamp.padding as EdgeInsets).left, 12 + 6 * 20);
    },
  );

  testWidgets('flat mode ignores depth and keeps the fixed indent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DocumentationTreeItem(
          ticket: _page(),
          depth: 10,
          showChevron: false,
        ),
      ),
    );

    final padding = tester.widget<Padding>(_rowPadding());
    expect((padding.padding as EdgeInsets).left, 14);
  });
}
