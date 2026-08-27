// test/features/tickets/presentation/screens/ticket_detail_screen_test.dart — TicketDetailScreen widget tests.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/core.dart';
import 'package:aion/design_system/design_system.dart';
import 'package:aion/features/tickets/tickets.dart';
import 'package:aion/l10n/generated/app_localizations.dart';

class MockTicketsCubit extends MockCubit<TicketsState>
    implements TicketsCubit {}

class MockChatCubit extends MockCubit<ChatState> implements ChatCubit {}

class MockCommentsCubit extends MockCubit<CommentsState>
    implements CommentsCubit {}

class MockWorkflowConfigCubit extends MockCubit<WorkflowConfigState>
    implements WorkflowConfigCubit {}

class MockAutomationSettingsRepository extends Mock
    implements AutomationSettingsRepository {}

class MockDecisionGraphRepository extends Mock
    implements DecisionGraphRepository {}

final WorkflowConfigLoaded _defaultWorkflowConfigLoaded = WorkflowConfigLoaded(
  statuses: defaultWorkflowStatuses,
  designStagesEnabled: false,
  stageDisplayNameOverrides: const {},
  attachments: const [],
  templates: const [],
);

/// Builds a fixture [Ticket] of [type] with a unique-enough id, matching
/// the minimal-fields shape other tests in this suite use.
Ticket _ticketOf(TicketType type) => Ticket(
  id: 'ticket-${type.name}',
  ticketId: 'AIO-1',
  type: type,
  title: 'Fixture ${type.name} ticket',
  status: 'backlog',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// Wraps [TicketDetailScreen] for [ticket], backed by mock cubits whose
/// `TicketsCubit` state stream transitions from [TicketsLoading] to a
/// [TicketDetailLoaded] for [ticket] — a genuine stream emission (not
/// just `initialState`), so `TicketDetailScreen`'s top-level
/// `BlocListener` — the one this suite is targeting — actually fires,
/// mirroring a real `getTicketById` call resolving. Provides only the
/// providers `TicketDetailScreen` (and, for every non-`chat` type, the
/// `TicketMetadataSection` it renders) reads unconditionally;
/// `ActiveProjectProvider`/`ActiveTicketViewRegistry`/
/// `TicketRepairService` are all read via a try/catch guard in the real
/// widgets and deliberately omitted here.
Widget _wrap({
  required Ticket ticket,
  required MockTicketsCubit ticketsCubit,
  required MockAutomationSettingsRepository automationRepo,
  MockDecisionGraphRepository? decisionGraphRepository,
  AutomationConfidence sddStageConfidence = AutomationConfidence.gated,
}) {
  whenListen(
    ticketsCubit,
    Stream.fromIterable([const TicketsLoading(), TicketDetailLoaded(ticket)]),
    initialState: const TicketsLoading(),
  );
  when(
    () => ticketsCubit.detailTick,
  ).thenAnswer((_) => const Stream<void>.empty());

  // Every `TicketDetailScreen` reach in the real app has this provided at
  // the project shell level (`app_router.dart`, alongside
  // `WorkflowStatusRepository`) — `initState` reads it unconditionally
  // once `AutomationContext.sddStage`'s confidence resolves `auto` (see
  // `aion-arch/changes/automation-decision-graphs/design.md` §4). Callers
  // that care about its stubbed responses pass their own mock; everyone
  // else gets a default null-root graph, matching the seeded baseline.
  final resolvedDecisionGraphRepository =
      decisionGraphRepository ?? MockDecisionGraphRepository();
  if (decisionGraphRepository == null) {
    when(
      () => resolvedDecisionGraphRepository.getGraph(any()),
    ).thenAnswer(
      (invocation) async => DecisionGraph(
        context: invocation.positionalArguments.single as AutomationContext,
        rootNodeId: null,
      ),
    );
  }

  final chatCubit = MockChatCubit();
  whenListen(
    chatCubit,
    const Stream<ChatState>.empty(),
    initialState: const ChatInitial(),
  );
  when(() => chatCubit.loadMessages(any())).thenAnswer((_) async {});

  final commentsCubit = MockCommentsCubit();
  whenListen(
    commentsCubit,
    const Stream<CommentsState>.empty(),
    initialState: const CommentsInitial(),
  );
  when(() => commentsCubit.loadComments(any())).thenAnswer((_) async {});

  final workflowConfigCubit = MockWorkflowConfigCubit();
  whenListen(
    workflowConfigCubit,
    Stream.value(_defaultWorkflowConfigLoaded),
    initialState: _defaultWorkflowConfigLoaded,
  );

  when(() => automationRepo.getConfidence(any())).thenAnswer((invocation) async {
    final context = invocation.positionalArguments.single as AutomationContext;
    return context == AutomationContext.sddStage
        ? sddStageConfidence
        : AutomationConfidence.gated;
  });

  return MediaQuery(
    data: const MediaQueryData(),
    child: ThemeScope(
      theme: aionThemeArctic,
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AutomationSettingsRepository>.value(
            value: automationRepo,
          ),
          RepositoryProvider<DecisionGraphRepository>.value(
            value: resolvedDecisionGraphRepository,
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<TicketsCubit>.value(value: ticketsCubit),
            BlocProvider<ChatCubit>.value(value: chatCubit),
            BlocProvider<CommentsCubit>.value(value: commentsCubit),
            BlocProvider<WorkflowConfigCubit>.value(value: workflowConfigCubit),
          ],
          child: WidgetsApp(
            color: aionThemeArctic.colors.primary,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, _) =>
                TicketDetailScreen(ticketId: ticket.id),
          ),
        ),
      ),
    ),
  );
}

/// Stubs every `TicketsCubit` method [TicketDetailScreen] and the
/// non-`chat`-type widget subtree it renders (`TicketMetadataSection`,
/// and — via that — `TicketParentPicker`) call unconditionally, beyond
/// the state-stream wiring `_wrap` itself sets up. Shared by both test
/// groups below so neither can drift out of sync and start missing a
/// stub the other already covers.
void _stubTicketsCubit(MockTicketsCubit ticketsCubit) {
  when(
    () => ticketsCubit.loadDocumentRelations(any()),
  ).thenAnswer((_) async {});
  when(() => ticketsCubit.getTicketById(any())).thenAnswer((_) async {});
  when(() => ticketsCubit.startDetailTicker()).thenReturn(null);
  when(() => ticketsCubit.stopDetailTicker()).thenReturn(null);
  when(
    () => ticketsCubit.getValidParentCandidates(any()),
  ).thenAnswer((_) async => const []);
}

void main() {
  setUpAll(() {
    registerFallbackValue(AutomationContext.sddStage);
    registerFallbackValue(
      Ticket(
        id: 'fallback',
        ticketId: 'AIO-0',
        type: TicketType.task,
        title: 'fallback',
        status: 'backlog',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  });

  group('TicketDetailScreen — loadDocumentRelations trigger', () {
    for (final type in [
      TicketType.epic,
      TicketType.story,
      TicketType.task,
      TicketType.resource,
      TicketType.bug,
    ]) {
      testWidgets(
        'calls loadDocumentRelations for a $type ticket '
        '(board-task-ordering-indication widened this from resource/bug-'
        'only — regression test for the screen-level trigger that was '
        'missed when that change shipped)',
        (tester) async {
          final ticket = _ticketOf(type);
          final ticketsCubit = MockTicketsCubit();
          final automationRepo = MockAutomationSettingsRepository();
          _stubTicketsCubit(ticketsCubit);

          await tester.pumpWidget(
            _wrap(
              ticket: ticket,
              ticketsCubit: ticketsCubit,
              automationRepo: automationRepo,
            ),
          );
          await tester.pump();

          verify(
            () => ticketsCubit.loadDocumentRelations(ticket.id),
          ).called(1);
        },
      );
    }

    for (final type in [TicketType.chat, TicketType.idea]) {
      testWidgets(
        'does NOT call loadDocumentRelations for a $type ticket '
        "(no TicketLink use case — TicketMetadataSection's own render "
        'gate excludes it too)',
        (tester) async {
          final ticket = _ticketOf(type);
          final ticketsCubit = MockTicketsCubit();
          final automationRepo = MockAutomationSettingsRepository();
          _stubTicketsCubit(ticketsCubit);

          await tester.pumpWidget(
            _wrap(
              ticket: ticket,
              ticketsCubit: ticketsCubit,
              automationRepo: automationRepo,
            ),
          );
          await tester.pump();

          verifyNever(() => ticketsCubit.loadDocumentRelations(any()));
        },
      );
    }
  });

  group(
    'TicketDetailScreen — AutomationContext.sddStage decision-graph '
    'consultation (aion-arch/changes/automation-decision-graphs)',
    () {
      testWidgets(
        'auto confidence + null-root graph: reads the graph but never '
        'walks it (getAllNodes not called) — the seeded baseline, no '
        'behavior change from before this proposal',
        (tester) async {
          final ticket = _ticketOf(TicketType.task);
          final ticketsCubit = MockTicketsCubit();
          final automationRepo = MockAutomationSettingsRepository();
          final decisionGraphRepository = MockDecisionGraphRepository();
          _stubTicketsCubit(ticketsCubit);
          when(
            () => decisionGraphRepository.getGraph(AutomationContext.sddStage),
          ).thenAnswer(
            (_) async => const DecisionGraph(
              context: AutomationContext.sddStage,
              rootNodeId: null,
            ),
          );

          await tester.pumpWidget(
            _wrap(
              ticket: ticket,
              ticketsCubit: ticketsCubit,
              automationRepo: automationRepo,
              decisionGraphRepository: decisionGraphRepository,
              sddStageConfidence: AutomationConfidence.auto,
            ),
          );
          await tester.pump();
          await tester.pump();

          verify(
            () => decisionGraphRepository.getGraph(AutomationContext.sddStage),
          ).called(1);
          verifyNever(
            () => decisionGraphRepository.getAllNodes(any()),
          );
        },
      );

      testWidgets(
        'auto confidence + configured graph resolving gated: walks the '
        'graph via getAllNodes, without throwing',
        (tester) async {
          final ticket = _ticketOf(TicketType.task);
          final ticketsCubit = MockTicketsCubit();
          final automationRepo = MockAutomationSettingsRepository();
          final decisionGraphRepository = MockDecisionGraphRepository();
          _stubTicketsCubit(ticketsCubit);
          when(
            () => decisionGraphRepository.getGraph(AutomationContext.sddStage),
          ).thenAnswer(
            (_) async => const DecisionGraph(
              context: AutomationContext.sddStage,
              rootNodeId: 'sdd-node-1',
            ),
          );
          when(
            () =>
                decisionGraphRepository.getAllNodes(AutomationContext.sddStage),
          ).thenAnswer(
            (_) async => [
              DecisionNode(
                id: 'sdd-node-1',
                conditionId: 'sessionOverageDetected',
                conditionParams: const {},
                matchedBranch: const DecisionBranch.terminal(
                  DecisionOutcome.proceed,
                ),
                // A plain `DecisionEvalContext()` always takes the
                // unmatched branch — `sessionOverageDetected` defaults
                // `false` — so this is how the fixture pins `gated`.
                unmatchedBranch: const DecisionBranch.terminal(
                  DecisionOutcome.gated,
                ),
              ),
            ],
          );

          await tester.pumpWidget(
            _wrap(
              ticket: ticket,
              ticketsCubit: ticketsCubit,
              automationRepo: automationRepo,
              decisionGraphRepository: decisionGraphRepository,
              sddStageConfidence: AutomationConfidence.auto,
            ),
          );
          await tester.pump();
          await tester.pump();

          verify(
            () =>
                decisionGraphRepository.getAllNodes(AutomationContext.sddStage),
          ).called(1);
          // The screen builds and settles without error even once the
          // graph resolves a non-`proceed` outcome — `tester.pump()`
          // above would surface a widget-test failure on any uncaught
          // exception from `initState`'s decision-graph read.
        },
      );

      testWidgets(
        'gated confidence: never reads the decision graph at all — only '
        'ever consulted once sddStage confidence has already resolved '
        'auto',
        (tester) async {
          final ticket = _ticketOf(TicketType.task);
          final ticketsCubit = MockTicketsCubit();
          final automationRepo = MockAutomationSettingsRepository();
          final decisionGraphRepository = MockDecisionGraphRepository();
          _stubTicketsCubit(ticketsCubit);

          await tester.pumpWidget(
            _wrap(
              ticket: ticket,
              ticketsCubit: ticketsCubit,
              automationRepo: automationRepo,
              decisionGraphRepository: decisionGraphRepository,
            ),
          );
          // `_wrap`'s own blanket stub already resolves every context to
          // `gated` — left as-is here, matching this test's intent.
          await tester.pump();
          await tester.pump();

          verifyNever(() => decisionGraphRepository.getGraph(any()));
          verifyNever(() => decisionGraphRepository.getAllNodes(any()));
        },
      );
    },
  );
}
