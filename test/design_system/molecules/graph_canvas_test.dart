// test/design_system/molecules/graph_canvas_test.dart — GraphCanvas widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

/// Wraps [child] in the minimal `ThemeScope`/`WidgetsApp` harness every
/// other design-system widget test in this repo uses (see
/// `markdown_editor_test.dart`'s own `_wrap`). Added for
/// `aion-arch/changes/automation-decision-graphs` (`/verify` fix pass 2).
Widget _wrap(Widget child) {
  return ThemeScope(
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
  );
}

void main() {
  testWidgets('renders every node and its label text', (tester) async {
    await tester.pumpWidget(
      _wrap(
        GraphCanvas<String>(
          nodes: const [
            GraphCanvasNode(id: 'a', position: Offset(0, 0), data: 'Alpha'),
            GraphCanvasNode(id: 'b', position: Offset(300, 0), data: 'Beta'),
          ],
          edges: const [GraphCanvasEdge(fromId: 'a', toId: 'b')],
          nodeBuilder: (context, data, selected, hovered, dragging) =>
              Text(data),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('onNodeTap fires with the tapped node\'s id', (tester) async {
    String? tappedId;
    await tester.pumpWidget(
      _wrap(
        GraphCanvas<String>(
          nodes: const [
            GraphCanvasNode(id: 'only', position: Offset(0, 0), data: 'Only'),
          ],
          edges: const [],
          onNodeTap: (id) => tappedId = id,
          nodeBuilder: (context, data, selected, hovered, dragging) =>
              SizedBox(width: 100, height: 40, child: Text(data)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // GraphCanvas's plane has its own `onDoubleTap` (fit-to-view)
    // recognizer above the node's `onTap`, so — as with any nested
    // single-tap-under-double-tap gesture arena — the single tap only
    // resolves once the double-tap timeout window elapses.
    await tester.tap(find.text('Only'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tappedId, 'only');
  });

  testWidgets('renders emptyState when nodes is empty, hidden otherwise', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        GraphCanvas<String>(
          nodes: const [],
          edges: const [],
          nodeBuilder: (context, data, selected, hovered, dragging) =>
              Text(data),
          emptyState: const Text('Nothing here'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing here'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        GraphCanvas<String>(
          nodes: const [
            GraphCanvasNode(id: 'a', position: Offset(0, 0), data: 'Alpha'),
          ],
          edges: const [],
          nodeBuilder: (context, data, selected, hovered, dragging) =>
              Text(data),
          emptyState: const Text('Nothing here'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing here'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });

  test('snapToGraphCanvasLattice rounds to the nearest 24px cell', () {
    expect(snapToGraphCanvasLattice(0), 0);
    expect(snapToGraphCanvasLattice(11), 0);
    expect(snapToGraphCanvasLattice(13), 24);
    expect(snapToGraphCanvasLattice(-13), -24);
    expect(snapToGraphCanvasLattice(301), 312);
  });
}
