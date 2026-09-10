// test/features/providers/presentation/widgets/transition_outline_list_test.dart — TransitionOutlineList widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/presentation/cubit/transition_precondition_config_cubit.dart';
import 'package:aion/features/providers/presentation/widgets/transition_outline_list.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTransitionPreconditionRepository extends Mock
    implements TransitionPreconditionRepository {}

/// Wraps [child] in the `ThemeScope`/`WidgetsApp`/`Overlay` harness every
/// widget test in this repo uses for a `SelectionMenu`/`TransitionNodeForm`
/// host — mirrors `decision_outline_list_test.dart`'s own `_wrap`.
Widget _wrap(TransitionPreconditionConfigCubit cubit, Widget child) {
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
          BlocProvider<TransitionPreconditionConfigCubit>.value(
            value: cubit,
            child: Overlay(
              initialEntries: [OverlayEntry(builder: (_) => child)],
            ),
          ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(SddStage.proposed);
    registerFallbackValue(
      const TransitionNode(
        id: 'fallback',
        fieldId: 'hasChildren',
        matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
        unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
      ),
    );
  });

  const stage = SddStage.proposed;

  // Mirrors `seedDefaultsIfEmpty`'s real `proposed` shape (minus its third
  // node) — a root with a chained matched-branch child, i.e. depth 0 and
  // depth 1 rows. This is the exact shape `AIO-2831` reproduced on: any
  // stage with a chained (non-root) field check rendered a completely
  // blank pane, because `_GuideRailIndent`'s then-`IntrinsicHeight`-based
  // implementation couldn't lay out through `_NodeRow`'s `LayoutBuilder`.
  const rootNode = TransitionNode(
    id: 'root',
    fieldId: 'hasChildren',
    matchedBranch: TransitionBranch.toNode('child'),
    unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
  );
  const childNode = TransitionNode(
    id: 'child',
    fieldId: 'storyNeedsDesignReview',
    matchedBranch: TransitionBranch.terminal(TransitionOutcome.allowed),
    unmatchedBranch: TransitionBranch.terminal(TransitionOutcome.blocked),
  );

  late MockTransitionPreconditionRepository repository;
  late TransitionPreconditionConfigCubit cubit;

  setUp(() {
    repository = MockTransitionPreconditionRepository();
    cubit = TransitionPreconditionConfigCubit(repository);
    when(() => repository.getGraph(stage)).thenAnswer(
      (_) async => const TransitionGraph(stage: stage, rootNodeId: 'root'),
    );
    when(
      () => repository.getAllNodes(stage),
    ).thenAnswer((_) async => const [rootNode, childNode]);
    when(() => repository.upsertNode(any())).thenAnswer((_) async {});
    when(() => repository.deleteNode(any())).thenAnswer((_) async {});
    when(() => repository.setRoot(stage, any())).thenAnswer((_) async {});
  });

  testWidgets(
    'renders a chained child as its own nested (depth-1) row without '
    'throwing — regression test for AIO-2831',
    (tester) async {
      await cubit.load(stage);
      await tester.pumpWidget(
        _wrap(cubit, const TransitionOutlineList(stage: stage)),
      );
      await tester.pumpAndSettle();

      // The pre-fix `IntrinsicHeight`/`LayoutBuilder` conflict threw
      // during every layout pass for a depth-1 row, which
      // `tester.pumpAndSettle()` above would surface as a `FlutterError`
      // via `takeException()` — asserting `isNull` is the actual
      // regression check; the row-text expectations below confirm the
      // pane still renders its real content, not just "didn't crash".
      expect(tester.takeException(), isNull);

      expect(find.text('Ticket has children'), findsOneWidget);
      expect(find.text('Story needs design review'), findsOneWidget);
      // Once for the branch-word caption above the nested row, once for
      // the child row's own trailing "matched → allowed" outcome badge.
      expect(find.text('MATCHED'), findsNWidgets(2));
    },
  );

  testWidgets('expands the root row\'s inline form on tap', (tester) async {
    await cubit.load(stage);
    await tester.pumpWidget(
      _wrap(cubit, const TransitionOutlineList(stage: stage)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Ticket has children').first);
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
