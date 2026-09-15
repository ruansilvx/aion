// test/core/utils/mouse_drag_scroll_behavior_test.dart — MouseDragScrollBehavior tests.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';

/// A horizontal, non-bouncing scrollable long enough that its content
/// overflows the viewport — mirrors `MarkdownView`'s fenced-code-block/table
/// shape (`SingleChildScrollView(scrollDirection: Axis.horizontal)`) closely
/// enough to exercise the same drag-to-scroll path `AIO-2905` found broken.
Widget _horizontalScrollable({required Key key}) {
  return Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 200,
      child: SingleChildScrollView(
        key: key,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: const SizedBox(width: 2000, height: 20),
      ),
    ),
  );
}

void main() {
  group('MouseDragScrollBehavior (AIO-2905)', () {
    test('dragDevices adds mouse without dropping the base set', () {
      const behavior = MouseDragScrollBehavior();
      expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
      // The base (non-Material) ScrollBehavior's own default set — confirms
      // this widens it rather than replacing it outright.
      expect(
        behavior.dragDevices,
        containsAll(const ScrollBehavior().dragDevices),
      );
    });

    testWidgets(
      'a mouse-kind click-drag scrolls a horizontal scrollable under '
      'MouseDragScrollBehavior — reproduces AIO-2905\'s live fix',
      (tester) async {
        final scrollableKey = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ScrollConfiguration(
              behavior: const MouseDragScrollBehavior(),
              child: _horizontalScrollable(key: scrollableKey),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(scrollableKey),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scrollable.position.pixels, 0);

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(() => gesture.removePointer());
        await gesture.down(tester.getCenter(find.byKey(scrollableKey)));
        await tester.pump(kPressTimeout);
        await gesture.moveBy(const Offset(-200, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(scrollable.position.pixels, greaterThan(0));
      },
    );

    testWidgets(
      'the same mouse-kind click-drag does NOT scroll under the base '
      'ScrollBehavior — the bug MouseDragScrollBehavior fixes, kept as a '
      'live regression control',
      (tester) async {
        final scrollableKey = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ScrollConfiguration(
              behavior: const ScrollBehavior(),
              child: _horizontalScrollable(key: scrollableKey),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(scrollableKey),
            matching: find.byType(Scrollable),
          ),
        );

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(() => gesture.removePointer());
        await gesture.down(tester.getCenter(find.byKey(scrollableKey)));
        await tester.pump(kPressTimeout);
        await gesture.moveBy(const Offset(-200, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(scrollable.position.pixels, 0);
      },
    );
  });
}
