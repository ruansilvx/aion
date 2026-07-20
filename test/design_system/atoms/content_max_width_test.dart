// test/design_system/atoms/content_max_width_test.dart — ContentMaxWidth
// widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';

/// Wraps [child] so it receives loose constraints up to [availableWidth]
/// (via a top-left [Align], which loosens its incoming constraints),
/// letting tests control the width [ContentMaxWidth] sees as "available".
Widget _harness({required double availableWidth, required Widget child}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: availableWidth, height: 400, child: child),
    ),
  );
}

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(1400, 800);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  group('ContentMaxWidth', () {
    testWidgets('constrains a form-variant child to AionContentWidth.form', (
      tester,
    ) async {
      const childKey = Key('child');
      await tester.pumpWidget(
        _harness(
          availableWidth: 900,
          child: const ContentMaxWidth(
            variant: ContentWidthVariant.form,
            child: SizedBox(key: childKey, width: 5000, height: 40),
          ),
        ),
      );

      final size = tester.getSize(find.byKey(childKey));
      expect(size.width, AionContentWidth.form);
    });

    testWidgets(
      'constrains a reading-variant child to AionContentWidth.reading',
      (tester) async {
        const childKey = Key('child');
        await tester.pumpWidget(
          _harness(
            availableWidth: 1200,
            child: const ContentMaxWidth(
              child: SizedBox(key: childKey, width: 5000, height: 40),
            ),
          ),
        );

        final size = tester.getSize(find.byKey(childKey));
        expect(size.width, AionContentWidth.reading);
      },
    );

    testWidgets(
      'centers the constrained child within a wider available width',
      (tester) async {
        const childKey = Key('child');
        const availableWidth = 1200.0;
        await tester.pumpWidget(
          _harness(
            availableWidth: availableWidth,
            child: const ContentMaxWidth(
              child: SizedBox(key: childKey, width: 5000, height: 40),
            ),
          ),
        );

        final childLeft = tester.getTopLeft(find.byKey(childKey)).dx;
        final expectedGutter = (availableWidth - AionContentWidth.reading) / 2;
        expect(childLeft, expectedGutter);
      },
    );
  });
}
