// test/features/providers/presentation/screens/decision_graph_editor_screen_test.dart — DecisionGraphEditorScreen widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_cubit.dart';
import 'package:aion/features/providers/presentation/screens/decision_graph_editor_screen.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockDecisionGraphRepository extends Mock
    implements DecisionGraphRepository {}

Widget _wrap(DecisionGraphConfigCubit cubit) {
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
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => const DecisionGraphEditorScreen(
                automationContext: AutomationContext.codingExecutionRetry,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(AutomationContext.codingExecutionRetry);
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

  late MockDecisionGraphRepository repository;
  late DecisionGraphConfigCubit cubit;

  setUp(() {
    repository = MockDecisionGraphRepository();
    cubit = DecisionGraphConfigCubit(repository);
    when(() => repository.upsertNode(any())).thenAnswer((_) async {});
    when(() => repository.deleteNode(any())).thenAnswer((_) async {});
    when(
      () => repository.setRoot(automationContext, any()),
    ).thenAnswer((_) async {});
  });

  testWidgets(
    'renders both panes bound to the same DecisionGraphConfigCubit state',
    (tester) async {
      const rootNode = DecisionNode(
        id: 'root',
        conditionId: 'attemptExceedsMax',
        conditionParams: {'maxAttempts': 2},
        matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
        unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
      );
      when(() => repository.getGraph(automationContext)).thenAnswer(
        (_) async =>
            const DecisionGraph(context: automationContext, rootNodeId: 'root'),
      );
      when(
        () => repository.getAllNodes(automationContext),
      ).thenAnswer((_) async => const [rootNode]);

      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      // The canvas pane's condition-box eyebrow and the outline pane's
      // row both render the same node's condition name — one per pane.
      expect(find.text('Attempt count exceeds'), findsNWidgets(2));
    },
  );

  testWidgets('renders the empty-graph state when the context has no root', (
    tester,
  ) async {
    when(() => repository.getGraph(automationContext)).thenAnswer(
      (_) async =>
          const DecisionGraph(context: automationContext, rootNodeId: null),
    );
    when(
      () => repository.getAllNodes(automationContext),
    ).thenAnswer((_) async => const []);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Every run proceeds'), findsOneWidget);
    expect(find.text('Attempt count exceeds'), findsNothing);
  });

  group('rule builder', () {
    testWidgets(
      '"Custom rule…" appears in the condition picker for a context with '
      'rule-builder fields (codingExecutionRetry)',
      (tester) async {
        when(() => repository.getGraph(automationContext)).thenAnswer(
          (_) async => const DecisionGraph(
            context: automationContext,
            rootNodeId: null,
          ),
        );
        when(
          () => repository.getAllNodes(automationContext),
        ).thenAnswer((_) async => const []);

        await tester.pumpWidget(_wrap(cubit));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add condition'), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose a condition'));
        await tester.pumpAndSettle();

        expect(find.text('Custom rule…'), findsOneWidget);
      },
    );

    testWidgets(
      '"Custom rule…" is absent from the condition picker for a context '
      'with no rule-builder fields (sddStage)',
      (tester) async {
        const sddContext = AutomationContext.sddStage;
        when(() => repository.getGraph(sddContext)).thenAnswer(
          (_) async =>
              const DecisionGraph(context: sddContext, rootNodeId: null),
        );
        when(
          () => repository.getAllNodes(sddContext),
        ).thenAnswer((_) async => const []);

        await tester.pumpWidget(
          ThemeScope(
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
                  BlocProvider<DecisionGraphConfigCubit>.value(
                    value: cubit,
                    child: Overlay(
                      initialEntries: [
                        OverlayEntry(
                          builder: (_) => const DecisionGraphEditorScreen(
                            automationContext: sddContext,
                          ),
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add condition'), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose a condition'));
        await tester.pumpAndSettle();

        expect(find.text('Custom rule…'), findsNothing);
      },
    );

    testWidgets(
      'a rule-builder node renders its field-derived title/summary and no '
      'INCOMPLETE error chrome',
      (tester) async {
        const rootNode = DecisionNode(
          id: 'root',
          conditionId: 'ruleBuilder',
          conditionParams: {
            'field': 'attempt',
            'operator': 'greaterThan',
            'value': 3,
          },
          matchedBranch: DecisionBranch.terminal(DecisionOutcome.gated),
          unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
        );
        when(() => repository.getGraph(automationContext)).thenAnswer(
          (_) async => const DecisionGraph(
            context: automationContext,
            rootNodeId: 'root',
          ),
        );
        when(
          () => repository.getAllNodes(automationContext),
        ).thenAnswer((_) async => const [rootNode]);

        await tester.pumpWidget(_wrap(cubit));
        await tester.pumpAndSettle();

        // The canvas node's title and the outline row's title both read
        // the chosen field's display name, not the raw conditionId.
        expect(find.text('Attempt count'), findsNWidgets(2));
        // The canvas card's eyebrow reads "RULE ·", not "IF ·" — the
        // rule-vs-preset marker design.md (Component Spec) §4.1 requires
        // alongside the parameter chip's border.
        expect(find.text('RULE · ATTEMPT COUNT'), findsOneWidget);
        expect(find.text('IF · ATTEMPT COUNT'), findsNothing);
        expect(find.text('IF · INCOMPLETE'), findsNothing);
        expect(find.text('RULE · INCOMPLETE'), findsNothing);
      },
    );
  });
}
