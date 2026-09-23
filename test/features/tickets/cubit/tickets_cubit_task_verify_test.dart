// test/features/tickets/cubit/tickets_cubit_task_verify_test.dart —
// TicketsCubit's per-Task semantic verify gate building blocks (AIO-3001,
// epic AIO-2999): the review prompt (_assembleTaskVerificationContext), its
// gate-line parser (_taskVerifyFailureReason), and its non-blocking
// suggestions parser (_taskVerifySuggestions, AIO-3003), exercised through
// their @visibleForTesting seams.
//
// Self-contained (own Mock classes and fixtures), mirroring
// tickets_cubit_decision_graph_test.dart's precedent for a cohesive slice of
// TicketsCubit coverage split out of the enormous tickets_cubit_test.dart.
// The gate's wiring into _runCodingExecution (AIO-3002) is covered there,
// next to the mechanical verification gate group, not here.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:aion/features/tickets/tickets.dart';

class MockTicketRepository extends Mock implements TicketRepository {}

void main() {
  late MockTicketRepository repository;

  final story = Ticket(
    id: 'story-1',
    ticketId: 'AIO-10',
    type: TicketType.story,
    title: 'Plumb the service',
    status: 'backlog',
    description:
        'STORY_SPEC_MARKER: wire the RepositoryProvider in app_router.',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final task = Ticket(
    id: 'task-1',
    ticketId: 'AIO-11',
    type: TicketType.task,
    title: 'Provide DecisionLogService project-scoped',
    status: 'inProgress',
    description: 'TASK_DESCRIPTION_MARKER',
    parentId: story.id,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  const diff =
      'diff --git a/lib/a.dart b/lib/a.dart\n'
      '--- a/lib/a.dart\n'
      '+++ b/lib/a.dart\n'
      '@@ -1 +1 @@\n'
      '-old\n'
      '+new\n';

  setUp(() {
    repository = MockTicketRepository();
    when(() => repository.getTicketById(any())).thenAnswer((invocation) async {
      final id = invocation.positionalArguments[0] as String;
      return id == story.id ? story : null;
    });
  });

  group('_assembleTaskVerificationContext (AIO-3001)', () {
    test('frames an independent review of the diff against the real spec '
        '— title, description, parent plan — with both required checks '
        'and the terminal gate-line instruction', () async {
      final prompt = await TicketsCubit(
        repository,
      ).debugAssembleTaskVerificationContext(task, diff);

      expect(
        prompt,
        allOf([
          contains('independent reviewer'),
          contains('You did not write this change'),
          contains('# ${task.title}'),
          contains('TASK_DESCRIPTION_MARKER'),
          contains("## Parent story's full plan"),
          contains('STORY_SPEC_MARKER'),
          contains('## Diff'),
          contains('```diff\n$diff```'),
          contains('## Required checks'),
          contains('Scope'),
          contains('Tests'),
          contains('## Issues Found'),
          contains('TASK VERIFY GATE: APPROVED'),
          contains('TASK VERIFY GATE: NEEDS FIXES'),
        ]),
      );
      expect(prompt, isNot(contains('diff truncated')));
      // The spec comes before the evidence, which comes before the checks.
      expect(
        prompt.indexOf('STORY_SPEC_MARKER'),
        lessThan(prompt.indexOf('## Diff')),
      );
      expect(
        prompt.indexOf('## Diff'),
        lessThan(prompt.indexOf('## Required checks')),
      );
    });

    test('omits the plan section for a Task with no parent', () async {
      final orphan = Ticket(
        id: 'task-2',
        ticketId: 'AIO-12',
        type: TicketType.task,
        title: 'Standalone task',
        status: 'inProgress',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final prompt = await TicketsCubit(
        repository,
      ).debugAssembleTaskVerificationContext(orphan, diff);

      expect(prompt, isNot(contains('## Parent')));
      expect(prompt, isNot(contains('## Approved plan')));
      expect(prompt, contains('# Standalone task'));
    });

    test('truncates a diff over 60,000 characters, says so explicitly, and '
        'lists every changed file — including ones past the cut — so the '
        'reviewer can read them instead of failing by default', () async {
      final hugeDiff =
          'diff --git a/lib/big.dart b/lib/big.dart\n'
          '+${'x' * 70000}\n'
          'diff --git a/lib/hidden.dart b/lib/hidden.dart\n'
          '+TAIL_MARKER\n';

      final prompt = await TicketsCubit(
        repository,
      ).debugAssembleTaskVerificationContext(task, hugeDiff);

      expect(
        prompt,
        contains(
          '[diff truncated — 60000 of ${hugeDiff.length} characters shown]',
        ),
      );
      expect(prompt, contains('read its current contents in the worktree'));
      expect(prompt, contains('- lib/big.dart'));
      expect(prompt, contains('- lib/hidden.dart'));
      expect(prompt, isNot(contains('TAIL_MARKER')));
    });

    test('limits blocking to the two required checks and routes every other '
        'improvement idea to a separate, non-blocking Suggestions section '
        '(AIO-3003)', () async {
      final prompt = await TicketsCubit(
        repository,
      ).debugAssembleTaskVerificationContext(task, diff);

      expect(
        prompt,
        allOf([
          contains(
            'Only failures of the two required checks above are '
            'blocking',
          ),
          contains('must NOT go under Issues Found'),
          contains('"## Suggestions" heading'),
          contains('even if you listed suggestions'),
        ]),
      );
      // The terminal-line instruction still comes last.
      expect(
        prompt.indexOf('## Suggestions'),
        lessThan(prompt.lastIndexOf('TASK VERIFY GATE: APPROVED')),
      );
    });

    test('an untruncated diff gets no changed-file list', () async {
      final prompt = await TicketsCubit(
        repository,
      ).debugAssembleTaskVerificationContext(task, diff);

      expect(prompt, isNot(contains('- lib/a.dart')));
    });

    test(
      'fences the diff with more backticks than any run inside it, so a '
      "changed Markdown file's own code fences can't end the block early",
      () async {
        const markdownDiff =
            'diff --git a/README.md b/README.md\n'
            '+```dart\n'
            '+void main() {}\n'
            '+```\n'
            '+````\n';

        final prompt = await TicketsCubit(
          repository,
        ).debugAssembleTaskVerificationContext(task, markdownDiff);

        expect(prompt, contains('`````diff\n$markdownDiff`````'));
      },
    );
  });

  group('_taskVerifyFailureReason (AIO-3001)', () {
    late TicketsCubit cubit;

    setUp(() => cubit = TicketsCubit(repository));

    test('a null reply fails closed with a generic reason', () {
      expect(
        cubit.debugTaskVerifyFailureReason(null),
        'The task-verify review turn produced no reply.',
      );
    });

    test('an explicit APPROVED line passes', () {
      expect(
        cubit.debugTaskVerifyFailureReason(
          'Scope matches, tests added.\n\nTASK VERIFY GATE: APPROVED',
        ),
        isNull,
      );
    });

    test('NEEDS FIXES returns only the Issues Found body — not the heading '
        'or the terminal gate line', () {
      const reply =
          'Reviewed the diff.\n\n'
          '## Issues Found\n'
          '- Missing RepositoryProvider wiring in app_router.dart\n'
          '- No new tests for the recording call sites\n\n'
          'TASK VERIFY GATE: NEEDS FIXES';

      expect(
        cubit.debugTaskVerifyFailureReason(reply),
        '- Missing RepositoryProvider wiring in app_router.dart\n'
        '- No new tests for the recording call sites',
      );
    });

    test('the Issues Found body stops at the next heading', () {
      const reply =
          '## Issues Found\n'
          '- Scope creep: implements AIO-2990 call sites\n'
          '## Notes\n'
          'Otherwise tidy.\n'
          'TASK VERIFY GATE: NEEDS FIXES';

      expect(
        cubit.debugTaskVerifyFailureReason(reply),
        '- Scope creep: implements AIO-2990 call sites',
      );
    });

    test('NEEDS FIXES without an Issues Found block returns the reply '
        'itself', () {
      const reply = 'Tests are missing.\nTASK VERIFY GATE: NEEDS FIXES';

      expect(cubit.debugTaskVerifyFailureReason(reply), reply);
    });

    test('a reply with no gate line at all fails closed, truncated to '
        '1000 characters', () {
      final reply = 'y' * 1500;

      expect(cubit.debugTaskVerifyFailureReason(reply), '${'y' * 1000}...');
    });

    test('quoting the APPROVED line mid-reply while ending on NEEDS FIXES '
        'does not pass', () {
      const reply =
          "I can't give TASK VERIFY GATE: APPROVED yet.\n\n"
          '## Issues Found\n'
          '- Missing RepositoryProvider wiring\n\n'
          'TASK VERIFY GATE: NEEDS FIXES';

      expect(
        cubit.debugTaskVerifyFailureReason(reply),
        '- Missing RepositoryProvider wiring',
      );
    });

    test('APPROVED followed by more text is not a terminal verdict and does '
        'not pass', () {
      const reply =
          'TASK VERIFY GATE: APPROVED\n\nActually, tests are missing.';

      expect(cubit.debugTaskVerifyFailureReason(reply), reply);
    });

    test('a terminal APPROVED line wrapped in Markdown bold or backticks, '
        'with trailing whitespace, still passes', () {
      expect(
        cubit.debugTaskVerifyFailureReason(
          'All good.\n\n**TASK VERIFY GATE: APPROVED**\n\n',
        ),
        isNull,
      );
      expect(
        cubit.debugTaskVerifyFailureReason(
          'All good.\n`TASK VERIFY GATE: APPROVED`',
        ),
        isNull,
      );
    });

    test('a Windows-style CRLF reply ending in APPROVED still passes', () {
      expect(
        cubit.debugTaskVerifyFailureReason(
          'All good.\r\nTASK VERIFY GATE: APPROVED\r\n',
        ),
        isNull,
      );
    });

    test('Issues Found stops at a following Suggestions section, so '
        'non-blocking ideas never reach the implementer (AIO-3003)', () {
      const reply =
          '## Issues Found\n'
          '- No tests for the new parser\n\n'
          '## Suggestions\n'
          '- Consider renaming _foo to _bar\n\n'
          'TASK VERIFY GATE: NEEDS FIXES';

      expect(
        cubit.debugTaskVerifyFailureReason(reply),
        '- No tests for the new parser',
      );
    });

    test('NEEDS FIXES without Issues Found falls back to the reply minus its '
        'Suggestions section (AIO-3003)', () {
      const reply =
          'Tests are missing for the new branch.\n\n'
          '## Suggestions\n'
          '- SUGGESTION_MARKER rename the helper\n\n'
          'TASK VERIFY GATE: NEEDS FIXES';

      final reason = cubit.debugTaskVerifyFailureReason(reply)!;
      expect(reason, contains('Tests are missing for the new branch.'));
      expect(reason, contains('TASK VERIFY GATE: NEEDS FIXES'));
      expect(reason, isNot(contains('SUGGESTION_MARKER')));
      expect(reason, isNot(contains('## Suggestions')));
    });

    test('an empty Issues Found block falls back to the reply', () {
      const reply = '## Issues Found\n\nTASK VERIFY GATE: NEEDS FIXES';

      expect(cubit.debugTaskVerifyFailureReason(reply), reply);
    });
  });

  group('_taskVerifySuggestions (AIO-3003)', () {
    late TicketsCubit cubit;

    setUp(() => cubit = TicketsCubit(repository));

    test('a null reply has no suggestions', () {
      expect(cubit.debugTaskVerifySuggestions(null), isNull);
    });

    test('returns the Suggestions body, stopping before the terminal gate '
        'line', () {
      const reply =
          'Scope and tests look right.\n\n'
          '## Suggestions\n'
          '- Extract the retry-confidence switch into a helper\n'
          '- The dartdoc on _foo is stale\n\n'
          'TASK VERIFY GATE: APPROVED';

      expect(
        cubit.debugTaskVerifySuggestions(reply),
        '- Extract the retry-confidence switch into a helper\n'
        '- The dartdoc on _foo is stale',
      );
    });

    test('stops at the next heading', () {
      const reply =
          '## Suggestions\n'
          '- Rename x\n'
          '## Notes\n'
          'Nothing else.\n'
          'TASK VERIFY GATE: APPROVED';

      expect(cubit.debugTaskVerifySuggestions(reply), '- Rename x');
    });

    test('a reply without a Suggestions section has none', () {
      expect(
        cubit.debugTaskVerifySuggestions(
          'All good.\nTASK VERIFY GATE: APPROVED',
        ),
        isNull,
      );
    });

    test('an empty Suggestions section has none', () {
      expect(
        cubit.debugTaskVerifySuggestions(
          '## Suggestions\n\nTASK VERIFY GATE: APPROVED',
        ),
        isNull,
      );
    });
  });
}
