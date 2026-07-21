// data/repositories/shared_prefs_agent_settings_repository.dart — SharedPrefsAgentSettingsRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/repositories/agent_settings_repository.dart';

/// `shared_preferences`-backed implementation of [AgentSettingsRepository].
/// Stores [AgentModel.id] under a single string key — no
/// `flutter_secure_storage` needed, since nothing secret is stored (Agent
/// SDK auth lives entirely in the user's existing Claude plan credentials,
/// outside Aion's control).
class SharedPrefsAgentSettingsRepository implements AgentSettingsRepository {
  static const _selectedModelKey = 'agent_settings.selected_model_id';

  @override
  Future<AgentModel> getSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString(_selectedModelKey);
    return AgentModel.values.firstWhere(
      (model) => model.id == storedId,
      orElse: () => AgentModel.sonnet,
    );
  }

  @override
  Future<void> setSelectedModel(AgentModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, model.id);
  }
}
