import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/core/contracts/agent_model_client.dart';
import 'package:aion/core/git/git_repository_client.dart';
import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

class MockAgentModelClient extends Mock implements AgentModelClient {}

class MockCommentRepository extends Mock implements CommentRepository {}

class MockGitRepositoryClient extends Mock implements GitRepositoryClient {}

class MockTicketLinkRepository extends Mock implements TicketLinkRepository {}

/// Makes [repository]'s `createTicket`/`getTicketById` behave like a real
/// (in-memory) store, keyed on each [Ticket]'s own `id` — needed since
/// `runCodebaseSummarization` generates its own ticket ids internally
/// (`Uuid().v4()`) and then immediately reads them back via
/// `getTicketById`.
void stubStatefulTickets(MockTicketRepository repository) {
  final store = <String, Ticket>{};
  when(() => repository.createTicket(any())).thenAnswer((invocation) async {
    final ticket = invocation.positionalArguments[0] as Ticket;
    store[ticket.id] = ticket;
  });
  when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
    final id = invocation.positionalArguments[0] as String;
    return store[id];
  });
}

/// Makes [commentRepository]'s `addComment`/`getCommentsForTicket` behave
/// like a real (in-memory) per-ticket comment log — mirrors
/// `tickets_cubit_test.dart`'s `stubStatefulComments`, generalized to any
/// ticket id since the analysis chat's id is generated internally.
void stubStatefulComments(MockCommentRepository commentRepository) {
  final comments = <TicketComment>[];
  when(
    () => commentRepository.getCommentsForTicket(any()),
  ).thenAnswer((invocation) async {
    final ticketId = invocation.positionalArguments[0] as String;
    return comments.where((c) => c.ticketId == ticketId).toList();
  });
  when(() => commentRepository.addComment(any())).thenAnswer((
    invocation,
  ) async {
    comments.add(invocation.positionalArguments[0] as TicketComment);
  });
}

void main() {
  late MockTicketRepository repository;
  late MockAgentModelClient agentClient;
  late MockCommentRepository commentRepository;
  late MockGitRepositoryClient gitClient;
  late MockTicketLinkRepository linkRepository;

  setUpAll(() {
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
    registerFallbackValue(const AgentRequest(prompt: '', model: ''));
    registerFallbackValue(
      TicketComment(
        id: '',
        ticketId: '',
        content: '',
        authorType: CommentAuthorType.system,
        createdAt: DateTime(2026),
      ),
    );
    registerFallbackValue(TicketLinkType.relatesTo);
  });

  setUp(() {
    repository = MockTicketRepository();
    agentClient = MockAgentModelClient();
    commentRepository = MockCommentRepository();
    gitClient = MockGitRepositoryClient();
    linkRepository = MockTicketLinkRepository();
    stubStatefulTickets(repository);
    stubStatefulComments(commentRepository);
    when(
      () => linkRepository.createLink(
        sourceTicketId: any(named: 'sourceTicketId'),
        targetTicketId: any(named: 'targetTicketId'),
        linkType: any(named: 'linkType'),
      ),
    ).thenAnswer((_) async {});
  });

  group('runCodebaseSummarization — shallow', () {
    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      agentClient: agentClient,
      linkRepository: linkRepository,
      projectRootPath: '/fake/project/root',
      projectName: 'Fake Project',
    );

    test(
      'creates a run-record signal ticket and one signal ticket per '
      'finding, each prefixed with the shallow-scan flag and linked back '
      'to the run — no worktree/chat calls',
      () async {
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent(
              'FINDING: Uses drift for persistence\n'
              'A local SQLite database via the drift package.\n'
              'FINDING: No CI configuration found\n'
              'No .github/workflows directory present.\n'
              'SUMMARY: DONE',
            ),
            AgentDoneEvent(),
          ]),
        );

        final cubit = buildCubit();
        final statuses = <CodebaseAnalysisStatus>[];
        final sub = cubit.codebaseAnalysisStatus.listen(statuses.add);

        await cubit.runCodebaseSummarization(depth: SummarizationDepth.shallow);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await cubit.close();

        expect(statuses.last, isA<CodebaseAnalysisDone>());
        expect((statuses.last as CodebaseAnalysisDone).count, 2);

        verifyNever(() => gitClient.createWorktree(any(), any(), any()));

        final createdTickets = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>();
        // 1 run-record + 2 findings.
        expect(createdTickets.length, 3);
        expect(
          createdTickets.every((t) => t.type == TicketType.signal),
          isTrue,
        );
        final runRecord = createdTickets.firstWhere(
          (t) => t.title == 'Codebase Analysis — Fake Project',
        );
        expect(runRecord.parentId, isNull);

        final findings = createdTickets.where((t) => t.id != runRecord.id);
        expect(findings.length, 2);
        for (final finding in findings) {
          expect(
            finding.description,
            startsWith('[Shallow scan — structural only, may be incomplete]'),
          );
        }

        verify(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: runRecord.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(2);
      },
    );

    test(
      'emits CodebaseAnalysisFailed and creates no findings when the model '
      'run reports an error',
      () async {
        when(
          () => agentClient.run(any()),
        ).thenAnswer((_) async => Stream.fromIterable(const [
          AgentErrorEvent('provider unavailable'),
        ]));

        final cubit = buildCubit();
        final statuses = <CodebaseAnalysisStatus>[];
        final sub = cubit.codebaseAnalysisStatus.listen(statuses.add);

        await cubit.runCodebaseSummarization(depth: SummarizationDepth.shallow);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await cubit.close();

        expect(statuses.last, isA<CodebaseAnalysisFailed>());
        // Only the run-record ticket was created — no findings, since the
        // model run failed before any could be parsed.
        verify(() => repository.createTicket(any())).called(1);
      },
    );

    test(
      'emits CodebaseAnalysisFailed immediately, creating no tickets, when '
      'constructed without a project root path',
      () async {
        final cubit = TicketsCubit(repository, agentClient: agentClient);
        final statuses = <CodebaseAnalysisStatus>[];
        final sub = cubit.codebaseAnalysisStatus.listen(statuses.add);

        await cubit.runCodebaseSummarization(depth: SummarizationDepth.shallow);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await cubit.close();

        expect(statuses.last, isA<CodebaseAnalysisFailed>());
        verifyNever(() => repository.createTicket(any()));
      },
    );
  });

  group('runCodebaseSummarization — full', () {
    TicketsCubit buildCubit() => TicketsCubit(
      repository,
      agentClient: agentClient,
      commentRepository: commentRepository,
      gitClient: gitClient,
      linkRepository: linkRepository,
      projectRootPath: '/fake/project/root',
      projectName: 'Fake Project',
    );

    setUp(() {
      when(
        () => gitClient.createWorktree(any(), any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => gitClient.removeWorktree(any(), any()),
      ).thenAnswer((_) async {});
    });

    test(
      'creates and removes an isolated worktree, spawns a chat under the '
      'run-record ticket, streams status, and links findings back to the '
      'run',
      () async {
        when(() => agentClient.run(any())).thenAnswer(
          (_) async => Stream.fromIterable(const [
            AgentTextEvent(
              'FINDING: Missing test coverage for auth\n'
              'No tests found under test/features/auth.\n'
              'SUMMARY: DONE',
            ),
            AgentDoneEvent(),
          ]),
        );

        final cubit = buildCubit();
        final statuses = <CodebaseAnalysisStatus>[];
        final sub = cubit.codebaseAnalysisStatus.listen(statuses.add);

        await cubit.runCodebaseSummarization(depth: SummarizationDepth.full);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await cubit.close();

        expect(statuses.any((s) => s is CodebaseAnalysisRunning), isTrue);
        expect(statuses.last, isA<CodebaseAnalysisDone>());
        expect((statuses.last as CodebaseAnalysisDone).count, 1);

        verify(
          () => gitClient.createWorktree(any(), any(), any()),
        ).called(1);
        verify(() => gitClient.removeWorktree(any(), any())).called(1);

        final createdTickets = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>();
        // 1 run-record signal + 1 chat child + 1 finding signal.
        expect(createdTickets.length, 3);
        final chat = createdTickets.singleWhere(
          (t) => t.type == TicketType.chat,
        );
        final runRecord = createdTickets.singleWhere(
          (t) =>
              t.title == 'Codebase Analysis — Fake Project' &&
              t.type == TicketType.signal,
        );
        expect(chat.parentId, runRecord.id);

        verify(
          () => linkRepository.createLink(
            sourceTicketId: any(named: 'sourceTicketId'),
            targetTicketId: runRecord.id,
            linkType: TicketLinkType.relatesTo,
          ),
        ).called(1);
      },
    );

    test(
      'removes the worktree even when the model turn hard-fails, emitting '
      'CodebaseAnalysisFailed and creating no findings',
      () async {
        when(() => agentClient.run(any())).thenThrow(Exception('boom'));

        final cubit = buildCubit();
        final statuses = <CodebaseAnalysisStatus>[];
        final sub = cubit.codebaseAnalysisStatus.listen(statuses.add);

        await cubit.runCodebaseSummarization(depth: SummarizationDepth.full);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await cubit.close();

        expect(statuses.last, isA<CodebaseAnalysisFailed>());
        verify(() => gitClient.removeWorktree(any(), any())).called(1);

        final createdTickets = verify(
          () => repository.createTicket(captureAny()),
        ).captured.cast<Ticket>();
        // Run-record + chat only — no findings, since the turn never
        // completed.
        expect(createdTickets.length, 2);
        expect(
          createdTickets.where((t) => t.type == TicketType.signal).length,
          1,
        );
      },
    );

    test(
      'removes the worktree even when createWorktree itself throws',
      () async {
        when(
          () => gitClient.createWorktree(any(), any(), any()),
        ).thenThrow(Exception('worktree create failed'));

        final cubit = buildCubit();
        final statuses = <CodebaseAnalysisStatus>[];
        final sub = cubit.codebaseAnalysisStatus.listen(statuses.add);

        await cubit.runCodebaseSummarization(depth: SummarizationDepth.full);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await cubit.close();

        expect(statuses.last, isA<CodebaseAnalysisFailed>());
        verify(() => gitClient.removeWorktree(any(), any())).called(1);
      },
    );
  });
}
