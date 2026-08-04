// test/design_system/molecules/overlay_menu_item_test.dart — OverlayMenuItem widget tests.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';

/// Wraps [child] in a `WidgetsApp` (not just `Directionality`) so the
/// default `Tab`/`Enter`/`Space` `Shortcuts`→`Intent` bindings the real
/// app root provides are present — without them, `ActivateIntent`/
/// `NextFocusIntent` never fire and every keyboard assertion below would
/// silently no-op.
Widget _wrap(Widget child) {
  return WidgetsApp(
    color: const Color(0xFF000000),
    builder: (context, _) =>
        ThemeScope(theme: aionThemeObsidian, child: Center(child: child)),
  );
}

/// Reads the row's current fill straight off its `AnimatedContainer`.
Color _fillOf(WidgetTester tester, [Finder? finder]) {
  final box = tester.widget<AnimatedContainer>(
    finder ?? find.byType(AnimatedContainer),
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  setUp(() {
    // Focus rings/hover fills are suppressed under
    // FocusHighlightMode.touch, which FocusHighlightStrategy.automatic
    // can select by default in a test environment with no prior
    // keyboard interaction. Force traditional (keyboard) mode so
    // OverlayMenuItem's focus fill assertions below are deterministic.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });

  testWidgets('autofocus row focuses on mount and paints the hover-equivalent fill', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        OverlayMenuItem(
          onTap: () => tapped = true,
          semanticsLabel: 'Delete ticket',
          accent: obsidian.danger,
          autofocus: true,
          child: const SizedBox(width: 100, height: 30),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      _fillOf(tester),
      obsidian.danger.withValues(alpha: fillAlphaObsidian),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('a neutral row defaults transparent and steps through surfaceHover/border', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OverlayMenuItem(
          onTap: () {},
          semanticsLabel: 'Task',
          child: const SizedBox(width: 100, height: 30),
        ),
      ),
    );
    await tester.pump();
    expect(_fillOf(tester), const Color(0x00000000));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(OverlayMenuItem)),
    );
    await tester.pump();
    expect(_fillOf(tester), obsidian.border);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('restingTinted paints the resting accentTint fill until pressed deepens it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OverlayMenuItem(
          onTap: () {},
          semanticsLabel: 'Promote to Epic',
          accent: obsidian.typeEpic,
          restingTinted: true,
          child: const SizedBox(width: 100, height: 30),
        ),
      ),
    );
    await tester.pump();
    expect(_fillOf(tester), obsidian.accentTint(obsidian.typeEpic, true));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(OverlayMenuItem)),
    );
    await tester.pump();
    expect(
      _fillOf(tester),
      obsidian.pressedAccentTint(obsidian.typeEpic, true),
    );

    await gesture.up();
    await tester.pump();
  });

  testWidgets('Tab moves the focus fill from row 0 to row 1', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OverlayMenuItem(
              onTap: () {},
              semanticsLabel: 'Row 0',
              autofocus: true,
              child: const SizedBox(width: 100, height: 30),
            ),
            OverlayMenuItem(
              onTap: () {},
              semanticsLabel: 'Row 1',
              child: const SizedBox(width: 100, height: 30),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final containers = find.byType(AnimatedContainer);
    expect(_fillOf(tester, containers.at(0)), obsidian.surfaceHover);
    expect(_fillOf(tester, containers.at(1)), const Color(0x00000000));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(_fillOf(tester, containers.at(0)), const Color(0x00000000));
    expect(_fillOf(tester, containers.at(1)), obsidian.surfaceHover);
  });

  testWidgets('holding Enter paints the pressed fill for the hold duration, mirroring mouse-down', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OverlayMenuItem(
          onTap: () {},
          semanticsLabel: 'Delete ticket',
          accent: obsidian.danger,
          autofocus: true,
          child: const SizedBox(width: 100, height: 30),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Before any key: the autofocus hover-equivalent fill.
    expect(
      _fillOf(tester),
      obsidian.danger.withValues(alpha: fillAlphaObsidian),
    );

    // Key held down: pressed fill, deeper than the hover/focus wash.
    await simulateKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_fillOf(tester), obsidian.pressedAccentTint(obsidian.danger, true));

    // Key released: back to the hover-equivalent (focused) fill.
    await simulateKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      _fillOf(tester),
      obsidian.danger.withValues(alpha: fillAlphaObsidian),
    );
  });

  testWidgets('a disabled row dims its child, ignores taps, and shows the basic cursor', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        OverlayMenuItem(
          onTap: () => tapped = true,
          semanticsLabel: 'Disabled row',
          enabled: false,
          child: const SizedBox(width: 100, height: 30),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Opacity), findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.45);

    await tester.tap(find.byType(OverlayMenuItem));
    await tester.pump();
    expect(tapped, isFalse);

    // OverlayMenuItem's own outer MouseRegion plus
    // FocusableActionDetector's internal one both match by type — take
    // the outermost (first in a depth-first descendant search), which
    // is the one OverlayMenuItem itself sets `cursor` on.
    final region = tester
        .widgetList<MouseRegion>(
          find.descendant(
            of: find.byType(OverlayMenuItem),
            matching: find.byType(MouseRegion),
          ),
        )
        .first;
    expect(region.cursor, SystemMouseCursors.basic);
  });
}
