import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/agent/agent_bridge_locator.dart';
import 'package:aion/core/agent/claude_agent_sdk_provider.dart';
import 'package:aion/core/agent/static_provider_registry.dart';
import 'package:aion/features/providers/data/repositories/shared_prefs_model_routing_repository.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = ClaudeAgentSdkProvider(AgentBridgeLocator());
  final registry = StaticProviderRegistry([provider]);
  final opus = provider.availableModels[0];
  final sonnet = provider.availableModels[1];
  final haiku = provider.availableModels[2];

  group('SharedPrefsModelRoutingRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'getModelForPhase defaults to the first registered model when '
      'nothing is persisted and no legacy key exists',
      () async {
        final repository = SharedPrefsModelRoutingRepository(registry);

        expect(await repository.getModelForPhase(ModelPhase.frontier), opus);
        expect(await repository.getModelForPhase(ModelPhase.capable), opus);
        expect(await repository.getModelForPhase(ModelPhase.execution), opus);
      },
    );

    test(
      'setModelForPhase then getModelForPhase round-trips the value, '
      'independently per phase',
      () async {
        final repository = SharedPrefsModelRoutingRepository(registry);

        await repository.setModelForPhase(ModelPhase.frontier, sonnet);
        await repository.setModelForPhase(ModelPhase.execution, haiku);

        expect(
          await repository.getModelForPhase(ModelPhase.frontier),
          sonnet,
        );
        expect(await repository.getModelForPhase(ModelPhase.capable), opus);
        expect(
          await repository.getModelForPhase(ModelPhase.execution),
          haiku,
        );
      },
    );

    test(
      'getModelForPhase falls back to the legacy single-model key when a '
      "phase's own key isn't set, without writing anything",
      () async {
        SharedPreferences.setMockInitialValues({
          'agent_settings.selected_model_id': sonnet.modelId,
        });
        final repository = SharedPrefsModelRoutingRepository(registry);

        expect(
          await repository.getModelForPhase(ModelPhase.frontier),
          sonnet,
        );
        expect(
          await repository.getModelForPhase(ModelPhase.capable),
          sonnet,
        );
        expect(
          await repository.getModelForPhase(ModelPhase.execution),
          sonnet,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('model_routing.frontier_model_id'), isNull);
      },
    );

    test(
      "a phase's own persisted value takes priority over the legacy key",
      () async {
        SharedPreferences.setMockInitialValues({
          'agent_settings.selected_model_id': sonnet.modelId,
        });
        final repository = SharedPrefsModelRoutingRepository(registry);
        await repository.setModelForPhase(ModelPhase.frontier, haiku);

        expect(
          await repository.getModelForPhase(ModelPhase.frontier),
          haiku,
        );
      },
    );

    test(
      'getModelForPhase falls back to the first registered model for an '
      'unrecognized stored id (e.g. a since-removed model)',
      () async {
        SharedPreferences.setMockInitialValues({
          'model_routing.capable_model_id': 'claude-some-retired-model',
        });
        final repository = SharedPrefsModelRoutingRepository(registry);

        expect(await repository.getModelForPhase(ModelPhase.capable), opus);
      },
    );

    test(
      'pre-migration data with a model id but no provider id key still '
      'resolves under ProviderId.claudeAgentSdk',
      () async {
        SharedPreferences.setMockInitialValues({
          'model_routing.execution_model_id': haiku.modelId,
        });
        final repository = SharedPrefsModelRoutingRepository(registry);

        expect(
          await repository.getModelForPhase(ModelPhase.execution),
          haiku,
        );
      },
    );

    test(
      'setModelForPhase persists both the provider id and model id keys',
      () async {
        final repository = SharedPrefsModelRoutingRepository(registry);
        await repository.setModelForPhase(ModelPhase.capable, sonnet);

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('model_routing.capable_provider_id'),
          sonnet.providerId.name,
        );
        expect(
          prefs.getString('model_routing.capable_model_id'),
          sonnet.modelId,
        );
      },
    );
  });
}
