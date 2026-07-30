// test/core/routing/workspace_nav_shell_test.dart — WorkspaceNavShell app-wide toast listener widget tests.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
