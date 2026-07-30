// test/core/routing/workspace_nav_shell_test.dart — WorkspaceNavShell app-wide toast listener widget tests.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/routing/workspace_nav_shell.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketsCubit extends MockCubit<TicketsState> implements TicketsCubit {}

/// Wraps [WorkspaceNavShell] with the providers/localization/theme
/// scaffolding it needs to build, and a [MockTicketsCubit] whose state
/// stream is driven by [controller] so a test can push new
/// [TicketsState]s after the initial pump — the shape a real
/// `TicketsCubit.emit` call from deep in the widget tree would produce.
Widget _wrap({
  required StreamController<TicketsState> controller,
  required TicketsState initialState,
}) {
  final ticketsCubit = MockTicketsCubit();
  when(() => ticketsCubit.state).thenReturn(initialState);
  when(() => ticketsCubit.stream).thenAnswer((_) => controller.stream);

  return MediaQuery(
    data: const MediaQueryData(size: Size(1200, 800)),
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
        home: BlocProvider<TicketsCubit>.value(
          value: ticketsCubit,
          child: WorkspaceNavShell(
            currentLocation: '/workspace/tickets',
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}

/// Wraps a real [GoRouter] with three routes standing in for
/// `/workspace/tickets`/`/workspace/documentation`/`/workspace/inbox`,
/// each rendering [WorkspaceNavShell] around a distinctive [Text] so a
/// test can assert both which nav item is active and that tapping each
/// one actually navigates. [width] drives whether [WorkspaceNavShell]
/// renders `_WideShell`/`_Sidebar` or `_CompactShell`/`_BottomTabBar`.
Widget _wrapRouted({required double width}) {
  final ticketsCubit = MockTicketsCubit();
  when(() => ticketsCubit.state).thenReturn(const TicketsInitial());
  when(
    () => ticketsCubit.stream,
  ).thenAnswer((_) => const Stream<TicketsState>.empty());

  Widget shellFor(GoRouterState state, String label) => BlocProvider<TicketsCubit>.value(
    value: ticketsCubit,
    child: WorkspaceNavShell(
      currentLocation: state.uri.path,
      child: Text(label),
    ),
  );

  final router = GoRouter(
    initialLocation: '/workspace/tickets',
    routes: [
      GoRoute(
        path: '/workspace/tickets',
        builder: (context, state) => shellFor(state, 'Tickets screen'),
      ),
      GoRoute(
        path: '/workspace/documentation',
        builder: (context, state) => shellFor(state, 'Documentation screen'),
      ),
      GoRoute(
        path: '/workspace/inbox',
        builder: (context, state) => shellFor(state, 'Inbox screen'),
      ),
    ],
  );

  return MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: ThemeScope(
      theme: aionThemeArctic,
      child: WidgetsApp.router(
        routerConfig: router,
        color: aionThemeArctic.colors.primary,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'emitting a TicketsError with a classified reason shows an AppToast '
    'with the matching ticketsErrorMessage text',
    (tester) async {
      final controller = StreamController<TicketsState>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(
        _wrap(controller: controller, initialState: const TicketsInitial()),
      );
      await tester.pump();

      controller.add(
        const TicketsError(
          '',
          reason: TicketsErrorReason.codingExecutionBlocked,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final expectedMessage = ticketsErrorMessage(
        tester.element(find.byType(WorkspaceNavShell)),
        TicketsErrorReason.codingExecutionBlocked,
      );
      expect(find.text(expectedMessage), findsOneWidget);

      // Lets AppToast's own 3-second auto-dismiss Future.delayed fire and
      // remove its OverlayEntry — otherwise the pending Timer trips
      // flutter_test's post-test "no leftover timers" invariant check.
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'emitting a TicketsError with reason: null shows no toast from this '
    'listener',
    (tester) async {
      final controller = StreamController<TicketsState>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(
        _wrap(controller: controller, initialState: const TicketsInitial()),
      );
      await tester.pump();

      controller.add(const TicketsError('a raw, unclassified error'));
      await tester.pump();

      expect(find.text('a raw, unclassified error'), findsNothing);
    },
  );

  /// Finds the single [Semantics] widget labeling the nav item [label] —
  /// reads its `properties.selected` directly off the widget (no
  /// semantics-tree binding needed) to check which destination
  /// `_destinationFor` resolved as active.
  Semantics navItemSemantics(WidgetTester tester, String label) {
    return tester
        .widgetList<Semantics>(find.byType(Semantics))
        .firstWhere((s) => s.properties.label == label);
  }

  group('destination navigation (new-project-onboarding-inbox)', () {
    for (final width in [1200.0, 500.0]) {
      final layoutName = width > 900 ? 'wide sidebar' : 'compact bottom bar';

      testWidgets(
        '$layoutName: tapping each of the three destinations navigates '
        'correctly, and /workspace/inbox resolves Inbox as active',
        (tester) async {
          await tester.pumpWidget(_wrapRouted(width: width));
          await tester.pumpAndSettle();

          expect(find.text('Tickets screen'), findsOneWidget);
          expect(navItemSemantics(tester, 'Tickets').properties.selected, isTrue);
          expect(
            navItemSemantics(tester, 'Documentation').properties.selected,
            isFalse,
          );
          expect(
            navItemSemantics(tester, 'Inbox').properties.selected,
            isFalse,
          );

          await tester.tap(find.text('Documentation'));
          await tester.pumpAndSettle();
          expect(find.text('Documentation screen'), findsOneWidget);
          expect(
            navItemSemantics(tester, 'Documentation').properties.selected,
            isTrue,
          );

          await tester.tap(find.text('Inbox'));
          await tester.pumpAndSettle();
          expect(find.text('Inbox screen'), findsOneWidget);
          expect(
            navItemSemantics(tester, 'Inbox').properties.selected,
            isTrue,
          );
          expect(
            navItemSemantics(tester, 'Tickets').properties.selected,
            isFalse,
          );
          expect(
            navItemSemantics(tester, 'Documentation').properties.selected,
            isFalse,
          );

          await tester.tap(find.text('Tickets'));
          await tester.pumpAndSettle();
          expect(find.text('Tickets screen'), findsOneWidget);
          expect(
            navItemSemantics(tester, 'Tickets').properties.selected,
            isTrue,
          );
        },
      );
    }
  });
}
