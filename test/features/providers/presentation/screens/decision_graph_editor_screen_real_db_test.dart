// test/features/providers/presentation/screens/decision_graph_editor_screen_real_db_test.dart —
// DecisionGraphEditorScreen widget tests against a REAL in-memory drift
// database (no mocked repository) — catches persistence bugs a
// synchronous mock can hide, per `automation_decision_dao_test.dart`'s own
// real-database precedent. Added for manual QA of
// `aion-arch/changes/automation-decision-graphs`: the mocked-repository
// tests in `decision_graph_editor_screen_test.dart` never actually drove
// the canvas-popover tap-to-edit-and-save flow end to end, so a real
// cascading-delete regression (see `decision_graph_config_cubit_test.dart`)
// went unnoticed until manual GUI QA.
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/automation/data/drift_decision_graph_repository.dart';
import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/projects.dart';
import 'package:aion/features/providers/presentation/cubit/decision_graph_config_cubit.dart';
import 'package:aion/features/providers/presentation/screens/decision_graph_editor_screen.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

final _testProject = Project(
  id: 'test-project',
  name: 'Test Project',
  storageKey: 'test-project',
  baselineVersion: '0.1.0',
  createdAt: DateTime(2024, 1, 1),
  lastOpenedAt: DateTime(2024, 1, 1),
);

Widget _wrap(DecisionGraphConfigCubit cubit, AutomationContext ctx) {
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
              builder: (_) =>
                  DecisionGraphEditorScreen(automationContext: ctx),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DriftDecisionGraphRepository repository;
  late DecisionGraphConfigCubit cubit;

  setUp(() {
    database = AppDatabase(_testProject, NativeDatabase.memory());
    repository = DriftDecisionGraphRepository(database);
    cubit = DecisionGraphConfigCubit(repository);
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets(
    'deleting a node with a chained child cascades in the real database — '
    'the descendant is not left as an orphaned row',
    (tester) async {
      const ctx = AutomationContext.codingExecutionRetry;
      await tester.pumpWidget(_wrap(cubit, ctx));
      await tester.pumpAndSettle();

      // Chain the seeded default root's matched branch to a new condition
      // via the canvas popover, so the graph has root + one descendant.
      await tester.tap(
        find.text('Attempt count exceeds').first,
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Continue to condition').first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a condition'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Attempt count exceeds').last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last, warnIfMissed: false);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(await repository.getAllNodes(ctx), hasLength(2));

      // Re-open the root and delete it — the confirm dialog should warn
      // about the descendant, and confirming should remove both rows.
      // Locate the root node's own canvas gesture area via its unique
      // "ROOT" marker chip rather than by text-match index, since
      // `_TreeLayout.layout` positions a child's `GraphCanvasNode` before
      // its own parent's (it recurses into the matched child before
      // adding itself — see that method's own body).
      await tester.tap(
        find
            .ancestor(
              of: find.text('ROOT'),
              matching: find.byType(GestureDetector),
            )
            .first,
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.textContaining('1 descendant'), findsOneWidget);

      await tester.tap(find.text('Delete').last, warnIfMissed: false);
      await tester.pump();
      await tester.pumpAndSettle();

      // Root-reachable nodes are gone from the UI...
      expect(await repository.getAllNodes(ctx), isEmpty);
      // ...and the descendant's row was actually deleted, not merely
      // orphaned (getAllNodes only walks from the root, so this checks
      // the DAO directly — filtered to this test's own condition, since
      // the DAO's `getAllNodes` returns every context's rows and the
      // database seeds a baseline `codingExecution` node too).
      final remaining = await database.automationDecisionDao.getAllNodes();
      expect(
        remaining.where((row) => row.conditionId == 'attemptExceedsMax'),
        isEmpty,
      );
    },
  );

  testWidgets('sddStage empty graph: "Add condition" persists to a real DB', (
    tester,
  ) async {
    const ctx = AutomationContext.sddStage;
    await tester.pumpWidget(_wrap(cubit, ctx));
    await tester.pumpAndSettle();

    expect(await repository.getGraph(ctx), isA<DecisionGraph>());
    expect((await repository.getGraph(ctx)).rootNodeId, isNull);
    expect(find.text('Add condition'), findsOneWidget);
  });
}
