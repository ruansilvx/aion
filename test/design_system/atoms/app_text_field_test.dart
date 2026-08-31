// test/design_system/atoms/app_text_field_test.dart — AppTextField widget
// tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

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
      builder: (_, _) => Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

void main() {
  group('AppTextField multiline minLines/maxLines invariant', () {
    // Regression coverage for the `/verify` finding on
    // `aion-arch/changes/decision-graph-agentjudgment-condition`:
    // `_buildAgentPromptField` passed `maxLines: 4`, and this widget used
    // to hand `TextField` a hardcoded `minLines: 5` for every multiline
    // field regardless of `maxLines` — violating `TextField`'s own
    // `minLines <= maxLines` assertion and crashing the instant the field
    // mounted. Every value below must build without throwing.
    for (final maxLines in [1, 3, 4, 5, 6, null]) {
      testWidgets('maxLines: $maxLines builds without throwing', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            AppTextField(
              controller: TextEditingController(),
              labelText: 'Question',
              maxLines: maxLines,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Question'), findsOneWidget);
      });
    }

    testWidgets(
      'obscureText forces single-line even when maxLines is multiline',
      (tester) async {
        // obscureText overrides maxLines to 1 (see AppTextField's own
        // dartdoc) — this must not leave a stale multiline minLines
        // behind (isMultiline is derived from the *effective* maxLines,
        // not the raw one), which would hit the same assertion.
        await tester.pumpWidget(
          _wrap(
            AppTextField(
              controller: TextEditingController(),
              obscureText: true,
              maxLines: 3,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
