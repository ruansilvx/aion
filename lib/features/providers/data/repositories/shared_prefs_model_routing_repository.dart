// data/repositories/shared_prefs_model_routing_repository.dart — SharedPrefsModelRoutingRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';

/// `shared_preferences`-backed implementation of [ModelRoutingRepository].
/// Stores [AgentModel.id] under one string key per [ModelPhase]. A phase
/// with no persisted value yet falls back to the pre-existing single-model
/// key `SharedPrefsAgentSettingsRepository` used
/// (`agent_settings.selected_model_id`, read only, never written here) so
/// an already-chosen model survives into all three tiers the first time
/// this repository runs, instead of silently resetting to
/// [AgentModel.sonnet] — mirrors
/// `SharedPrefsAutomationSettingsRepository`'s precedent of preserving
/// `AutomationContext.sddStage`'s pre-generalization key. No
/// `flutter_secure_storage` — nothing secret is stored, same reasoning as
/// the repository this replaces.
class SharedPrefsModelRoutingRepository implements ModelRoutingRepository {
  static const _frontierKey = 'model_routing.frontier_model_id';
  static const _capableKey = 'model_routing.capable_model_id';
  static const _executionKey = 'model_routing.execution_model_id';

  /// The legacy single-model key, read as a fallback default only.
  static const _legacySelectedModelKey = 'agent_settings.selected_model_id';

  String _keyFor(ModelPhase phase) => switch (phase) {
    ModelPhase.frontier => _frontierKey,
    ModelPhase.capable => _capableKey,
    ModelPhase.execution => _executionKey,
  };

  @override
  Future<AgentModel> getModelForPhase(ModelPhase phase) async {
    final prefs = await SharedPreferences.getInstance();
    final storedId =
        prefs.getString(_keyFor(phase)) ??
        prefs.getString(_legacySelectedModelKey);
    return AgentModel.values.firstWhere(
      (model) => model.id == storedId,
      orElse: () => AgentModel.sonnet,
    );
  }

  @override
  Future<void> setModelForPhase(ModelPhase phase, AgentModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(phase), model.id);
  }
}
