// test/features/tickets/presentation/screens/tickets_list_screen_test.dart — TicketsListScreen widget tests.

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/active_project_provider.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockActiveProjectProvider extends Mock implements ActiveProjectProvider {}

Widget _wrap({
  required TicketsCubit ticketsCubit,
  required ActiveProjectProvider activeProjectProvider,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ActiveProjectProvider>.value(
              value: activeProjectProvider,
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<TicketsCubit>.value(value: ticketsCubit),
              BlocProvider<TicketSelectionCubit>(
                create: (_) => TicketSelectionCubit(),
              ),
            ],
            child: const TicketsListScreen(),
          ),
        ),
      ),
    ],
  );

  return MediaQuery(
    data: const MediaQueryData(),
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
  late MockTicketRepository repository;
  late MockTicketLinkRepository linkRepository;
  late MockAgentModelClient agentClient;
  late MockActiveProjectProvider activeProjectProvider;

  setUpAll(() {
    registerFallbackValue(const AgentRequest(prompt: '', model: ''));
    registerFallbackValue(
      Ticket(
        id: 'fallback',
        ticketId: '',
        type: TicketType.signal,
        title: '',
        status: TicketStatus.backlog,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    registerFallbackValue(TicketLinkType.relatesTo);
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(900, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    repository = MockTicketRepository();
    linkRepository = MockTicketLinkRepository();
    agentClient = MockAgentModelClient();
    activeProjectProvider = MockActiveProjectProvider();

    when(
      () => repository.searchTickets(
        query: any(named: 'query'),
        status: any(named: 'status'),
        type: any(named: 'type'),
        priority: any(named: 'priority'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => const TicketSearchPage(tickets: [], hasMore: false));
    final ticketStore = <String, Ticket>{};
    when(() => repository.createTicket(any())).thenAnswer((invocation) async {
      final ticket = invocation.positionalArguments[0] as Ticket;
      ticketStore[ticket.id] = ticket;
    });
    when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
      final id = invocation.positionalArguments[0] as String;
      return ticketStore[id];
    });
    when(
      () => linkRepository.createLink(
        sourceTicketId: any(named: 'sourceTicketId'),
        targetTicketId: any(named: 'targetTicketId'),
        linkType: any(named: 'linkType'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => activeProjectProvider.consumeCodebaseAnalysisOffer(),
    ).thenReturn(null);
  });

  TicketsCubit buildCubit() => TicketsCubit(
    repository,
    linkRepository: linkRepository,
    agentClient: agentClient,
    projectRootPath: '/fake/project/root',
    projectName: 'Fake Project',
  );

  testWidgets(
    'does not show the codebase-analysis banner when the active project '
    'has no pending offer',
    (tester) async {
      when(
        () => activeProjectProvider.offerCodebaseAnalysis,
      ).thenReturn(false);

      await tester.pumpWidget(
        _wrap(
          ticketsCubit: buildCubit(),
          activeProjectProvider: activeProjectProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Draft a starting backlog from this codebase'),
        findsNothing,
      );
      verifyNever(() => activeProjectProvider.consumeCodebaseAnalysisOffer());
    },
  );

  testWidgets(
    'shows the codebase-analysis offer banner and consumes the flag when '
    'the active project has a pending offer',
    (tester) async {
      when(
        () => activeProjectProvider.offerCodebaseAnalysis,
      ).thenReturn(true);

      await tester.pumpWidget(
        _wrap(
          ticketsCubit: buildCubit(),
          activeProjectProvider: activeProjectProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Draft a starting backlog from this codebase'),
        findsOneWidget,
      );
      verify(
        () => activeProjectProvider.consumeCodebaseAnalysisOffer(),
      ).called(1);
    },
  );

  testWidgets(
    'picking a depth calls TicketsCubit.runCodebaseSummarization, and the '
    'banner never reappears after being dismissed',
    (tester) async {
      when(
        () => activeProjectProvider.offerCodebaseAnalysis,
      ).thenReturn(true);
      when(() => agentClient.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [
          AgentTextEvent(
            'FINDING: A finding\nA description.\nSUMMARY: DONE',
          ),
          AgentDoneEvent(),
        ]),
      );

      await tester.pumpWidget(
        _wrap(
          ticketsCubit: buildCubit(),
          activeProjectProvider: activeProjectProvider,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Shallow scan'));
      await tester.pumpAndSettle();

      // Run-record + 1 finding ticket created — confirms
      // runCodebaseSummarization actually ran.
      verify(() => repository.createTicket(any())).called(2);

      // Dismiss the now-"done" banner.
      final dismissFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Dismiss',
      );
      expect(dismissFinder, findsOneWidget);
      await tester.tap(dismissFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('Draft a starting backlog from this codebase'),
        findsNothing,
      );
      expect(find.text('Drafted 1 signal ticket'), findsNothing);

      // Still only consumed once, at initState — never re-triggered by
      // the rebuild the dismiss/tap caused.
      verify(
        () => activeProjectProvider.consumeCodebaseAnalysisOffer(),
      ).called(1);
    },
  );
}
