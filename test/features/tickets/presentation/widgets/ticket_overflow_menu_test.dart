// test/features/tickets/presentation/widgets/ticket_overflow_menu_test.dart — TicketOverflowMenu widget tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketsCubit extends MockCubit<TicketsState>
    implements TicketsCubit {}

/// Wraps [child] in a real [GoRouter] (not a bare `WidgetsApp`/`Navigator`)
/// so `TicketOverflowMenu`'s own `context.go` call on "Discuss" has
/// somewhere to navigate to — the initial route renders [child], and
/// `/workspace/tickets/:id` renders a plain [Text] of the id so a
/// successful navigation is observable via `find.text`. [ticketsCubit] is
/// fixed to [state] via `whenListen`, mirroring
/// `ticket_metadata_section_test.dart`'s `_wrap` shape.
Widget _wrap(
  Widget child,
  MockTicketsCubit ticketsCubit, {
  TicketsState state = const TicketsInitial(),
}) {
  whenListen(ticketsCubit, Stream.value(state), initialState: state);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Align(
          child: BlocProvider<TicketsCubit>.value(
            value: ticketsCubit,
            child: child,
          ),
        ),
      ),
      GoRoute(
        path: '/workspace/tickets/:id',
        builder: (context, state) => Text('chat:${state.pathParameters['id']}'),
      ),
    ],
  );
  return MediaQuery(
    data: const MediaQueryData(),
    child: ThemeScope(
      theme: aionThemeArctic,
      child: MaterialApp.router(
        routerConfig: router,
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
  late MockTicketsCubit ticketsCubit;

  final epic = Ticket(
    id: 'epic-1',
    ticketId: 'AIO-2',
    type: TicketType.epic,
    title: 'Existing epic',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Ticket buildIdea() => Ticket(
    id: 'idea-1',
    ticketId: 'AIO-1',
    type: TicketType.idea,
    title: 'A raw idea',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(
      Ticket(
        id: 'fallback',
        ticketId: '',
        type: TicketType.epic,
        title: '',
        status: 'backlog',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    registerFallbackValue(TicketType.epic);
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(2000, 2000);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    ticketsCubit = MockTicketsCubit();
    when(() => ticketsCubit.getAllTickets()).thenAnswer((_) async => [epic]);
    when(
      () => ticketsCubit.reclassifyIdea(
        any(),
        targetType: any(named: 'targetType'),
        targetTicketId: any(named: 'targetTicketId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => ticketsCubit.startIdeaDiscussion(any()),
    ).thenAnswer((_) async => 'chat-1');
  });

  testWidgets(
    'tapping the trigger for an idea ticket shows Discuss, both reclassify '
    'rows, and the delete row',
    (tester) async {
      await tester.pumpWidget(
        _wrap(TicketOverflowMenu(ticket: buildIdea()), ticketsCubit),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();

      expect(find.text('Discuss'), findsOneWidget);
      expect(find.text('Change to Known Gap'), findsOneWidget);
      expect(find.text('Change to Open Question'), findsOneWidget);
      expect(find.text('Delete ticket'), findsOneWidget);
      // The old one-click promote actions are gone (AIO-2941).
      expect(find.text('Promote to Epic'), findsNothing);
      expect(find.text('Promote to Bug'), findsNothing);
    },
  );

  testWidgets('tapping "Discuss" for a non-idea ticket is not offered at all', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(TicketOverflowMenu(ticket: epic), ticketsCubit),
    );
    await tester.pump();

    await tester.tap(find.byType(TicketOverflowMenu));
    await tester.pumpAndSettle();

    expect(find.text('Discuss'), findsNothing);
    expect(find.text('Delete ticket'), findsOneWidget);
  });

  testWidgets('tapping "Change to Known Gap" opens a target picker; picking an '
      'existing ticket calls reclassifyIdea', (tester) async {
    final idea = buildIdea();
    await tester.pumpWidget(
      _wrap(TicketOverflowMenu(ticket: idea), ticketsCubit),
    );
    await tester.pump();

    await tester.tap(find.byType(TicketOverflowMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change to Known Gap'));
    await tester.pumpAndSettle();

    // No "create new" option in the reclassify target picker.
    expect(find.text('Create new epic'), findsNothing);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existing epic'));
    await tester.pumpAndSettle();

    verify(
      () => ticketsCubit.reclassifyIdea(
        idea,
        targetType: TicketType.knownGap,
        targetTicketId: epic.id,
      ),
    ).called(1);
  });

  testWidgets(
    'tapping "Discuss" starts the idea\'s discussion and navigates to the '
    'spawned chat (AIO-2940/AIO-2941)',
    (tester) async {
      final idea = buildIdea();
      await tester.pumpWidget(
        _wrap(TicketOverflowMenu(ticket: idea), ticketsCubit),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discuss'));
      await tester.pumpAndSettle();

      verify(() => ticketsCubit.startIdeaDiscussion(idea)).called(1);
      expect(find.text('chat:chat-1'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "Discuss" does not navigate when startIdeaDiscussion resolves '
    'null (guard rejection or no provider registry)',
    (tester) async {
      final idea = buildIdea();
      when(
        () => ticketsCubit.startIdeaDiscussion(any()),
      ).thenAnswer((_) async => null);
      await tester.pumpWidget(
        _wrap(TicketOverflowMenu(ticket: idea), ticketsCubit),
      );
      await tester.pump();

      await tester.tap(find.byType(TicketOverflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discuss'));
      await tester.pumpAndSettle();

      verify(() => ticketsCubit.startIdeaDiscussion(idea)).called(1);
      // Still on the idea's own route — no chat id to navigate to.
      expect(find.textContaining('chat:'), findsNothing);
    },
  );
}
