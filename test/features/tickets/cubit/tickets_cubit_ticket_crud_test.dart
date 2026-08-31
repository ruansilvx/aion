// test/features/tickets/cubit/tickets_cubit_ticket_crud_test.dart —
// TicketsCubit.create_ticket/add_link tool-call handler tests
// (aion-arch/changes/ticket-crud-tool-calls).
//
// Split into its own file (mirroring the existing
// tickets_cubit_codebase_analysis_test.dart/
// tickets_cubit_workflow_status_test.dart precedent for a cohesive slice
// of TicketsCubit coverage) rather than appended to the already
// enormous tickets_cubit_test.dart — that file's sheer size made the
// full suite intermittently fail unrelated tests ("Skill attachments
// (Phase 2)") purely from insertion-point/file-size sensitivity once
// this group was added there, with no logical connection between the
// two areas. This file is fully self-contained (its own Mock classes,
// fixtures, and `registerFallbackValue` calls) and runs cleanly in
// isolation and as part of the full suite.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_graph_evaluator.dart';
import 'package:aion/core/automation/decision_graph_repository.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';
import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/contracts/agent_provider.dart';
import 'package:aion/core/contracts/agent_session_handle.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockAutomationSettingsRepository extends Mock
    implements AutomationSettingsRepository {}

class MockDecisionGraphRepository extends Mock
    implements DecisionGraphRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockAgentProvider extends Mock implements AgentProvider {}

class MockProviderRegistry extends Mock implements ProviderRegistry {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockTicketRepository repository;
  late MockAutomationSettingsRepository automationSettingsRepository;
  late MockTicketLinkRepository linkRepository;
  // Wired for the `_askAgentJudgment` group below only — every other
  // group's `buildCubit()` never passes a `providerRegistry`, so these
  // mocks simply go unused there.
  late MockAgentModelClient client;
  late MockAgentProvider provider;
  late MockProviderRegistry registry;
  Map<String, dynamic>? result;

  // The ticket a `create_ticket`/`add_link` tool call is "working on" —
  // resolved via `chat.parentId`.
  final ticket = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Test ticket',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(TicketLinkType.relatesTo);
    // Needed for `repository.createTicket(any()/captureAny())` — mocktail
    // requires a fallback for any custom type used with those matchers.
    registerFallbackValue(ticket);
    // Needed for `client.run(any())` in the `_askAgentJudgment` group below.
    registerFallbackValue(const AgentRequest(prompt: '', model: ''));
    // Needed for `decisionGraphRepository.getGraph(any())`/`.getAllNodes
    // (any())` in that same group.
    registerFallbackValue(AutomationContext.ticketCreation);
  });

  // A chat parented by `ticket` — the shape every create_ticket/add_link
  // handler expects: chat.parentId is "the ticket being worked."
  final crudChat = Ticket(
    id: 'crud-chat',
    ticketId: 'AIO-40',
    type: TicketType.chat,
    title: 'Execution chat',
    status: 'backlog',
    parentId: ticket.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final targetTicket = Ticket(
    id: 'crud-target',
    ticketId: 'AIO-42',
    type: TicketType.task,
    title: 'Target ticket',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUp(() {
    repository = MockTicketRepository();
    automationSettingsRepository = MockAutomationSettingsRepository();
    linkRepository = MockTicketLinkRepository();
    client = MockAgentModelClient();
    provider = MockAgentProvider();
    registry = MockProviderRegistry();
    when(() => provider.client).thenReturn(client);
    when(
      () => registry.providerById(ProviderId.claudeAgentSdk),
    ).thenReturn(provider);
    result = null;
  });

  TicketsCubit buildCubit() => TicketsCubit(
    repository,
    automationSettingsRepository: automationSettingsRepository,
    linkRepository: linkRepository,
  );

  group('dispatch — handleChatToolCall routes by tool name', () {
    blocTest<TicketsCubit, TicketsState>(
      'create_ticket dispatches to _handleCreateTicketToolCall',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketCreation,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) async {
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'create_ticket',
          {'title': 'Follow-up', 'type': 'task'},
          null,
        );
      },
      verify: (_) {
        expect(result?['accepted'], true);
        verify(() => repository.createTicket(any())).called(1);
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'add_link dispatches to _handleAddLinkToolCall',
      setUp: () {
        when(
          () => repository.getTicketByTicketId(targetTicket.ticketId),
        ).thenAnswer((_) async => targetTicket);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketLinking,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(
          () => linkRepository.createLink(
            sourceTicketId: ticket.id,
            targetTicketId: targetTicket.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) async {
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'add_link',
          {'targetTicketId': targetTicket.ticketId, 'linkType': 'relatesTo'},
          null,
        );
      },
      verify: (_) {
        expect(result?['accepted'], true);
        verify(
          () => linkRepository.createLink(
            sourceTicketId: ticket.id,
            targetTicketId: targetTicket.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'an unrecognized tool name falls through to _handleBranchToolCall '
      '(the default case)',
      setUp: () {
        when(
          () => repository.getTicketById(ticket.id),
        ).thenAnswer((_) async => ticket);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.chatBranching,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) async {
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'branch_ticket',
          {'title': 'Sub-issue'},
          null,
        );
      },
      verify: (_) {
        expect(result?['accepted'], true);
        expect(result?['childChatId'], isA<String>());
      },
      expect: () => <TicketsState>[],
    );
  });

  group('AutomationContext.ticketCreation confidence branches', () {
    blocTest<TicketsCubit, TicketsState>(
      'manual declines outright',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketCreation,
          ),
        ).thenAnswer((_) async => AutomationConfidence.manual);
      },
      build: buildCubit,
      act: (cubit) async {
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'create_ticket',
          {'title': 'Follow-up', 'type': 'task'},
          null,
        );
      },
      verify: (_) {
        expect(result, {
          'accepted': false,
          'reason': 'Ticket creation set to manual.',
        });
        verifyNever(() => repository.createTicket(any()));
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'auto creates the ticket immediately, top-level (no parent)',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketCreation,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) async {
        result = await cubit
            .handleChatToolCall(crudChat, 'call-1', 'create_ticket', {
              'title': 'Follow-up bug',
              'type': 'bug',
              'description': 'Found while working on this',
            }, null);
      },
      verify: (_) {
        expect(result?['accepted'], true);
        expect(result?['createdTicketId'], isA<String>());
        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured;
        expect(created, hasLength(1));
        final createdTicket = created.single as Ticket;
        expect(createdTicket.type, TicketType.bug);
        expect(createdTicket.title, 'Follow-up bug');
        expect(createdTicket.description, 'Found while working on this');
        expect(createdTicket.parentId, isNull);
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'rejects an unrecognized type',
      build: buildCubit,
      act: (cubit) async {
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'create_ticket',
          {'title': 'Follow-up', 'type': 'epic'},
          null,
        );
      },
      verify: (_) {
        expect(result, {
          'accepted': false,
          'reason': 'type must be story, task, or bug.',
        });
        verifyNever(() => repository.createTicket(any()));
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'gated surfaces a CreateTicketProposal and pauses until confirmed',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketCreation,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(crudChat.id),
        ).thenAnswer((_) async => crudChat);
      },
      build: buildCubit,
      act: (cubit) async {
        unawaited(
          cubit
              .handleChatToolCall(crudChat, 'call-1', 'create_ticket', {
                'title': 'Follow-up',
                'type': 'task',
              }, null)
              .then((value) => result = value),
        );
        await Future<void>.delayed(Duration.zero);
        // Resolve the pending proposal before the test ends — leaving it
        // dangling forever would leak an unresolved Completer/pending
        // Future past this test's zone.
        await cubit.rejectPendingToolProposal(crudChat.id);
      },
      verify: (_) {
        verifyNever(() => repository.createTicket(any()));
        expect(result, {'accepted': false, 'reason': 'Declined by user.'});
      },
      expect: () => [
        isA<TicketDetailLoaded>()
            .having((s) => s.ticket.id, 'ticket.id', crudChat.id)
            .having(
              (s) => s.pendingToolProposal,
              'pendingToolProposal',
              const CreateTicketProposal(
                title: 'Follow-up',
                type: TicketType.task,
              ),
            ),
        isA<TicketDetailLoaded>()
            .having((s) => s.ticket.id, 'ticket.id', crudChat.id)
            .having(
              (s) => s.pendingToolProposal,
              'pendingToolProposal',
              isNull,
            ),
      ],
    );
  });

  group('AutomationContext.ticketLinking confidence branches', () {
    blocTest<TicketsCubit, TicketsState>(
      'manual declines outright',
      setUp: () {
        when(
          () => repository.getTicketByTicketId(targetTicket.ticketId),
        ).thenAnswer((_) async => targetTicket);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketLinking,
          ),
        ).thenAnswer((_) async => AutomationConfidence.manual);
      },
      build: buildCubit,
      act: (cubit) async {
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'add_link',
          {'targetTicketId': targetTicket.ticketId, 'linkType': 'blocks'},
          null,
        );
      },
      verify: (_) {
        expect(result, {
          'accepted': false,
          'reason': 'Ticket linking set to manual.',
        });
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'auto creates the link immediately',
      setUp: () {
        when(
          () => repository.getTicketByTicketId(targetTicket.ticketId),
        ).thenAnswer((_) async => targetTicket);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketLinking,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(
          () => linkRepository.createLink(
            sourceTicketId: ticket.id,
            targetTicketId: targetTicket.id,
            linkType: TicketLinkType.duplicates,
          ),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) async {
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'add_link',
          {'targetTicketId': targetTicket.ticketId, 'linkType': 'duplicates'},
          null,
        );
      },
      verify: (_) {
        expect(result, {'accepted': true});
        verify(
          () => linkRepository.createLink(
            sourceTicketId: ticket.id,
            targetTicketId: targetTicket.id,
            linkType: TicketLinkType.duplicates,
          ),
        ).called(1);
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'declines when targetTicketId does not resolve to any ticket',
      setUp: () {
        when(
          () => repository.getTicketByTicketId('AIO-999'),
        ).thenAnswer((_) async => null);
      },
      build: buildCubit,
      act: (cubit) async {
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'add_link',
          {'targetTicketId': 'AIO-999', 'linkType': 'blocks'},
          null,
        );
      },
      verify: (_) {
        expect(result, {
          'accepted': false,
          'reason': 'No ticket found with id "AIO-999".',
        });
        verifyNever(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketLinking,
          ),
        );
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'gated surfaces an AddLinkProposal and pauses until confirmed',
      setUp: () {
        when(
          () => repository.getTicketByTicketId(targetTicket.ticketId),
        ).thenAnswer((_) async => targetTicket);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketLinking,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);
        when(
          () => linkRepository.createLink(
            sourceTicketId: ticket.id,
            targetTicketId: targetTicket.id,
            linkType: TicketLinkType.blocks,
          ),
        ).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(crudChat.id),
        ).thenAnswer((_) async => crudChat);
      },
      build: buildCubit,
      act: (cubit) async {
        unawaited(
          cubit
              .handleChatToolCall(crudChat, 'call-1', 'add_link', {
                'targetTicketId': targetTicket.ticketId,
                'linkType': 'blocks',
              }, null)
              .then((value) => result = value),
        );
        await Future<void>.delayed(Duration.zero);
        // Resolve the pending proposal before the test ends — see the
        // matching comment on the create_ticket gated test above.
        await cubit.rejectPendingToolProposal(crudChat.id);
      },
      verify: (_) {
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: any(named: 'targetTicketId'),
            linkType: any(named: 'linkType'),
          ),
        );
        expect(result, {'accepted': false, 'reason': 'Declined by user.'});
      },
      expect: () => [
        isA<TicketDetailLoaded>()
            .having((s) => s.ticket.id, 'ticket.id', crudChat.id)
            .having(
              (s) => s.pendingToolProposal,
              'pendingToolProposal',
              AddLinkProposal(
                targetTicketId: targetTicket.ticketId,
                targetTicketTitle: targetTicket.title,
                linkType: TicketLinkType.blocks,
              ),
            ),
        isA<TicketDetailLoaded>()
            .having((s) => s.ticket.id, 'ticket.id', crudChat.id)
            .having(
              (s) => s.pendingToolProposal,
              'pendingToolProposal',
              isNull,
            ),
      ],
    );
  });

  group(
    'confirmPendingToolProposal / rejectPendingToolProposal — new kinds',
    () {
      setUp(() {
        when(
          () => repository.getTicketById(crudChat.id),
        ).thenAnswer((_) async => crudChat);
      });

      blocTest<TicketsCubit, TicketsState>(
        'confirming a pending CreateTicketProposal creates the ticket',
        setUp: () {
          when(
            () => automationSettingsRepository.getConfidence(
              AutomationContext.ticketCreation,
            ),
          ).thenAnswer((_) async => AutomationConfidence.gated);
          when(() => repository.createTicket(any())).thenAnswer((_) async {});
        },
        build: buildCubit,
        act: (cubit) async {
          unawaited(
            cubit
                .handleChatToolCall(crudChat, 'call-1', 'create_ticket', {
                  'title': 'Follow-up',
                  'type': 'task',
                }, null)
                .then((value) => result = value),
          );
          await Future<void>.delayed(Duration.zero);
          await cubit.confirmPendingToolProposal(crudChat.id);
        },
        verify: (_) {
          verify(() => repository.createTicket(any())).called(1);
          expect(result?['accepted'], true);
        },
        expect: () => [
          isA<TicketDetailLoaded>().having(
            (s) => s.pendingToolProposal,
            'pendingToolProposal',
            isNotNull,
          ),
          isA<TicketDetailLoaded>()
              .having((s) => s.ticket.id, 'ticket.id', crudChat.id)
              .having(
                (s) => s.pendingToolProposal,
                'pendingToolProposal',
                isNull,
              ),
        ],
      );

      blocTest<TicketsCubit, TicketsState>(
        'rejecting a pending AddLinkProposal never creates the link',
        setUp: () {
          when(
            () => repository.getTicketByTicketId(targetTicket.ticketId),
          ).thenAnswer((_) async => targetTicket);
          when(
            () => automationSettingsRepository.getConfidence(
              AutomationContext.ticketLinking,
            ),
          ).thenAnswer((_) async => AutomationConfidence.gated);
        },
        build: buildCubit,
        act: (cubit) async {
          unawaited(
            cubit
                .handleChatToolCall(crudChat, 'call-1', 'add_link', {
                  'targetTicketId': targetTicket.ticketId,
                  'linkType': 'relatesTo',
                }, null)
                .then((value) => result = value),
          );
          await Future<void>.delayed(Duration.zero);
          await cubit.rejectPendingToolProposal(crudChat.id);
        },
        verify: (_) {
          verifyNever(
            () => linkRepository.createLink(
              sourceTicketId: any(named: 'sourceTicketId'),
              targetTicketId: any(named: 'targetTicketId'),
              linkType: any(named: 'linkType'),
            ),
          );
          expect(result, {'accepted': false, 'reason': 'Declined by user.'});
        },
        expect: () => [
          isA<TicketDetailLoaded>().having(
            (s) => s.pendingToolProposal,
            'pendingToolProposal',
            isNotNull,
          ),
          isA<TicketDetailLoaded>()
              .having((s) => s.ticket.id, 'ticket.id', crudChat.id)
              .having(
                (s) => s.pendingToolProposal,
                'pendingToolProposal',
                isNull,
              ),
        ],
      );
    },
  );

  group('_askAgentJudgment (via _handleCreateTicketToolCall)', () {
    // Single agentJudgment node for AutomationContext.ticketCreation:
    // matched (a "yes" answer) → decline (blocked, resolves immediately —
    // no proposal-confirmation dance to unwind in these tests), unmatched
    // (a "no"/null/ambiguous answer) → proceed (creates immediately).
    final agentJudgmentGraph = DecisionGraph(
      context: AutomationContext.ticketCreation,
      rootNodeId: 'node-1',
    );
    const agentJudgmentNode = DecisionNode(
      id: 'node-1',
      conditionId: agentJudgmentConditionId,
      conditionParams: {'prompt': 'Is this expensive?'},
      matchedBranch: DecisionBranch.terminal(DecisionOutcome.decline),
      unmatchedBranch: DecisionBranch.terminal(DecisionOutcome.proceed),
    );
    const session = AgentSessionHandle(
      providerId: ProviderId.claudeAgentSdk,
      sessionId: 'sess-1',
      modelId: 'claude-sonnet-5',
    );

    late MockDecisionGraphRepository decisionGraphRepository;

    setUp(() {
      decisionGraphRepository = MockDecisionGraphRepository();
      // Every context defaults to a null-root graph (TicketsCubit's
      // constructor loads every AutomationContext's graph up front, not
      // just ticketCreation's) — overridden below for ticketCreation only.
      when(() => decisionGraphRepository.getGraph(any())).thenAnswer(
        (invocation) async => DecisionGraph(
          context: invocation.positionalArguments.single as AutomationContext,
          rootNodeId: null,
        ),
      );
      when(
        () => decisionGraphRepository.getAllNodes(any()),
      ).thenAnswer((_) async => const []);
      when(
        () =>
            decisionGraphRepository.getGraph(AutomationContext.ticketCreation),
      ).thenAnswer((_) async => agentJudgmentGraph);
      when(
        () => decisionGraphRepository.getAllNodes(
          AutomationContext.ticketCreation,
        ),
      ).thenAnswer((_) async => const [agentJudgmentNode]);
      when(
        () => decisionGraphRepository.onChanged,
      ).thenAnswer((_) => const Stream<void>.empty());
      when(
        () => automationSettingsRepository.getConfidence(
          AutomationContext.ticketCreation,
        ),
      ).thenAnswer((_) async => AutomationConfidence.auto);
      when(() => repository.createTicket(any())).thenAnswer((_) async {});
    });

    /// [TicketsCubit]'s constructor fires `_loadDecisionGraphs` unawaited
    /// — every `act:` below awaits this once, first, mirroring
    /// `tickets_cubit_decision_graph_test.dart`'s own
    /// `awaitDecisionGraphsLoaded` precedent.
    Future<void> awaitDecisionGraphsLoaded() =>
        Future<void>.delayed(Duration.zero);

    Future<Map<String, dynamic>> callWithSession(TicketsCubit cubit) =>
        cubit.handleChatToolCall(crudChat, 'call-1', 'create_ticket', {
          'title': 'Follow-up',
          'type': 'task',
        }, session);

    blocTest<TicketsCubit, TicketsState>(
      'a provider with supportsSessionResume == false resolves unmatched, '
      'no client.run call attempted',
      setUp: () {
        when(() => provider.supportsSessionResume).thenReturn(false);
      },
      build: () => TicketsCubit(
        repository,
        automationSettingsRepository: automationSettingsRepository,
        linkRepository: linkRepository,
        decisionGraphRepository: decisionGraphRepository,
        providerRegistry: registry,
      ),
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await callWithSession(cubit);
      },
      verify: (_) {
        expect(result?['accepted'], true); // unmatched → proceed → created.
        verifyNever(() => client.run(any()));
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'AgentTextEvent("Yes") → AgentDoneEvent() matches, blocking creation',
      setUp: () {
        when(() => provider.supportsSessionResume).thenReturn(true);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Yes'),
            AgentDoneEvent(),
          ]),
        );
      },
      build: () => TicketsCubit(
        repository,
        automationSettingsRepository: automationSettingsRepository,
        linkRepository: linkRepository,
        decisionGraphRepository: decisionGraphRepository,
        providerRegistry: registry,
      ),
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await callWithSession(cubit);
      },
      verify: (_) {
        expect(result, {
          'accepted': false,
          'reason': 'Blocked by decision graph.',
        });
        verifyNever(() => repository.createTicket(any()));
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'AgentTextEvent("No") is unmatched, creating immediately',
      setUp: () {
        when(() => provider.supportsSessionResume).thenReturn(true);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('No'),
            AgentDoneEvent(),
          ]),
        );
      },
      build: () => TicketsCubit(
        repository,
        automationSettingsRepository: automationSettingsRepository,
        linkRepository: linkRepository,
        decisionGraphRepository: decisionGraphRepository,
        providerRegistry: registry,
      ),
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await callWithSession(cubit);
      },
      verify: (_) {
        expect(result?['accepted'], true);
        verify(() => repository.createTicket(any())).called(1);
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'AgentErrorEvent is unmatched, creating immediately',
      setUp: () {
        when(() => provider.supportsSessionResume).thenReturn(true);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentErrorEvent('boom')]),
        );
      },
      build: () => TicketsCubit(
        repository,
        automationSettingsRepository: automationSettingsRepository,
        linkRepository: linkRepository,
        decisionGraphRepository: decisionGraphRepository,
        providerRegistry: registry,
      ),
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await callWithSession(cubit);
      },
      verify: (_) {
        expect(result?['accepted'], true);
        verify(() => repository.createTicket(any())).called(1);
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'AgentCancelledEvent is unmatched, creating immediately',
      setUp: () {
        when(() => provider.supportsSessionResume).thenReturn(true);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [AgentCancelledEvent()]),
        );
      },
      build: () => TicketsCubit(
        repository,
        automationSettingsRepository: automationSettingsRepository,
        linkRepository: linkRepository,
        decisionGraphRepository: decisionGraphRepository,
        providerRegistry: registry,
      ),
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await callWithSession(cubit);
      },
      verify: (_) {
        expect(result?['accepted'], true);
        verify(() => repository.createTicket(any())).called(1);
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'ambiguous text is unmatched, creating immediately',
      setUp: () {
        when(() => provider.supportsSessionResume).thenReturn(true);
        when(() => client.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent('Maybe, hard to say'),
            AgentDoneEvent(),
          ]),
        );
      },
      build: () => TicketsCubit(
        repository,
        automationSettingsRepository: automationSettingsRepository,
        linkRepository: linkRepository,
        decisionGraphRepository: decisionGraphRepository,
        providerRegistry: registry,
      ),
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await callWithSession(cubit);
      },
      verify: (_) {
        expect(result?['accepted'], true);
        verify(() => repository.createTicket(any())).called(1);
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'no ProviderRegistry at all resolves unmatched, no lookup attempted',
      build: () => TicketsCubit(
        repository,
        automationSettingsRepository: automationSettingsRepository,
        linkRepository: linkRepository,
        decisionGraphRepository: decisionGraphRepository,
      ),
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await callWithSession(cubit);
      },
      verify: (_) {
        expect(result?['accepted'], true);
        verify(() => repository.createTicket(any())).called(1);
      },
      expect: () => <TicketsState>[],
    );
  });
}
