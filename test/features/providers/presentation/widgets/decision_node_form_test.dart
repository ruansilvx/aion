// test/features/providers/presentation/widgets/decision_node_form_test.dart — DecisionNodeForm widget tests.

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/presentation/widgets/decision_node_form.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

/// Wraps [child] with an `Overlay` ancestor (needed for `SelectionMenu`'s
/// own overlay, and for [DecisionNodeForm.showAsPopover]'s), mirroring
/// `workflow_status_settings_screen_test.dart`'s `_wrap`. Added for
/// `aion-arch/changes/automation-decision-graphs` (`/verify` fix pass 2).
Widget _wrap(WidgetBuilder builder) {
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
      builder: (context, _) =>
          Overlay(initialEntries: [OverlayEntry(builder: builder)]),
    ),
  );
}

void main() {
  group('condition + parameter validation', () {
    testWidgets(
      'Save stays disabled until a condition is chosen and its parameter '
      'is valid — also a regression test for the SelectionMenu '
      'currentValue-exclusion bug that hid a single-item catalog\'s only '
      'entry (codingExecutionRetry/codingExecution) when nothing was '
      'selected yet',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            (context) => DecisionNodeForm(
              automationContext: AutomationContext.codingExecutionRetry,
              onSave:
                  ({
                    required conditionId,
                    required conditionParams,
                    required matchedBranch,
                    required unmatchedBranch,
                  }) {},
              onCreateChainedChild: (_) async => null,
              onCancel: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        AppButton saveButton() =>
            tester.widget<AppButton>(find.widgetWithText(AppButton, 'Save'));

        expect(saveButton().onPressed, isNull);

        // Open the condition picker and select its only entry —
        // previously hidden by the SelectionMenu currentValue-exclusion
        // bug (items.first was passed as currentValue while unselected).
        await tester.tap(find.text('Choose a condition'));
        await tester.pumpAndSettle();
        expect(find.text('Attempt count exceeds'), findsOneWidget);
        await tester.tap(find.text('Attempt count exceeds'));
        await tester.pumpAndSettle();

        // The default parameter value (3) is already valid, so Save is
        // enabled immediately after picking the condition.
        expect(saveButton().onPressed, isNotNull);

        // Clear the parameter field — Save disables again.
        await tester.enterText(find.byType(AppTextField), '');
        await tester.pumpAndSettle();
        expect(saveButton().onPressed, isNull);

        // A valid number re-enables it.
        await tester.enterText(find.byType(AppTextField), '5');
        await tester.pumpAndSettle();
        expect(saveButton().onPressed, isNotNull);
      },
    );
  });

  group('chaining a branch to a new condition', () {
    testWidgets('switching the matched branch to "Continue to condition" and '
        'picking a condition calls onCreateChainedChild and Save includes '
        'a DecisionBranch.toNode for it', (tester) async {
      String? createdForConditionId;
      Map<String, dynamic>? savedParams;
      DecisionBranch? savedMatchedBranch;

      await tester.pumpWidget(
        _wrap(
          (context) => DecisionNodeForm(
            automationContext: AutomationContext.codingExecutionRetry,
            onSave:
                ({
                  required conditionId,
                  required conditionParams,
                  required matchedBranch,
                  required unmatchedBranch,
                }) {
                  savedParams = conditionParams;
                  savedMatchedBranch = matchedBranch;
                },
            onCreateChainedChild: (conditionId) async {
              createdForConditionId = conditionId;
              return 'chained-child-id';
            },
            onCancel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose a condition'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attempt count exceeds'));
      await tester.pumpAndSettle();

      // Switch the matched branch's mode to "Continue to condition" —
      // both the matched and unmatched branch sections render their
      // own "End here"/"Continue to condition" toggle, so this must
      // pick the first (matched) occurrence specifically.
      await tester.tap(find.text('Continue to condition').first);
      await tester.pumpAndSettle();

      // Pick the (only) chaining condition in the now-visible nested
      // picker.
      expect(find.text('THEN CHECK'), findsOneWidget);
      await tester.tap(find.text('Choose a condition'));
      await tester.pumpAndSettle();
      // The top-level condition picker's own trigger already reads
      // "Attempt count exceeds" too, so this menu row is the second
      // (last) match rather than the only one.
      await tester.tap(find.text('Attempt count exceeds').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await tester.pumpAndSettle();

      expect(createdForConditionId, 'attemptExceedsMax');
      expect(savedParams, isNotNull);
      expect(
        savedMatchedBranch,
        const DecisionBranch.toNode('chained-child-id'),
      );
    });
  });

  group('showAsPopover', () {
    late LayerLink link;

    Widget buildHost() => _wrap(
      (context) => Column(
        children: [
          CompositedTransformTarget(
            link: link,
            child: const SizedBox(width: 40, height: 40),
          ),
          Builder(
            builder: (context) => GestureDetector(
              onTap: () => DecisionNodeForm.showAsPopover(
                context,
                link: link,
                automationContext: AutomationContext.codingExecutionRetry,
                onSave:
                    ({
                      required conditionId,
                      required conditionParams,
                      required matchedBranch,
                      required unmatchedBranch,
                    }) {},
                onCreateChainedChild: (_) async => null,
              ),
              child: const Text('Open popover'),
            ),
          ),
          // Something to tap that's clearly outside the popover chrome.
          const SizedBox(height: 400, child: Text('Outside area')),
        ],
      ),
    );

    setUp(() {
      link = LayerLink();
    });

    testWidgets('dismisses on outside-tap', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open popover'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a condition'), findsOneWidget);

      await tester.tapAt(const Offset(10, 500));
      await tester.pumpAndSettle();
      expect(find.text('Choose a condition'), findsNothing);
    });

    testWidgets('dismisses on Escape', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open popover'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a condition'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Choose a condition'), findsNothing);
    });
  });
}
