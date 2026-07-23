import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/providers/data/repositories/shared_prefs_model_routing_repository.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsModelRoutingRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'getModelForPhase defaults to AgentModel.sonnet when nothing is '
      'persisted and no legacy key exists',
      () async {
        final repository = SharedPrefsModelRoutingRepository();

        expect(
          await repository.getModelForPhase(ModelPhase.frontier),
          AgentModel.sonnet,
        );
        expect(
          await repository.getModelForPhase(ModelPhase.capable),
          AgentModel.sonnet,
        );
        expect(
          await repository.getModelForPhase(ModelPhase.execution),
          AgentModel.sonnet,
        );
      },
    );

    test(
      'setModelForPhase then getModelForPhase round-trips the value, '
      'independently per phase',
      () async {
        final repository = SharedPrefsModelRoutingRepository();

        await repository.setModelForPhase(ModelPhase.frontier, AgentModel.opus);
        await repository.setModelForPhase(
          ModelPhase.execution,
          AgentModel.haiku,
        );

        expect(
          await repository.getModelForPhase(ModelPhase.frontier),
          AgentModel.opus,
        );
        expect(
          await repository.getModelForPhase(ModelPhase.capable),
          AgentModel.sonnet,
        );
        expect(
          await repository.getModelForPhase(ModelPhase.execution),
          AgentModel.haiku,
        );
      },
    );

    test(
      'getModelForPhase falls back to the legacy single-model key when a '
      "phase's own key isn't set, without writing anything",
      () async {
        SharedPreferences.setMockInitialValues({
          'agent_settings.selected_model_id': AgentModel.opus.id,
        });
        final repository = SharedPrefsModelRoutingRepository();

        expect(
          await repository.getModelForPhase(ModelPhase.frontier),
          AgentModel.opus,
        );
        expect(
          await repository.getModelForPhase(ModelPhase.capable),
          AgentModel.opus,
        );
        expect(
          await repository.getModelForPhase(ModelPhase.execution),
          AgentModel.opus,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('model_routing.frontier_model_id'), isNull);
      },
    );

    test(
      "a phase's own persisted value takes priority over the legacy key",
      () async {
        SharedPreferences.setMockInitialValues({
          'agent_settings.selected_model_id': AgentModel.opus.id,
        });
        final repository = SharedPrefsModelRoutingRepository();
        await repository.setModelForPhase(ModelPhase.frontier, AgentModel.haiku);

        expect(
          await repository.getModelForPhase(ModelPhase.frontier),
          AgentModel.haiku,
        );
      },
    );

    test(
      'getModelForPhase falls back to AgentModel.sonnet for an '
      'unrecognized stored id (e.g. a since-removed model)',
      () async {
        SharedPreferences.setMockInitialValues({
          'model_routing.capable_model_id': 'claude-some-retired-model',
        });
        final repository = SharedPrefsModelRoutingRepository();

        expect(
          await repository.getModelForPhase(ModelPhase.capable),
          AgentModel.sonnet,
        );
      },
    );
  });
}
