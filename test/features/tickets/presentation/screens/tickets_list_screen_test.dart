// test/features/tickets/presentation/screens/tickets_list_screen_test.dart — TicketsListScreen widget tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/active_project_provider.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/consumption_signal.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/projects/domain/entities/project.dart';
import 'package:aion/features/projects/domain/repositories/baseline_repository.dart';
import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';
import 'package:aion/features/providers/domain/repositories/execution_scheduling_repository.dart';
import 'package:aion/features/providers/presentation/cubit/execution_scheduling_cubit.dart';
import 'package:aion/features/tickets/domain/entities/ticket_list_sort.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_direction.dart';
import 'package:aion/features/tickets/domain/enums/ticket_sort_field.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockAgentProvider extends Mock implements AgentProvider {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

class MockActiveProjectProvider extends Mock implements ActiveProjectProvider {}

class MockBaselineRepository extends Mock implements BaselineRepository {}

class MockExecutionSchedulingRepository extends Mock
    implements ExecutionSchedulingRepository {}

class MockWorkflowConfigCubit extends MockCubit<WorkflowConfigState>
    implements WorkflowConfigCubit {}

/// A [WorkflowConfigLoaded] fixture built from [defaultWorkflowStatuses] —
/// the default status set [_wrap] uses unless a test case needs a
/// custom/reconfigured status set. Added for
/// `aion-arch/changes/v1-release-readiness` (T12), so
/// `_TicketFilterAndSortSection`'s (and every widget it constructs) new
/// `context.watch<WorkflowConfigCubit>()` calls don't throw
/// `ProviderNotFoundException` against this harness.
final WorkflowConfigLoaded _defaultWorkflowConfigLoaded = WorkflowConfigLoaded(
  statuses: defaultWorkflowStatuses,
  designStagesEnabled: false,
  stageDisplayNameOverrides: const {},
  attachments: const [],
  templates: const [],
);

Widget _wrap({
  required TicketsCubit ticketsCubit,
  required ActiveProjectProvider activeProjectProvider,
  required BaselineRepository baselineRepository,
  TicketLinkRepository? ticketLinkRepository,
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
            RepositoryProvider<BaselineRepository>.value(
              value: baselineRepository,
            ),
            if (ticketLinkRepository != null)
              RepositoryProvider<TicketLinkRepository>.value(
                value: ticketLinkRepository,
              ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<TicketsCubit>.value(value: ticketsCubit),
              BlocProvider<WorkflowConfigCubit>(
                create: (_) {
                  final workflowConfigCubit = MockWorkflowConfigCubit();
                  whenListen(
                    workflowConfigCubit,
                    Stream.value(_defaultWorkflowConfigLoaded),
                    initialState: _defaultWorkflowConfigLoaded,
                  );
                  return workflowConfigCubit;
                },
              ),
              BlocProvider<TicketSelectionCubit>(
                create: (_) => TicketSelectionCubit(),
              ),
              // BoardColumn (via TicketBoardView) reads this to decide
              // whether to cluster same-parent siblings — a plain
              // strictFifo/2 stub, since these tests don't exercise
              // Hybrid-mode clustering. Added for
              // `aion-arch/changes/parallel-work`.
              BlocProvider<ExecutionSchedulingCubit>(
                create: (_) {
                  final repo = MockExecutionSchedulingRepository();
                  when(
                    () => repo.getMode(),
                  ).thenAnswer((_) async => ExecutionSchedulingMode.strictFifo);
                  when(
                    () => repo.getConcurrencyCeiling(),
                  ).thenAnswer((_) async => 2);
                  return ExecutionSchedulingCubit(repo)..load();
                },
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
  late MockProviderRegistry registry;
  late MockActiveProjectProvider activeProjectProvider;
  late MockBaselineRepository baselineRepository;

  final activeProject = Project(
    id: '1',
    name: 'Fake Project',
    storageKey: '1',
    baselineVersion: '0.1.0',
    createdAt: DateTime(2026, 1, 1),
    lastOpenedAt: DateTime(2026, 1, 1),
  );

  setUpAll(() {
    registerFallbackValue(const AgentRequest(prompt: '', model: ''));
    registerFallbackValue(
      Ticket(
        id: 'fallback',
        ticketId: '',
        type: TicketType.idea,
        title: '',
        status: 'backlog',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    registerFallbackValue(TicketLinkType.relatesTo);
    registerFallbackValue(
      const TicketListSort(
        field: TicketSortField.createdAt,
        direction: TicketSortDirection.descending,
      ),
    );
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
    final provider = MockAgentProvider();
    registry = MockProviderRegistry();
    when(() => provider.client).thenReturn(agentClient);
    when(() => provider.availableModels).thenReturn(const [
      AgentModelDescriptor(
        providerId: ProviderId.claudeAgentSdk,
        modelId: 'claude-sonnet-5',
        label: 'Sonnet 5',
        contextWindowTokens: 200000,
      ),
    ]);
    when(
      () => provider.normalizeErrorMessage(any()),
    ).thenAnswer((invocation) => invocation.positionalArguments[0] as String);
    when(() => provider.describeOverage(any())).thenAnswer(
      (invocation) =>
          UsageWindowConsumption(invocation.positionalArguments[0] as String),
    );
    when(() => registry.availableProviders).thenReturn([provider]);
    when(
      () => registry.providerById(ProviderId.claudeAgentSdk),
    ).thenReturn(provider);
    activeProjectProvider = MockActiveProjectProvider();
    baselineRepository = MockBaselineRepository();

    when(
      () => repository.searchTickets(
        query: any(named: 'query'),
        statuses: any(named: 'statuses'),
        types: any(named: 'types'),
        priorities: any(named: 'priorities'),
        sort: any(named: 'sort'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      statusSortOrder: any(named: 'statusSortOrder'),
            ),
    ).thenAnswer(
      (_) async => const TicketSearchPage(tickets: [], hasMore: false),
    );
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
    // Default for TicketsCubit._computeBlockedTicketIds, called on every
    // searchTickets/loadMoreTickets success — board-task-ordering-
    // indication. No test in this file exercises actual blocked-badge
    // state, so an empty result everywhere is the correct default.
    when(
      () => linkRepository.getLinksByTypes(any()),
    ).thenAnswer((_) async => []);
    // Default for TicketsCubit._seedExecutionTokenTotals, called on
    // every searchTickets/loadMoreTickets/getTicketById success —
    // token-cost-prediction. No test in this file exercises actual
    // token-total display, so an empty result everywhere is the correct
    // default.
    when(
      () => repository.getExecutionTokenTotals(any()),
    ).thenAnswer((_) async => {});
    when(
      () => activeProjectProvider.consumeCodebaseAnalysisOffer(),
    ).thenReturn(null);
    when(() => activeProjectProvider.offerCodebaseAnalysis).thenReturn(false);
    when(() => activeProjectProvider.offerBaselineUpgrade).thenReturn(false);
    when(
      () => activeProjectProvider.consumeBaselineUpgradeOffer(),
    ).thenReturn(null);
    when(() => activeProjectProvider.activeProject).thenReturn(activeProject);
    when(
      () => baselineRepository.getAvailableBaselineVersions(),
    ).thenAnswer((_) async => ['0.1.0']);
  });

  TicketsCubit buildCubit() => TicketsCubit(
    repository,
    linkRepository: linkRepository,
    providerRegistry: registry,
    projectRootPath: '/fake/project/root',
    projectName: 'Fake Project',
  );

  testWidgets(
    'does not show the codebase-analysis banner when the active project '
    'has no pending offer',
    (tester) async {
      when(() => activeProjectProvider.offerCodebaseAnalysis).thenReturn(false);

      await tester.pumpWidget(
        _wrap(
          ticketsCubit: buildCubit(),
          activeProjectProvider: activeProjectProvider,
          baselineRepository: baselineRepository,
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
      when(() => activeProjectProvider.offerCodebaseAnalysis).thenReturn(true);

      await tester.pumpWidget(
        _wrap(
          ticketsCubit: buildCubit(),
          activeProjectProvider: activeProjectProvider,
          baselineRepository: baselineRepository,
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
      when(() => activeProjectProvider.offerCodebaseAnalysis).thenReturn(true);
      when(() => agentClient.run(any())).thenAnswer(
        (_) async => Stream.fromIterable(const [
          AgentTextEvent('FINDING: A finding\nA description.\nSUMMARY: DONE'),
          AgentDoneEvent(),
        ]),
      );

      await tester.pumpWidget(
        _wrap(
          ticketsCubit: buildCubit(),
          activeProjectProvider: activeProjectProvider,
          baselineRepository: baselineRepository,
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

  testWidgets('shows the baseline-upgrade banner only when the active project '
      'provider reports offerBaselineUpgrade: true', (tester) async {
    when(() => activeProjectProvider.offerBaselineUpgrade).thenReturn(true);
    when(
      () => baselineRepository.getAvailableBaselineVersions(),
    ).thenAnswer((_) async => ['0.1.0', '0.2.0']);

    await tester.pumpWidget(
      _wrap(
        ticketsCubit: buildCubit(),
        activeProjectProvider: activeProjectProvider,
        baselineRepository: baselineRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A newer baseline is available'), findsOneWidget);
    verify(() => activeProjectProvider.consumeBaselineUpgradeOffer()).called(1);
  });

  testWidgets(
    'tapping "Upgrade" calls acceptBaselineUpgrade and the banner never '
    'reappears after consumeBaselineUpgradeOffer fires',
    (tester) async {
      when(() => activeProjectProvider.offerBaselineUpgrade).thenReturn(true);
      when(
        () => baselineRepository.getAvailableBaselineVersions(),
      ).thenAnswer((_) async => ['0.1.0', '0.2.0']);
      when(
        () => activeProjectProvider.acceptBaselineUpgrade(),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        _wrap(
          ticketsCubit: buildCubit(),
          activeProjectProvider: activeProjectProvider,
          baselineRepository: baselineRepository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upgrade'));
      await tester.pumpAndSettle();

      verify(() => activeProjectProvider.acceptBaselineUpgrade()).called(1);
      expect(find.text('A newer baseline is available'), findsNothing);

      // Still only consumed once, at initState.
      verify(
        () => activeProjectProvider.consumeBaselineUpgradeOffer(),
      ).called(1);
    },
  );

  testWidgets('both the baseline-upgrade and codebase-analysis banners render '
      'simultaneously without layout errors when both offer flags are true', (
    tester,
  ) async {
    when(() => activeProjectProvider.offerBaselineUpgrade).thenReturn(true);
    when(() => activeProjectProvider.offerCodebaseAnalysis).thenReturn(true);
    when(
      () => baselineRepository.getAvailableBaselineVersions(),
    ).thenAnswer((_) async => ['0.1.0', '0.2.0']);

    await tester.pumpWidget(
      _wrap(
        ticketsCubit: buildCubit(),
        activeProjectProvider: activeProjectProvider,
        baselineRepository: baselineRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('A newer baseline is available'), findsOneWidget);
    expect(
      find.text('Draft a starting backlog from this codebase'),
      findsOneWidget,
    );
  });

  testWidgets('switching to board view shows story, task, and bug tickets', (
    tester,
  ) async {
    final story = Ticket(
      id: 'story-1',
      ticketId: 'AIO-1',
      type: TicketType.story,
      title: 'A story',
      status: 'backlog',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final task = Ticket(
      id: 'task-1',
      ticketId: 'AIO-2',
      type: TicketType.task,
      title: 'A task',
      status: 'backlog',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final bug = Ticket(
      id: 'bug-1',
      ticketId: 'AIO-3',
      type: TicketType.bug,
      title: 'A bug',
      status: 'backlog',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    when(
      () => repository.searchTickets(
        query: any(named: 'query'),
        statuses: any(named: 'statuses'),
        types: any(named: 'types'),
        priorities: any(named: 'priorities'),
        sort: any(named: 'sort'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      statusSortOrder: any(named: 'statusSortOrder'),
            ),
    ).thenAnswer(
      (_) async =>
          TicketSearchPage(tickets: [story, task, bug], hasMore: false),
    );
    when(
      () => linkRepository.getLinksForTicket(any()),
    ).thenAnswer((_) async => []);

    await tester.pumpWidget(
      _wrap(
        ticketsCubit: buildCubit(),
        activeProjectProvider: activeProjectProvider,
        baselineRepository: baselineRepository,
        ticketLinkRepository: linkRepository,
      ),
    );
    await tester.pumpAndSettle();

    final boardToggleFinder = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Switch to board view',
    );
    expect(boardToggleFinder, findsOneWidget);
    await tester.tap(boardToggleFinder);
    await tester.pumpAndSettle();

    expect(find.text('A story'), findsOneWidget);
    expect(find.text('A task'), findsOneWidget);
    expect(find.text('A bug'), findsOneWidget);
  });
}
