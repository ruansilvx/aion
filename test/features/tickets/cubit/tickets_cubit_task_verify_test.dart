// test/features/tickets/cubit/tickets_cubit_task_verify_test.dart —
// TicketsCubit's per-Task semantic verify gate building blocks (AIO-3001,
// epic AIO-2999): the review prompt (_assembleTaskVerificationContext) and
// its gate-line parser (_taskVerifyFailureReason), exercised through their
// @visibleForTesting seams.
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

    test('truncates a diff over 60,000 characters and says so explicitly, '
        'telling the reviewer not to assume the hidden part is fine', () async {
      final hugeDiff = '+${'x' * 70000}\nTAIL_MARKER\n';

      final prompt = await TicketsCubit(
        repository,
      ).debugAssembleTaskVerificationContext(task, hugeDiff);

      expect(
        prompt,
        contains(
          '[diff truncated — 60000 of ${hugeDiff.length} characters shown]',
        ),
      );
      expect(prompt, contains('counts as unverified'));
      expect(prompt, isNot(contains('TAIL_MARKER')));
    });
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

    test('an empty Issues Found block falls back to the reply', () {
      const reply = '## Issues Found\n\nTASK VERIFY GATE: NEEDS FIXES';

      expect(cubit.debugTaskVerifyFailureReason(reply), reply);
    });
  });
}
