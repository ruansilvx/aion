// test/features/providers/presentation/widgets/decision_outline_list_test.dart — DecisionOutlineList widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_cubit.dart';
import 'package:aion/features/providers/presentation/widgets/decision_outline_list.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockDecisionGraphRepository extends Mock
    implements DecisionGraphRepository {}

/// Wraps [child] in the `ThemeScope`/`WidgetsApp`/`Overlay` harness every
/// widget test in this repo uses for a `SelectionMenu`/`DecisionNodeForm`
/// host (see `workflow_status_settings_screen_test.dart`'s `_wrap`), bound
/// to [cubit]. Added for `aion-arch/changes/automation-decision-graphs`
/// (`/verify` fix pass 2).
Widget _wrap(DecisionGraphConfigCubit cubit, Widget child) {
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
      builder: (context, _) => BlocProvider<DecisionGraphConfigCubit>.value(
        value: cubit,
        child: Overlay(initialEntries: [OverlayEntry(builder: (_) => child)]),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const DecisionNode(
        id: 'fallback',
        conditionId: 'attemptExceedsMax',
        conditionParams: {},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      ),
    );
  });

  const automationContext = AutomationContext.codingExecutionRetry;

  const rootNode = DecisionNode(
    id: 'root',
    conditionId: 'attemptExceedsMax',
    conditionParams: {'maxAttempts': 2},
    matchedBranch: DecisionBranch.toNode('child'),
    unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
  );
  const childNode = DecisionNode(
    id: 'child',
    conditionId: 'attemptExceedsMax',
    conditionParams: {'maxAttempts': 5},
    matchedBranch: DecisionBranch.terminal(DecisionOutcome.decline),
    unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
  );

  late MockDecisionGraphRepository repository;
  late DecisionGraphConfigCubit cubit;

  setUp(() {
    repository = MockDecisionGraphRepository();
    cubit = DecisionGraphConfigCubit(repository);
    when(() => repository.getGraph(automationContext)).thenAnswer(
      (_) async =>
          const DecisionGraph(context: automationContext, rootNodeId: 'root'),
    );
    when(
      () => repository.getAllNodes(automationContext),
    ).thenAnswer((_) async => const [rootNode, childNode]);
    when(() => repository.upsertNode(any())).thenAnswer((_) async {});
    when(() => repository.deleteNode(any())).thenAnswer((_) async {});
    when(
      () => repository.setRoot(automationContext, any()),
    ).thenAnswer((_) async {});
  });

  testWidgets('expands the root row\'s inline form on tap', (tester) async {
    await cubit.load(automationContext);
    await tester.pumpWidget(
      _wrap(
        cubit,
        const DecisionOutlineList(automationContext: automationContext),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Attempt count exceeds').first);
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets(
    'renders a chained child as its own nested row with the MATCHED label',
    (tester) async {
      await cubit.load(automationContext);
      await tester.pumpWidget(
        _wrap(
          cubit,
          const DecisionOutlineList(automationContext: automationContext),
        ),
      );
      await tester.pumpAndSettle();

      // Both root and child share the same condition display name — one
      // row each.
      expect(find.text('Attempt count exceeds'), findsNWidgets(2));
      expect(find.text('MATCHED'), findsOneWidget);
    },
  );

  testWidgets(
    'renders "+ Add condition" under a terminal branch and expands the '
    'parent form pre-set to "Continue to condition" when tapped',
    (tester) async {
      await cubit.load(automationContext);
      await tester.pumpWidget(
        _wrap(
          cubit,
          const DecisionOutlineList(automationContext: automationContext),
        ),
      );
      await tester.pumpAndSettle();

      // root's unmatched branch terminates (gated), and so do both of
      // child's own branches (decline/proceed) — three affordances
      // total. root's own (for its unmatched branch) renders last, after
      // the entire matched-child subtree.
      expect(find.text('Add condition'), findsNWidgets(3));

      await tester.tap(find.text('Add condition').last);
      await tester.pumpAndSettle();

      // The root's form is now expanded with the unmatched branch's mode
      // forced to "Continue to condition" — its nested picker's eyebrow
      // is only shown in that mode.
      expect(find.text('OTHERWISE CHECK'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    },
  );
}
