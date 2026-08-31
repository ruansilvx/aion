// test/features/tickets/cubit/tickets_cubit_decision_graph_test.dart —
// TicketsCubit's AutomationContext decision-graph consultation tests
// (aion-arch/changes/automation-decision-graphs).
//
// Self-contained (own Mock classes, fixtures, registerFallbackValue calls),
// mirroring tickets_cubit_ticket_crud_test.dart's own precedent for a
// cohesive slice of TicketsCubit coverage split out of the enormous
// tickets_cubit_test.dart.
//
// Covers every AutomationContext consulted from a `case
// AutomationConfidence.auto:` branch this proposal touches:
// ticketCreation, ticketLinking, chatBranching, specAutoLink directly
// against TicketsCubit here; codingExecution/codingExecutionRetry's
// seeded-baseline-graph parity is covered instead by
// automation_decision_dao_test.dart (the exact baseline data) and
// decision_graph_evaluator_test.dart (the pure evaluation of that data)
// — `_runCodingExecution`'s own worktree/git/chat-turn setup is out of
// scope for a graph-consultation-focused test file. sddStage/
// codingExecutionResume ship with `null`-root baseline graphs, so their
// `auto` behavior is unaffected structurally by every other test here
// exercising the shared null-root → proceed path.

import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/automation/automation_confidence.dart';
import 'package:aion/core/automation/automation_context.dart';
import 'package:aion/core/automation/automation_settings_repository.dart';
import 'package:aion/core/automation/decision_graph.dart';
import 'package:aion/core/automation/decision_graph_repository.dart';
import 'package:aion/core/automation/decision_node.dart';
import 'package:aion/core/automation/decision_outcome.dart';
import 'package:aion/core/contracts/embedding_provider.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

class MockAutomationSettingsRepository extends Mock
    implements AutomationSettingsRepository {}

class MockDecisionGraphRepository extends Mock
    implements DecisionGraphRepository {}

class MockEmbeddingProvider extends Mock implements EmbeddingProvider {}

/// A single-node graph: `conditionId` always matches (via
/// `alwaysMatchesCondition`'s fixed evaluator id below is not needed —
/// this repository is a plain mock, `getAllNodes`/`getGraph` just return
/// canned data) whose matched/unmatched branches resolve to whatever
/// [matched]/[unmatched] outcomes the test wants.
DecisionGraph _graphWithRoot(AutomationContext context) =>
    DecisionGraph(context: context, rootNodeId: 'node-1');

DecisionNode _singleNode({
  required DecisionOutcome matched,
  required DecisionOutcome unmatched,
}) => DecisionNode(
  id: 'node-1',
  // `sessionOverageDetected` takes no params and is `false` by default in
  // a plain `DecisionEvalContext()` — an always-unmatched condition here,
  // so stubbing the *unmatched* branch is how these fixtures pin the
  // outcome a test wants. Any registered conditionId with no matching
  // input works the same way; this one is picked because it's a real
  // shipped catalog entry.
  conditionId: 'sessionOverageDetected',
  conditionParams: const {},
  matchedBranch: DecisionBranch.terminal(matched),
  unmatchedBranch: DecisionBranch.terminal(unmatched),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockTicketRepository repository;
  late MockAutomationSettingsRepository automationSettingsRepository;
  late MockTicketLinkRepository linkRepository;
  late MockDecisionGraphRepository decisionGraphRepository;
  late MockEmbeddingProvider embeddingProvider;
  Map<String, dynamic>? result;

  final ticket = Ticket(
    id: '1',
    ticketId: 'AIO-1',
    type: TicketType.task,
    title: 'Test ticket',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

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

  // The `chatBranching` fixtures below need `chat` to already have a
  // non-`chat` parent, satisfying `_canBranch`'s unconditional depth-cap
  // pre-check before automation confidence is even consulted.
  final branchParent = Ticket(
    id: 'branch-parent',
    ticketId: 'AIO-50',
    type: TicketType.task,
    title: 'Branch parent',
    status: 'backlog',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final branchChat = Ticket(
    id: 'branch-chat',
    ticketId: 'AIO-51',
    type: TicketType.chat,
    title: 'Branch chat',
    status: 'backlog',
    parentId: branchParent.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(TicketLinkType.relatesTo);
    registerFallbackValue(ticket);
    registerFallbackValue(AutomationContext.ticketCreation);
  });

  setUp(() {
    repository = MockTicketRepository();
    automationSettingsRepository = MockAutomationSettingsRepository();
    linkRepository = MockTicketLinkRepository();
    decisionGraphRepository = MockDecisionGraphRepository();
    embeddingProvider = MockEmbeddingProvider();
    result = null;

    // Every context defaults to a null-root graph unless a test
    // overrides it — the seeded baseline for the six non-coding-execution
    // contexts this file exercises.
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
      () => decisionGraphRepository.onChanged,
    ).thenAnswer((_) => const Stream<void>.empty());
  });

  TicketsCubit buildCubit() => TicketsCubit(
    repository,
    automationSettingsRepository: automationSettingsRepository,
    linkRepository: linkRepository,
    decisionGraphRepository: decisionGraphRepository,
    embeddingProvider: embeddingProvider,
  );

  /// [TicketsCubit]'s constructor fires [TicketsCubit
  /// ._loadDecisionGraphs] `unawaited` — it caches every context's graph
  /// before any `case auto:` decision-graph consultation can see it.
  /// Every `act:` callback below awaits this once, first, so that cache
  /// (populated from stubs `setUp`/blocTest's own `setUp:` already
  /// registered before `build:` ran) is guaranteed populated before the
  /// tool call under test is dispatched — `bloc_test`'s own `build:`
  /// parameter can't be async here (it's typed as a bare, synchronous
  /// `TicketsCubit Function()` in the installed `bloc_test` version).
  Future<void> awaitDecisionGraphsLoaded() =>
      Future<void>.delayed(Duration.zero);

  /// Stubs [decisionGraphRepository] so [context]'s graph resolves to a
  /// single node whose unmatched branch (the branch a plain
  /// `DecisionEvalContext()` always takes, since `sessionOverageDetected`
  /// defaults `false`) is [outcome].
  void stubGraphOutcome(AutomationContext context, DecisionOutcome outcome) {
    when(
      () => decisionGraphRepository.getGraph(context),
    ).thenAnswer((_) async => _graphWithRoot(context));
    when(() => decisionGraphRepository.getAllNodes(context)).thenAnswer(
      (_) async => [
        _singleNode(matched: DecisionOutcome.gated, unmatched: outcome),
      ],
    );
  }

  group('AutomationContext.ticketCreation', () {
    blocTest<TicketsCubit, TicketsState>(
      'auto + null-root graph creates immediately, exactly as before',
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
        await awaitDecisionGraphsLoaded();
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
      'auto + graph resolving decline blocks creation, never surfacing '
      'a proposal',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketCreation,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        stubGraphOutcome(
          AutomationContext.ticketCreation,
          DecisionOutcome.decline,
        );
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
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
          'reason': 'Blocked by decision graph.',
        });
        verifyNever(() => repository.createTicket(any()));
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'auto + graph resolving gated routes through the existing '
      '_awaitProposalConfirmation surface',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketCreation,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        stubGraphOutcome(
          AutomationContext.ticketCreation,
          DecisionOutcome.gated,
        );
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
        when(
          () => repository.getTicketById(crudChat.id),
        ).thenAnswer((_) async => crudChat);
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
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
        expect(result?['accepted'], true);
        verify(() => repository.createTicket(any())).called(1);
      },
      expect: () => [
        isA<TicketDetailLoaded>().having(
          (s) => s.pendingToolProposal,
          'pendingToolProposal',
          isNotNull,
        ),
        isA<TicketDetailLoaded>().having(
          (s) => s.pendingToolProposal,
          'pendingToolProposal',
          isNull,
        ),
      ],
    );

    blocTest<TicketsCubit, TicketsState>(
      'gated confidence is untouched by the decision graph — even one '
      'stubbed to resolve decline, since the graph is only ever '
      'consulted once a context has already resolved to auto',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketCreation,
          ),
        ).thenAnswer((_) async => AutomationConfidence.gated);
        // If this were wrongly consulted under `gated`, this stub would
        // make the ticket-creation flow decline outright instead of
        // surfacing gated's own proposal-and-wait behavior below.
        stubGraphOutcome(
          AutomationContext.ticketCreation,
          DecisionOutcome.decline,
        );
        when(
          () => repository.getTicketById(crudChat.id),
        ).thenAnswer((_) async => crudChat);
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        unawaited(
          cubit
              .handleChatToolCall(crudChat, 'call-1', 'create_ticket', {
                'title': 'Follow-up',
                'type': 'task',
              }, null)
              .then((value) => result = value),
        );
        await Future<void>.delayed(Duration.zero);
        await cubit.rejectPendingToolProposal(crudChat.id);
      },
      verify: (_) {
        expect(result, {'accepted': false, 'reason': 'Declined by user.'});
      },
      expect: () => [isA<TicketDetailLoaded>(), isA<TicketDetailLoaded>()],
    );

    blocTest<TicketsCubit, TicketsState>(
      'manual confidence is untouched by the decision graph — even one '
      'stubbed to resolve decline',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketCreation,
          ),
        ).thenAnswer((_) async => AutomationConfidence.manual);
        stubGraphOutcome(
          AutomationContext.ticketCreation,
          DecisionOutcome.decline,
        );
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'create_ticket',
          {'title': 'Follow-up', 'type': 'task'},
          null,
        );
      },
      verify: (_) {
        // "Ticket creation set to manual." — manual's own decline
        // reason, not the graph's "Blocked by decision graph."
        expect(result, {
          'accepted': false,
          'reason': 'Ticket creation set to manual.',
        });
      },
      expect: () => <TicketsState>[],
    );
  });

  group('AutomationContext.ticketLinking', () {
    blocTest<TicketsCubit, TicketsState>(
      'auto + null-root graph creates the link immediately',
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
        await awaitDecisionGraphsLoaded();
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
      'auto + graph resolving decline blocks the link',
      setUp: () {
        when(
          () => repository.getTicketByTicketId(targetTicket.ticketId),
        ).thenAnswer((_) async => targetTicket);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.ticketLinking,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        stubGraphOutcome(
          AutomationContext.ticketLinking,
          DecisionOutcome.decline,
        );
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await cubit.handleChatToolCall(
          crudChat,
          'call-1',
          'add_link',
          {'targetTicketId': targetTicket.ticketId, 'linkType': 'relatesTo'},
          null,
        );
      },
      verify: (_) {
        expect(result, {
          'accepted': false,
          'reason': 'Blocked by decision graph.',
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
  });

  group('AutomationContext.chatBranching', () {
    blocTest<TicketsCubit, TicketsState>(
      'auto + null-root graph creates the branch immediately',
      setUp: () {
        when(
          () => repository.getTicketById(branchParent.id),
        ).thenAnswer((_) async => branchParent);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.chatBranching,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        result = await cubit.handleChatToolCall(
          branchChat,
          'call-1',
          'branch_ticket',
          {'title': 'Sub-issue'},
          null,
        );
      },
      verify: (_) {
        expect(result?['accepted'], true);
      },
      expect: () => <TicketsState>[],
    );

    blocTest<TicketsCubit, TicketsState>(
      'auto + graph resolving gated pauses for confirmation, after the '
      'unconditional _canBranch depth-cap check already passed',
      setUp: () {
        when(
          () => repository.getTicketById(branchParent.id),
        ).thenAnswer((_) async => branchParent);
        when(
          () => repository.getTicketById(branchChat.id),
        ).thenAnswer((_) async => branchChat);
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.chatBranching,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        stubGraphOutcome(
          AutomationContext.chatBranching,
          DecisionOutcome.gated,
        );
        when(() => repository.createTicket(any())).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        unawaited(
          cubit
              .handleChatToolCall(branchChat, 'call-1', 'branch_ticket', {
                'title': 'Sub-issue',
              }, null)
              .then((value) => result = value),
        );
        await Future<void>.delayed(Duration.zero);
        await cubit.confirmPendingToolProposal(branchChat.id);
      },
      verify: (_) {
        expect(result?['accepted'], true);
        expect(result?['childChatId'], isA<String>());
      },
      expect: () => [
        isA<TicketDetailLoaded>().having(
          (s) => s.pendingToolProposal,
          'pendingToolProposal',
          isNotNull,
        ),
        isA<TicketDetailLoaded>().having(
          (s) => s.pendingToolProposal,
          'pendingToolProposal',
          isNull,
        ),
      ],
    );
  });

  group('AutomationContext.specAutoLink', () {
    // Identical unit vectors → cosine similarity 1.0 (above the 0.75
    // threshold) — mirrors `tickets_cubit_test.dart`'s own
    // `_maybeAutoLinkToSpec` group fixture shape.
    Uint8List vec(List<double> values) =>
        Float32List.fromList(values).buffer.asUint8List();

    final matchingSpec = Ticket(
      id: 'spec-match',
      ticketId: 'AIO-80',
      type: TicketType.spec,
      title: 'Spec',
      status: 'backlog',
      embedding: vec([1, 0, 0]),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final gapTarget = Ticket(
      id: 'gq-target-spec',
      ticketId: 'AIO-81',
      type: TicketType.story,
      title: 'Target story',
      status: 'backlog',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    setUp(() {
      when(() => repository.getAllTickets()).thenAnswer((_) async => []);
      when(
        () => repository.getTicketById(gapTarget.id),
      ).thenAnswer((_) async => gapTarget);
      when(
        () => linkRepository.getLinksByTypes(any()),
      ).thenAnswer((_) async => []);
      when(
        () => linkRepository.getLinksForTicket(any()),
      ).thenAnswer((_) async => []);
      when(
        () => linkRepository.createLink(
          sourceTicketId: any(named: 'sourceTicketId'),
          targetTicketId: gapTarget.id,
          linkType: TicketLinkType.relatesTo,
        ),
      ).thenAnswer((_) async {});
      when(
        () => repository.getAllTicketsByType([TicketType.spec]),
      ).thenAnswer((_) async => [matchingSpec]);
      when(
        () => embeddingProvider.embed(any()),
      ).thenAnswer((_) async => vec([1, 0, 0]));
      when(() => repository.createTicket(any())).thenAnswer((_) async {});
    });

    blocTest<TicketsCubit, TicketsState>(
      'auto + null-root graph links to the best-matching spec immediately',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.specAutoLink,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        when(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: matchingSpec.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        await cubit.createGapOrQuestion(
          TicketType.knownGap,
          title: 'A gap',
          targetTicketId: gapTarget.id,
        );
      },
      wait: const Duration(milliseconds: 20),
      verify: (_) {
        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>().single;
        verify(
          () => linkRepository.createLink(
            sourceTicketId: created.id,
            targetTicketId: matchingSpec.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'auto + graph resolving decline creates no link, not even a '
      'pending suggestion',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.specAutoLink,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        stubGraphOutcome(
          AutomationContext.specAutoLink,
          DecisionOutcome.decline,
        );
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        await cubit.createGapOrQuestion(
          TicketType.knownGap,
          title: 'A gap',
          targetTicketId: gapTarget.id,
        );
      },
      wait: const Duration(milliseconds: 20),
      verify: (cubit) async {
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: matchingSpec.id,
            linkType: TicketLinkType.relatesTo,
          ),
        );
        // Nothing pending either — confirming resolves to a no-op, not a
        // suddenly-created link.
        await cubit.confirmPendingSpecLinkSuggestion('bogus-source-id');
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: matchingSpec.id,
            linkType: TicketLinkType.relatesTo,
          ),
        );
      },
    );

    blocTest<TicketsCubit, TicketsState>(
      'auto + graph resolving gated records a pending suggestion instead '
      'of linking immediately, resolved the same way plain gated '
      'confidence already is',
      setUp: () {
        when(
          () => automationSettingsRepository.getConfidence(
            AutomationContext.specAutoLink,
          ),
        ).thenAnswer((_) async => AutomationConfidence.auto);
        stubGraphOutcome(AutomationContext.specAutoLink, DecisionOutcome.gated);
      },
      build: buildCubit,
      act: (cubit) async {
        await awaitDecisionGraphsLoaded();
        await cubit.createGapOrQuestion(
          TicketType.knownGap,
          title: 'A gap',
          targetTicketId: gapTarget.id,
        );
      },
      wait: const Duration(milliseconds: 20),
      verify: (cubit) async {
        final created = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>().single;
        verifyNever(
          () => linkRepository.createLink(
            sourceTicketId: created.id,
            targetTicketId: matchingSpec.id,
            linkType: TicketLinkType.relatesTo,
          ),
        );
        when(
          () => linkRepository.createLink(
            sourceTicketId: created.id,
            targetTicketId: matchingSpec.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).thenAnswer((_) async {});
        await cubit.confirmPendingSpecLinkSuggestion(created.id);
        verify(
          () => linkRepository.createLink(
            sourceTicketId: created.id,
            targetTicketId: matchingSpec.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
    );
  });
}
