// Tests for PlanCheckResult / PlanCheckPrompt (AIO-3063) — the Frontier plan check's prompt, fail-closed reply parser and lead report.

import 'package:aion/features/tickets/presentation/cubit/escalation_ladder.dart';
import 'package:aion/features/tickets/presentation/cubit/plan_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlanCheckResult.parse', () {
    test('OK verdict with suspected causes', () {
      final r = PlanCheckResult.parse(
        '## Suspected Causes\n- The flaky router test\n\nPLAN CHECK: OK',
      );
      expect(r.verdict, PlanCheckVerdict.ok);
      expect(r.suspectedCauses, '- The flaky router test');
      expect(r.summary, '- The flaky router test');
    });

    test('TASK REWRITE returns the whole revised description, headings '
        'included', () {
      final r = PlanCheckResult.parse(
        '## Suspected Causes\nThe task names a missing file.\n\n'
        '## Revised Task Description\n'
        'Do the thing in lib/real.dart.\n\n'
        '## Notes\nKeep it small.\n\n'
        '**PLAN CHECK: TASK REWRITE**',
      );
      expect(r.verdict, PlanCheckVerdict.taskRewrite);
      expect(
        r.revisedDescription,
        'Do the thing in lib/real.dart.\n\n## Notes\nKeep it small.',
      );
      expect(r.suspectedCauses, 'The task names a missing file.');
    });

    test('STORY CHANGE returns the change request', () {
      final r = PlanCheckResult.parse(
        '## Story Change Request\n'
        '- was: edit foo.dart -> now: edit bar.dart, because foo.dart is gone\n'
        '\nPLAN CHECK: STORY CHANGE',
      );
      expect(r.verdict, PlanCheckVerdict.storyChange);
      expect(r.storyChangeRequest, contains('edit bar.dart'));
      expect(r.revisedDescription, isNull);
    });

    test('fails closed to OK: no reply, no verdict line, unknown verdict', () {
      expect(PlanCheckResult.parse(null).verdict, PlanCheckVerdict.ok);
      expect(PlanCheckResult.parse('').verdict, PlanCheckVerdict.ok);
      expect(
        PlanCheckResult.parse('## Revised Task Description\nx\n').verdict,
        PlanCheckVerdict.ok,
      );
      expect(
        PlanCheckResult.parse('PLAN CHECK: REWRITE EVERYTHING').verdict,
        PlanCheckVerdict.ok,
      );
    });

    test('fails closed to OK: rewrite or change verdict without its '
        'section, or with an empty one', () {
      expect(
        PlanCheckResult.parse('PLAN CHECK: TASK REWRITE').verdict,
        PlanCheckVerdict.ok,
      );
      expect(
        PlanCheckResult.parse(
          '## Revised Task Description\n\nPLAN CHECK: TASK REWRITE',
        ).verdict,
        PlanCheckVerdict.ok,
      );
      expect(
        PlanCheckResult.parse('PLAN CHECK: STORY CHANGE').verdict,
        PlanCheckVerdict.ok,
      );
    });

    test('a verdict quoted mid-reply does not count, only the last line', () {
      final r = PlanCheckResult.parse(
        'I would normally say PLAN CHECK: TASK REWRITE but no.\n'
        'PLAN CHECK: OK',
      );
      expect(r.verdict, PlanCheckVerdict.ok);
    });

    test('summary falls back to the truncated raw reply', () {
      final r = PlanCheckResult.parse('${'y' * 1500}\nPLAN CHECK: OK');
      expect(r.summary.length, lessThan(1100));
      expect(r.summary, endsWith('...'));
      expect(
        PlanCheckResult.parse(null).summary,
        'The plan check produced no reply.',
      );
    });
  });

  group('PlanCheckPrompt', () {
    const failures = [
      LadderFailure(ExecutionRung.execution, 'tests broke'),
      LadderFailure(ExecutionRung.capable, 'still broken'),
    ];

    test(
      'includes the plan under test, the failure trail and the protocol',
      () {
        final prompt = PlanCheckPrompt.build(
          title: 'Wire the thing',
          description: 'TASK_DESC',
          planSection: '## Parent story\'s full plan\n\nSTORY_PLAN',
          failures: failures,
        );
        expect(
          prompt,
          allOf([
            contains('# Wire the thing'),
            contains('TASK_DESC'),
            contains('STORY_PLAN'),
            contains('1. [execution model] tests broke'),
            contains('2. [capable model] still broken'),
            contains('you must NOT edit it'),
            contains('PLAN CHECK: TASK REWRITE'),
            contains('When unsure, answer OK'),
          ]),
        );
      },
    );

    test('omits the plan section for an orphan Task', () {
      final prompt = PlanCheckPrompt.build(
        title: 'Solo',
        description: null,
        planSection: null,
        failures: failures,
      );
      expect(prompt, isNot(contains('STORY_PLAN')));
      expect(prompt, contains('# Solo'));
    });
  });

  group('PlanCheckPrompt.leadReport', () {
    const trail = [
      LadderFailure(ExecutionRung.execution, 'tests broke'),
      LadderFailure(ExecutionRung.capable, 'still broken'),
    ];

    test('lists each rung\'s failure and the Frontier suspicions', () {
      final report = PlanCheckPrompt.leadReport(
        trail: trail,
        check: PlanCheckResult.parse(
          '## Suspected Causes\n- flaky test\n\nPLAN CHECK: OK',
        ),
        rewriteApplied: false,
      );
      expect(
        report,
        allOf([
          contains('- execution model failed self-verify: tests broke'),
          contains('- capable model failed self-verify: still broken'),
          contains('no provable plan defect'),
          contains('- flaky test'),
        ]),
      );
      expect(report, isNot(contains('rewrote the Task description')));
    });

    test('mentions an applied rewrite and a plan check that could not run', () {
      final report = PlanCheckPrompt.leadReport(
        trail: trail,
        check: null,
        rewriteApplied: true,
      );
      expect(report, contains('rewrote the Task description'));
      expect(report, contains('It could not run.'));
    });
  });
}
