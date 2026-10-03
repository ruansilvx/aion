// Tests for EscalationLadder (AIO-3059) — the coding-execution escalation state machine.

import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/tickets/presentation/cubit/escalation_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EscalationLadder', () {
    test('starts on Execution with the execution phase', () {
      final ladder = EscalationLadder(capableUsable: true);
      expect(ladder.rung, ExecutionRung.execution);
      expect(ladder.implementPhase, ModelPhase.execution);
      expect(ladder.stateMarker, isNull);
    });

    test('retries once, then escalates to Capable on the second failure', () {
      final ladder = EscalationLadder(capableUsable: true);
      expect(ladder.onSelfVerifyFailed('a'), LadderStep.retrySameRung);
      expect(ladder.rung, ExecutionRung.execution);
      expect(ladder.onSelfVerifyFailed('b'), LadderStep.escalate);
      expect(ladder.rung, ExecutionRung.capable);
      expect(ladder.implementPhase, ModelPhase.capable);
      expect(ladder.failuresOnRung, 0);
    });

    test('Capable gets its own fresh budget, then runs the plan check', () {
      final ladder = EscalationLadder(capableUsable: true);
      ladder
        ..onSelfVerifyFailed('a')
        ..onSelfVerifyFailed('b');
      expect(ladder.onSelfVerifyFailed('c'), LadderStep.retrySameRung);
      expect(ladder.onSelfVerifyFailed('d'), LadderStep.runPlanCheck);
      expect(ladder.rung, ExecutionRung.planCheck);
      expect(ladder.trail.map((f) => f.reason), ['a', 'b', 'c', 'd']);
      expect(ladder.trail[2].rung, ExecutionRung.capable);
    });

    test('skips Capable when it is not usable', () {
      final ladder = EscalationLadder(capableUsable: false);
      expect(ladder.onSelfVerifyFailed('a'), LadderStep.retrySameRung);
      expect(ladder.onSelfVerifyFailed('b'), LadderStep.runPlanCheck);
      expect(ladder.rung, ExecutionRung.planCheck);
    });

    test('without a plan check the spent ladder gives up in place', () {
      final ladder = EscalationLadder(
        capableUsable: false,
        planCheckAvailable: false,
      );
      ladder.onSelfVerifyFailed('a');
      expect(ladder.onSelfVerifyFailed('b'), LadderStep.giveUp);
      expect(ladder.rung, ExecutionRung.execution);
      expect(ladder.implementPhase, ModelPhase.execution);
      expect(ladder.onSelfVerifyFailed('c'), LadderStep.giveUp);
    });

    test('onPlanRewritten moves to a single final Execution attempt', () {
      final ladder = EscalationLadder(capableUsable: false)
        ..onSelfVerifyFailed('a')
        ..onSelfVerifyFailed('b')
        ..onPlanRewritten();
      expect(ladder.rung, ExecutionRung.finalExecution);
      expect(ladder.implementPhase, ModelPhase.execution);
      expect(ladder.onSelfVerifyFailed('c'), LadderStep.giveUp);
    });

    test('a failure reported while on the plan check gives up', () {
      final ladder = EscalationLadder(capableUsable: false)
        ..onSelfVerifyFailed('a')
        ..onSelfVerifyFailed('b');
      expect(ladder.onSelfVerifyFailed('c'), LadderStep.giveUp);
    });

    test('a custom threshold of 3 needs three failures per rung', () {
      final ladder = EscalationLadder(capableUsable: true, threshold: 3);
      expect(ladder.onSelfVerifyFailed('a'), LadderStep.retrySameRung);
      expect(ladder.onSelfVerifyFailed('b'), LadderStep.retrySameRung);
      expect(ladder.onSelfVerifyFailed('c'), LadderStep.escalate);
    });
  });

  group('EscalationLadder state marker', () {
    test('is null before any failure and after the implement rungs', () {
      final ladder = EscalationLadder(capableUsable: false);
      expect(ladder.stateMarker, isNull);
      ladder
        ..onSelfVerifyFailed('a')
        ..onSelfVerifyFailed('b');
      expect(ladder.stateMarker, isNull);
    });

    test('round-trips a mid-rung failure count', () {
      final ladder = EscalationLadder(capableUsable: true)
        ..onSelfVerifyFailed('a');
      final marker = ladder.stateMarker!;
      expect(marker, '[ladder: rung=execution failures=1]');
      final resumed = EscalationLadder.resume(
        capableUsable: true,
        lastComment: 'Execution failed verification:\n\nboom\n\n$marker',
      );
      expect(resumed.rung, ExecutionRung.execution);
      expect(resumed.failuresOnRung, 1);
      expect(resumed.onSelfVerifyFailed('b'), LadderStep.escalate);
    });

    test('round-trips an escalated rung with a zero count', () {
      final ladder = EscalationLadder(capableUsable: true)
        ..onSelfVerifyFailed('a')
        ..onSelfVerifyFailed('b');
      final resumed = EscalationLadder.resume(
        capableUsable: true,
        lastComment: 'x\n\n${ladder.stateMarker}',
      );
      expect(resumed.rung, ExecutionRung.capable);
      expect(resumed.failuresOnRung, 0);
    });

    test('stripMarker removes only the trailing marker line', () {
      expect(
        EscalationLadder.stripMarker(
          'Execution failed verification:\n\nboom\n\n'
          '[ladder: rung=capable failures=0]',
        ),
        'Execution failed verification:\n\nboom',
      );
      expect(EscalationLadder.stripMarker('plain'), 'plain');
    });

    test('resume without a marker starts fresh on Execution', () {
      expect(
        EscalationLadder.resume(
          capableUsable: true,
          lastComment: 'Escalation exhausted: nothing to resume',
        ).rung,
        ExecutionRung.execution,
      );
      expect(
        EscalationLadder.resume(capableUsable: true).rung,
        ExecutionRung.execution,
      );
    });

    test('resume ignores a marker that is not the last line', () {
      expect(
        EscalationLadder.resume(
          capableUsable: true,
          lastComment: '[ladder: rung=capable failures=0]\n\nlater text',
        ).rung,
        ExecutionRung.execution,
      );
    });

    test('a restored Capable rung falls back when Capable is now unusable', () {
      final resumed = EscalationLadder.resume(
        capableUsable: false,
        lastComment: 'x\n\n[ladder: rung=capable failures=1]',
      );
      expect(resumed.rung, ExecutionRung.execution);
      expect(resumed.failuresOnRung, 0);
    });
  });
}
