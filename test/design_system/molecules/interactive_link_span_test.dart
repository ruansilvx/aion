// test/design_system/molecules/interactive_link_span_test.dart — InteractiveLinkSpan widget tests.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';

const _color = Color(0xFF2E86D4);
const _hoverColor = Color(0xFF1E6DB6);

/// Wraps [child] in a `WidgetsApp` (not just `Directionality`) so the
/// default `Enter`/`Space`/`Tab` `Shortcuts`→`Intent` bindings the real
/// app root provides are present — without them, `ActivateIntent`/
/// `NextFocusIntent` never fire and the keyboard assertions below would
/// silently no-op. Mirrors `overlay_menu_item_test.dart`'s own `_wrap`.
///
/// Precedes [child] with a plain `autofocus` dummy [Focus] node — with
/// nothing focused yet, `primaryFocus` is `null` in this minimal harness
/// (no real `Navigator`/root focus scope to fall back to) and a bare
/// `Tab` key is a no-op; every keyboard test below sends one `Tab` first
/// to move off this dummy and onto the actual widget under test, exactly
/// mirroring how `overlay_menu_item_test.dart`'s own Tab test starts
/// from an `autofocus: true` row rather than from nothing.
Widget _wrap(Widget child) {
  return WidgetsApp(
    color: const Color(0xFF000000),
    builder: (context, _) => Center(
      child: Text.rich(
        TextSpan(
          children: [
            const WidgetSpan(
              child: Focus(autofocus: true, child: SizedBox.shrink()),
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: child,
            ),
          ],
        ),
      ),
    ),
  );
}

TextStyle _styleOf(WidgetTester tester) => tester
    .widget<AnimatedDefaultTextStyle>(find.byType(AnimatedDefaultTextStyle))
    .style;

/// The `CustomPaint` [InteractiveLinkSpan] itself renders — scoped as a
/// descendant, since a bare `find.byType(CustomPaint)` also matches
/// `WidgetsApp`'s/`RichText`'s own internal painters.
CustomPaint _linkPaintOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(InteractiveLinkSpan),
        matching: find.byType(CustomPaint),
      ),
    )
    .first;

void main() {
  setUp(() {
    // Same rationale as overlay_menu_item_test.dart: force keyboard-mode
    // focus highlighting so the ring assertions below are deterministic.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });

  testWidgets('renders text underlined in color at rest, and activates on tap', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        InteractiveLinkSpan(
          text: 'Board Filtering & Saved Views',
          style: const TextStyle(fontSize: 13),
          color: _color,
          hoverColor: _hoverColor,
          onTap: () => tapped = true,
          semanticsLabel: 'Board Filtering & Saved Views',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Board Filtering & Saved Views'), findsOneWidget);
    expect(_styleOf(tester).color, _color);
    expect(_styleOf(tester).decoration, TextDecoration.underline);
    // No hover custom-paint underline, no focus ring, while idle.
    expect(_linkPaintOf(tester).painter, isNull);
    expect(find.byType(DecoratedBox), findsNothing);

    await tester.tap(find.byType(InteractiveLinkSpan));
    expect(tapped, isTrue);
  });

  testWidgets(
    'hovering swaps in hoverColor, the custom underline painter, and the click cursor',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          InteractiveLinkSpan(
            text: 'Board Filtering & Saved Views',
            style: const TextStyle(fontSize: 13),
            color: _color,
            hoverColor: _hoverColor,
            onTap: () {},
            semanticsLabel: 'Board Filtering & Saved Views',
          ),
        ),
      );
      await tester.pump();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byType(InteractiveLinkSpan)),
      );
      await tester.pump();

      expect(_styleOf(tester).color, _hoverColor);
      // The plain TextStyle underline is switched off in favor of the
      // custom-offset one (design.md §2.4.1's hover row).
      expect(_styleOf(tester).decoration, isNull);
      expect(_linkPaintOf(tester).painter, isNotNull);

      final region = tester
          .widgetList<MouseRegion>(
            find.descendant(
              of: find.byType(InteractiveLinkSpan),
              matching: find.byType(MouseRegion),
            ),
          )
          .first;
      expect(region.cursor, SystemMouseCursors.click);
    },
  );

  testWidgets(
    'Tab-focusing shows the keyboard focus ring and Enter activates it',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          InteractiveLinkSpan(
            text: 'Board Filtering & Saved Views',
            style: const TextStyle(fontSize: 13),
            color: _color,
            hoverColor: _hoverColor,
            onTap: () => tapped = true,
            semanticsLabel: 'Board Filtering & Saved Views',
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DecoratedBox), findsNothing);

      // The dummy autofocus node from _wrap already holds focus on
      // mount — one Tab moves off it and onto the widget under test.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Ring visible, still underlined the plain way (not the hover
      // custom-paint one — this is keyboard focus, not pointer hover).
      expect(find.byType(DecoratedBox), findsOneWidget);
      expect(_styleOf(tester).color, _color);
      expect(_styleOf(tester).decoration, TextDecoration.underline);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, isTrue);
    },
  );

  testWidgets('pressing dims hoverColor to 80% while the pointer is down', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        InteractiveLinkSpan(
          text: 'Board Filtering & Saved Views',
          style: const TextStyle(fontSize: 13),
          color: _color,
          hoverColor: _hoverColor,
          onTap: () {},
          semanticsLabel: 'Board Filtering & Saved Views',
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InteractiveLinkSpan)),
    );
    await tester.pump();

    expect(_styleOf(tester).color, _hoverColor.withValues(alpha: 0.80));

    await gesture.up();
    await tester.pump();
  });
}
