// test/features/tickets/presentation/screens/tickets_board_view_test.dart — TicketBoardCard status-badge widget tests.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';
import 'package:aion/features/providers/domain/repositories/execution_scheduling_repository.dart';
import 'package:aion/features/providers/presentation/cubit/execution_scheduling_cubit.dart';
import 'package:aion/features/tickets/presentation/widgets/token_count_label.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketsCubit extends MockCubit<TicketsState>
    implements TicketsCubit {}

class MockExecutionSchedulingRepository extends Mock
    implements ExecutionSchedulingRepository {}

/// Wraps [card] with the providers/localization/theme scaffolding
/// `TicketBoardCard` needs to build: a [MockTicketsCubit] fixed to
/// [ticketsState], a real (inactive) [TicketSelectionCubit], and
/// [ThemeScope]/[AppLocalizations] for [ticketStatusLabel]'s `l10n`
/// lookups. No `GoRouter` — none of these cases tap the card, so
/// `context.go` is never reached.
Widget _wrap({required TicketsState ticketsState, required Widget card}) {
  final ticketsCubit = MockTicketsCubit();
  whenListen(
    ticketsCubit,
    Stream.value(ticketsState),
    initialState: ticketsState,
  );

  return MediaQuery(
    data: const MediaQueryData(),
    child: ThemeScope(
      theme: aionThemeArctic,
      child: WidgetsApp(
        color: aionThemeArctic.colors.primary,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
            PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (context, _, _) => builder(context),
            ),
        // `home` (not `builder`) so WidgetsApp mounts a Navigator, whose
        // Overlay ancestor `TicketBoardCard`'s Draggable requires.
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TicketsCubit>.value(value: ticketsCubit),
            BlocProvider<TicketSelectionCubit>(
              create: (_) => TicketSelectionCubit(),
            ),
          ],
          child: card,
        ),
      ),
    ),
  );
}

void main() {
  final task = Ticket(
    id: 'task-1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'A Task',
    status: TicketStatus.inProgress,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final epic = Ticket(
    id: 'epic-1',
    ticketId: 'AIO-2',
    type: TicketType.epic,
    title: 'An Epic',
    status: TicketStatus.backlog,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  testWidgets('a Task whose id is in inFlightExecutionIds renders the '
      'running badge', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ticketsState: TicketsLoaded(
          [task],
          hasMore: false,
          inFlightExecutionIds: {task.id},
        ),
        card: TicketBoardCard(ticket: task),
      ),
    );
    await tester.pump();

    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('Queued'), findsNothing);
    expect(find.text('Advancing'), findsNothing);
  });

  testWidgets('a queued Task renders its 1-based queue position', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ticketsState: TicketsLoaded(
          [task],
          hasMore: false,
          executionQueuePositions: {task.id: 2},
        ),
        card: TicketBoardCard(ticket: task),
      ),
    );
    await tester.pump();

    expect(find.text('Queued #2'), findsOneWidget);
    expect(find.text('Running'), findsNothing);
    expect(find.text('Advancing'), findsNothing);
  });

  testWidgets('an Epic/Story in inFlightAdvanceIds renders the advancing '
      'badge', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ticketsState: TicketsLoaded(
          [epic],
          hasMore: false,
          inFlightAdvanceIds: {epic.id},
        ),
        card: TicketBoardCard(ticket: epic),
      ),
    );
    await tester.pump();

    expect(find.text('Advancing'), findsOneWidget);
    expect(find.text('Running'), findsNothing);
    expect(find.textContaining('Queued'), findsNothing);
  });

  testWidgets('a ticket in none of the three in-flight fields renders no '
      "badge — today's exact output", (tester) async {
    await tester.pumpWidget(
      _wrap(
        ticketsState: TicketsLoaded([task], hasMore: false),
        card: TicketBoardCard(ticket: task),
      ),
    );
    await tester.pump();

    expect(find.text('Running'), findsNothing);
    expect(find.textContaining('Queued'), findsNothing);
    expect(find.text('Advancing'), findsNothing);
  });

  group('_cardTokenLabel precedence (token-cost-prediction)', () {
    final taskWithPrediction = Ticket(
      id: 'task-2',
      ticketId: 'AIO-3',
      type: TicketType.task,
      title: 'A predicted Task',
      status: TicketStatus.backlog,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      predictedExecutionTokensLow: 28000,
      predictedExecutionTokensHigh: 61000,
    );

    testWidgets(
      'a running total present takes precedence over a predicted range',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ticketsState: TicketsLoaded(
              [taskWithPrediction],
              hasMore: false,
              executionTokenTotals: const {'task-2': 18400},
            ),
            card: TicketBoardCard(ticket: taskWithPrediction),
          ),
        );
        await tester.pump();

        expect(find.text('~18.4K'), findsOneWidget);
        expect(find.text('~28K–61K'), findsNothing);
      },
    );

    testWidgets(
      'a predicted range shows when no running total is present',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ticketsState: TicketsLoaded([taskWithPrediction], hasMore: false),
            card: TicketBoardCard(ticket: taskWithPrediction),
          ),
        );
        await tester.pump();

        expect(find.text('~28K–61K'), findsOneWidget);
      },
    );

    testWidgets(
      'neither a running total nor a predicted range renders nothing',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ticketsState: TicketsLoaded([task], hasMore: false),
            card: TicketBoardCard(ticket: task),
          ),
        );
        await tester.pump();

        expect(find.byType(TokenCountLabel), findsNothing);
      },
    );

    testWidgets(
      'a non-task/bug ticket never renders a token label, even with a '
      'running total keyed to its id',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ticketsState: TicketsLoaded(
              [epic],
              hasMore: false,
              executionTokenTotals: {epic.id: 18400},
            ),
            card: TicketBoardCard(ticket: epic),
          ),
        );
        await tester.pump();

        expect(find.byType(TokenCountLabel), findsNothing);
      },
    );

    testWidgets(
      'a queued run suppresses a stale predicted range — the queued-state '
      'carve-out',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ticketsState: TicketsLoaded(
              [taskWithPrediction],
              hasMore: false,
              executionQueuePositions: const {'task-2': 1},
            ),
            card: TicketBoardCard(ticket: taskWithPrediction),
          ),
        );
        await tester.pump();

        expect(find.byType(TokenCountLabel), findsNothing);
      },
    );
  });

  testWidgets(
    'a card whose ticket id is in blockedTicketIds renders the Blocked '
    'badge (board-task-ordering-indication)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ticketsState: TicketsLoaded(
            [task],
            hasMore: false,
            blockedTicketIds: {task.id},
          ),
          card: TicketBoardCard(ticket: task),
        ),
      );
      await tester.pump();

      expect(find.text('Blocked'), findsOneWidget);
    },
  );

  testWidgets(
    'a card whose id is absent from blockedTicketIds renders no Blocked '
    "badge, no change to today's existing badge layout "
    '(board-task-ordering-indication)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ticketsState: TicketsLoaded(
            [task],
            hasMore: false,
            blockedTicketIds: const {'some-other-ticket'},
          ),
          card: TicketBoardCard(ticket: task),
        ),
      );
      await tester.pump();

      expect(find.text('Blocked'), findsNothing);
      expect(find.text('Running'), findsNothing);
      expect(find.textContaining('Queued'), findsNothing);
      expect(find.text('Advancing'), findsNothing);
    },
  );

  testWidgets(
    'a card that is both blocked and has an execution-state badge renders '
    'both, Blocked before the execution badge '
    '(board-task-ordering-indication)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ticketsState: TicketsLoaded(
            [task],
            hasMore: false,
            inFlightExecutionIds: {task.id},
            blockedTicketIds: {task.id},
          ),
          card: TicketBoardCard(ticket: task),
        ),
      );
      await tester.pump();

      expect(find.text('Blocked'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);

      final blockedCenter = tester.getCenter(find.text('Blocked'));
      final runningCenter = tester.getCenter(find.text('Running'));
      expect(
        blockedCenter.dx,
        lessThan(runningCenter.dx),
        reason:
            'Blocked badge should render before (left of) the '
            'execution-state badge, per the meta-row insertion order',
      );
    },
  );

  group(
    'rapid board reordering (parallel-work tasks.md T50 regression)',
    () {
      // Regression coverage for the crash flagged, not fixed, at the end
      // of T50: intermittent `RenderFlex overflowed`/`Duplicate GlobalKey`/
      // `'_dependents.isEmpty': is not true` framework errors that
      // blanked/duplicated the Board's chrome during rapid
      // ticket-status-changing interaction. Root cause: `BoardColumn`'s
      // per-column `ListView.separated` built `TicketBoardCard`s with no
      // `key:`, so Flutter's default positional element reconciliation
      // could reuse one ticket's stateful subtree (its `context.select`
      // subscriptions, its `MoveToStatusMenu` Overlay/LayerLink state, its
      // `_BoardCardStatusBadge` AnimationController) for an entirely
      // different ticket whenever the Board's ticket lists reordered or
      // moved tickets between columns across successive `TicketsLoaded`
      // emissions — exactly what concurrent scheduling's more frequent
      // re-emissions, plus Hybrid's `clusterSiblingsAdjacently`
      // reordering, make far more likely to hit. Fixed by keying each
      // `TicketBoardCard` on its ticket id (`tickets_board_view.dart`).
      Widget wrapBoard(TicketsCubit ticketsCubit) {
        return MediaQuery(
          data: const MediaQueryData(),
          child: ThemeScope(
            theme: aionThemeArctic,
            child: WidgetsApp(
              color: aionThemeArctic.colors.primary,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              pageRouteBuilder:
                  <T>(RouteSettings settings, WidgetBuilder builder) =>
                      PageRouteBuilder<T>(
                        settings: settings,
                        pageBuilder: (context, _, _) => builder(context),
                      ),
              // `home` (not `builder`) so `TicketBoardCard`'s Draggable
              // has the Overlay ancestor it needs, same as `_wrap` above.
              home: MultiBlocProvider(
                providers: [
                  BlocProvider<TicketsCubit>.value(value: ticketsCubit),
                  BlocProvider<TicketSelectionCubit>(
                    create: (_) => TicketSelectionCubit(),
                  ),
                  // Hybrid — the mode whose `clusterSiblingsAdjacently`
                  // reordering compounds the reorder churn this test
                  // drives.
                  BlocProvider<ExecutionSchedulingCubit>(
                    create: (_) {
                      final repo = MockExecutionSchedulingRepository();
                      when(() => repo.getMode()).thenAnswer(
                        (_) async => ExecutionSchedulingMode.hybrid,
                      );
                      when(
                        () => repo.getConcurrencyCeiling(),
                      ).thenAnswer((_) async => 3);
                      return ExecutionSchedulingCubit(repo)..load();
                    },
                  ),
                ],
                child: BlocBuilder<TicketsCubit, TicketsState>(
                  builder: (context, state) => TicketBoardView(
                    tickets: state is TicketsLoaded
                        ? state.tickets
                        : const <Ticket>[],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      Ticket ticket({
        required String id,
        required String title,
        required TicketStatus status,
        String? parentId,
      }) => Ticket(
        id: id,
        ticketId: 'AIO-$id',
        type: TicketType.task,
        title: title,
        status: status,
        parentId: parentId,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      testWidgets(
        'no framework exception across successive TicketsLoaded '
        'emissions that reorder tickets within and across columns under '
        'Hybrid clustering',
        (tester) async {
          final t1 = ticket(
            id: 't1',
            title: 'T1',
            status: TicketStatus.todo,
            parentId: 'story-1',
          );
          final t2 = ticket(
            id: 't2',
            title: 'T2',
            status: TicketStatus.todo,
            parentId: 'story-1',
          );
          final t3 = ticket(id: 't3', title: 'T3', status: TicketStatus.todo);
          final t4 = ticket(
            id: 't4',
            title: 'T4',
            status: TicketStatus.inProgress,
          );

          final states = [
            // s0: [t1, t3, t2] todo, [t4] inProgress — Hybrid clusters
            // t1/t2 adjacent in the rendered todo column.
            TicketsLoaded([t1, t3, t2, t4], hasMore: false),
            // s1: t1 moves to inProgress — removed from the front of
            // todo, appended to inProgress.
            TicketsLoaded(
              [t1.copyWith(status: TicketStatus.inProgress), t3, t2, t4],
              hasMore: false,
            ),
            // s2: t2 joins t1 in inProgress too.
            TicketsLoaded(
              [
                t1.copyWith(status: TicketStatus.inProgress),
                t3,
                t2.copyWith(status: TicketStatus.inProgress),
                t4,
              ],
              hasMore: false,
            ),
            // s3: t1 reverts to todo — rapid back-and-forth.
            TicketsLoaded(
              [t1, t3, t2.copyWith(status: TicketStatus.inProgress), t4],
              hasMore: false,
            ),
            // s4: t4 moves to todo too — a second column's churn on top
            // of the first.
            TicketsLoaded(
              [
                t1,
                t3,
                t2.copyWith(status: TicketStatus.inProgress),
                t4.copyWith(status: TicketStatus.todo),
              ],
              hasMore: false,
            ),
          ];

          final cubit = MockTicketsCubit();
          final controller = StreamController<TicketsState>();
          whenListen(cubit, controller.stream, initialState: states.first);

          await tester.pumpWidget(wrapBoard(cubit));
          // Let `ExecutionSchedulingCubit.load()`'s repo Futures resolve
          // before driving state changes.
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);

          for (final state in states.skip(1)) {
            controller.add(state);
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'no Flutter framework exception should surface while '
                  'the Board reorders tickets across a TicketsLoaded '
                  'emission (state: ${state.tickets.map((t) => '${t.id}:${t.status}')})',
            );
          }

          await controller.close();

          // Final layout: T4 (now `todo`) renders exactly once, not
          // duplicated or dropped, confirming the Board settled onto a
          // correct — not just exception-free — tree.
          expect(find.text('T4'), findsOneWidget);
          expect(find.text('T1'), findsOneWidget);
          expect(find.text('T2'), findsOneWidget);
          expect(find.text('T3'), findsOneWidget);
        },
      );

      testWidgets(
        'no framework exception when several TicketsLoaded emissions '
        'collapse into a single frame (TicketsCubit fires '
        '_refreshInFlightBoardState/_refreshTaskDetailIfShowing '
        'back-to-back synchronously, so Flutter often only paints the '
        'last of several emitted states) and the collapsed jump scrambles '
        'many cards, including one mid-spin `running` badge, at once',
        (tester) async {
          // All 6 status columns (280px each, plus padding/separators)
          // don't fit the default 800px test surface — widen it so every
          // column is actually laid out and visible to `find.text`,
          // rather than lazily un-built by the horizontal `ListView` and
          // producing false "0 widgets found" failures unrelated to the
          // bug under test.
          final originalSize = tester.view.physicalSize;
          final originalRatio = tester.view.devicePixelRatio;
          tester.view.physicalSize = const Size(2400, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.physicalSize = originalSize;
            tester.view.devicePixelRatio = originalRatio;
          });

          final siblingA = ticket(
            id: 'sib-a',
            title: 'Sib A',
            status: TicketStatus.todo,
            parentId: 'story-1',
          );
          final siblingB = ticket(
            id: 'sib-b',
            title: 'Sib B',
            status: TicketStatus.backlog,
            parentId: 'story-1',
          );
          final loose = List.generate(
            5,
            (i) => ticket(
              id: 'loose-$i',
              title: 'Loose $i',
              status: TicketStatus.values[i % TicketStatus.values.length],
            ),
          );

          final initial = TicketsLoaded([
            siblingA,
            ...loose,
            siblingB,
          ], hasMore: false, inFlightExecutionIds: {loose[0].id});

          // Every ticket's status shuffled at once (not a gradual
          // one-at-a-time drift), plus the in-flight/running badge moves
          // off `loose[0]` (still mid-spin — `AnimationController.repeat()`
          // never got a chance to stop cleanly) onto `siblingA`, and the
          // two siblings move out of adjacency, forcing Hybrid's
          // `clusterSiblingsAdjacently` to re-pull them together from
          // opposite ends of a differently-ordered list.
          final scrambled = TicketsLoaded(
            [
              loose[3].copyWith(status: TicketStatus.todo),
              siblingB.copyWith(status: TicketStatus.todo),
              loose[1].copyWith(status: TicketStatus.inProgress),
              loose[4].copyWith(status: TicketStatus.todo),
              siblingA.copyWith(status: TicketStatus.todo),
              loose[0].copyWith(status: TicketStatus.backlog),
              loose[2].copyWith(status: TicketStatus.done),
            ],
            hasMore: false,
            inFlightExecutionIds: {siblingA.id},
          );

          final cubit = MockTicketsCubit();
          final controller = StreamController<TicketsState>();
          whenListen(cubit, controller.stream, initialState: initial);

          await tester.pumpWidget(wrapBoard(cubit));
          await tester.pump();
          await tester.pump();
          // Let `loose[0]`'s running badge actually start spinning
          // (`didChangeDependencies` -> `AnimationController.repeat()`)
          // before the jump, so its ticker is genuinely live mid-reorder,
          // not just freshly constructed.
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);

          // Both emissions land before any pump processes either — the
          // same shape as `TicketsCubit`'s synchronous
          // `_refreshInFlightBoardState(); _refreshTaskDetailIfShowing();`
          // pairing, where Flutter's widget-binding schedules one frame
          // no matter how many times `emit` fired first.
          controller
            ..add(scrambled)
            ..add(scrambled);
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);

          await controller.close();

          // Every ticket still renders exactly once post-jump — not
          // duplicated (stale Element wrongly kept alongside its
          // replacement) and not blanked (an exception mid-layout that
          // aborted the column's subtree).
          for (final t in [siblingA, siblingB, ...loose]) {
            expect(
              find.text(t.title),
              findsOneWidget,
              reason: '${t.title} should render exactly once after the '
                  'collapsed jump',
            );
          }
        },
      );
    },
  );
}
