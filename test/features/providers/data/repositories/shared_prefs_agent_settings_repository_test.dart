import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/providers/data/repositories/shared_prefs_agent_settings_repository.dart';
import 'package:aion/features/providers/domain/enums/agent_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsAgentSettingsRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getSelectedModel defaults to AgentModel.sonnet when unset', () async {
      final repository = SharedPrefsAgentSettingsRepository();

      expect(await repository.getSelectedModel(), AgentModel.sonnet);
    });

    test('setSelectedModel then getSelectedModel round-trips the value', () async {
      final repository = SharedPrefsAgentSettingsRepository();

      await repository.setSelectedModel(AgentModel.opus);

      expect(await repository.getSelectedModel(), AgentModel.opus);
    });

    test(
      'getSelectedModel falls back to the default for an unrecognized '
      'stored id (e.g. a since-removed model)',
      () async {
        SharedPreferences.setMockInitialValues({
          'agent_settings.selected_model_id': 'claude-some-retired-model',
        });
        final repository = SharedPrefsAgentSettingsRepository();

        expect(await repository.getSelectedModel(), AgentModel.sonnet);
      },
    );
  });
}
