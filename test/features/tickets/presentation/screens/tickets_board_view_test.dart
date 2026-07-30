// test/features/tickets/presentation/screens/tickets_board_view_test.dart — TicketBoardCard status-badge widget tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketsCubit extends MockCubit<TicketsState> implements TicketsCubit {}

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
        pageRouteBuilder:
            <T>(RouteSettings settings, WidgetBuilder builder) =>
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
}
