import 'package:flutter_test/flutter_test.dart';

import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/tickets/domain/enums/sdd_stage.dart';

void main() {
  group('SddStageModelPhase.modelPhase', () {
    test('exploring, proposed, and verifying resolve to frontier', () {
      expect(SddStage.exploring.modelPhase, ModelPhase.frontier);
      expect(SddStage.proposed.modelPhase, ModelPhase.frontier);
      expect(SddStage.verifying.modelPhase, ModelPhase.frontier);
    });

    test('designBrief, designSync, and archived resolve to capable', () {
      expect(SddStage.designBrief.modelPhase, ModelPhase.capable);
      expect(SddStage.designSync.modelPhase, ModelPhase.capable);
      expect(SddStage.archived.modelPhase, ModelPhase.capable);
    });

    test('every SddStage value maps to a phase (no missing switch case)', () {
      for (final stage in SddStage.values) {
        expect(stage.modelPhase, isA<ModelPhase>());
      }
    });
  });
}
