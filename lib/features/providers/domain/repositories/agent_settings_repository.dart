// domain/repositories/agent_settings_repository.dart — AgentSettingsRepository interface (domain layer).

import 'package:aion/features/providers/domain/enums/agent_model.dart';

/// Persists the user's selected [AgentModel] — a single, global (not
/// per-project) setting, since provider identity isn't a per-project
/// concept. Plain reads/writes only — no validation (validation belongs in
/// `ProviderSettingsCubit`, per `project.md`'s Cubit-vs-repository split).
/// Implemented by the data layer (`SharedPrefsAgentSettingsRepository`);
/// UI and domain code depend only on this interface, never on a concrete
/// data source.
abstract interface class AgentSettingsRepository {
  /// Returns the currently selected [AgentModel], defaulting to
  /// [AgentModel.sonnet] if none has been saved yet.
  Future<AgentModel> getSelectedModel();

  /// Persists [model] as the selected model.
  Future<void> setSelectedModel(AgentModel model);
}
