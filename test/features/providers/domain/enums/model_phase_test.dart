import 'package:flutter_test/flutter_test.dart';

import 'package:aion/core/contracts/tool_access_tier.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';

void main() {
  group('ModelPhaseToolAccess.requiredToolAccessTier', () {
    test('frontier and capable require no tools', () {
      expect(
        ModelPhase.frontier.requiredToolAccessTier,
        ToolAccessTier.noTools,
      );
      expect(ModelPhase.capable.requiredToolAccessTier, ToolAccessTier.noTools);
    });

    test('execution and taskVerify require full tool access', () {
      expect(ModelPhase.execution.requiredToolAccessTier, ToolAccessTier.full);
      expect(ModelPhase.taskVerify.requiredToolAccessTier, ToolAccessTier.full);
    });

    test('every ModelPhase value maps to a tier (no missing switch case)', () {
      // Guards the phase list itself: a new phase must be deliberately
      // added here, alongside its tier mapping and Settings row.
      expect(ModelPhase.values, hasLength(4));
      for (final phase in ModelPhase.values) {
        expect(phase.requiredToolAccessTier, isA<ToolAccessTier>());
      }
    });
  });
}
