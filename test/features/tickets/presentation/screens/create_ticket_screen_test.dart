// test/features/tickets/presentation/screens/create_ticket_screen_test.dart — CreateTicketScreen's narrowed TicketsError listener widget tests.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketsCubit extends MockCubit<TicketsState> implements TicketsCubit {}

/// Wraps [CreateTicketScreen] with the providers/localization/theme
/// scaffolding it needs to build, and a [MockTicketsCubit] whose state
/// stream is driven by [controller] — same harness shape as
/// `workspace_nav_shell_test.dart`'s, since both cover a
/// `TicketsErrorReason`-gated `BlocListener`/[AppToast] pairing added by
/// `aion-arch/changes/board-execution-indicators-and-notifications`.
Widget _wrap({required StreamController<TicketsState> controller}) {
  final ticketsCubit = MockTicketsCubit();
  when(() => ticketsCubit.state).thenReturn(const TicketsInitial());
  when(() => ticketsCubit.stream).thenAnswer((_) => controller.stream);
  // TicketParentPicker (rendered for the default TicketType.task) fetches
  // candidates in initState.
  when(
    () => ticketsCubit.getValidParentCandidatesForType(any()),
  ).thenAnswer((_) async => <Ticket>[]);

  return MediaQuery(
    data: const MediaQueryData(size: Size(900, 800)),
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
          child: const CreateTicketScreen(),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(TicketType.task);
  });

  testWidgets(
    'still toasts a raw/unclassified TicketsError (reason: null)',
    (tester) async {
      final controller = StreamController<TicketsState>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(_wrap(controller: controller));
      await tester.pump();

      controller.add(const TicketsError('could not save the ticket'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('could not save the ticket'), findsOneWidget);

      // Lets AppToast's own 3-second auto-dismiss Future.delayed fire and
      // remove its OverlayEntry — otherwise the pending Timer trips
      // flutter_test's post-test "no leftover timers" invariant check.
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'no longer double-toasts a classified TicketsError — that is '
    "WorkspaceNavShell's job now",
    (tester) async {
      final controller = StreamController<TicketsState>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(_wrap(controller: controller));
      await tester.pump();

      controller.add(
        const TicketsError(
          '',
          reason: TicketsErrorReason.codingExecutionBlocked,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // No screen-local toast for a classified reason — nothing to find,
      // and (unlike the raw-error case) no AppToast timer left pending.
      final message = ticketsErrorMessage(
        tester.element(find.byType(CreateTicketScreen)),
        TicketsErrorReason.codingExecutionBlocked,
      );
      expect(find.text(message), findsNothing);
    },
  );
}
