// data/repositories/shared_prefs_model_routing_repository.dart — SharedPrefsModelRoutingRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/provider_id.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';

/// `shared_preferences`-backed implementation of [ModelRoutingRepository].
/// Stores two keys per [ModelPhase] now — `..._provider_id` and
/// `..._model_id` — resolving the persisted pair back into a full
/// [AgentModelDescriptor] via [_registry]. A phase with no persisted
/// `..._provider_id` key yet (pre-migration data, from before this
/// change) defaults to [ProviderId.claudeAgentSdk] — today's only
/// provider — so an already-chosen model survives, mirroring
/// [SharedPrefsAutomationSettingsRepository]'s precedent of preserving
/// `AutomationContext.sddStage`'s pre-generalization key. The legacy
/// single-model key `SharedPrefsAgentSettingsRepository` used
/// (`agent_settings.selected_model_id`, read only, never written here) is
/// still consulted as a further fallback for `..._model_id`, preserving
/// the pre-per-phase-routing precedent this repository already carried.
/// No `flutter_secure_storage` — nothing secret is stored, same reasoning
/// as the repository this replaces.
class SharedPrefsModelRoutingRepository implements ModelRoutingRepository {
  /// Creates a [SharedPrefsModelRoutingRepository] backed by [_registry]
  /// to resolve persisted provider/model ids back into full
  /// [AgentModelDescriptor]s.
  SharedPrefsModelRoutingRepository(this._registry);

  final ProviderRegistry _registry;

  static const _frontierProviderKey = 'model_routing.frontier_provider_id';
  static const _frontierModelKey = 'model_routing.frontier_model_id';
  static const _capableProviderKey = 'model_routing.capable_provider_id';
  static const _capableModelKey = 'model_routing.capable_model_id';
  static const _executionProviderKey = 'model_routing.execution_provider_id';
  static const _executionModelKey = 'model_routing.execution_model_id';

  /// The legacy single-model key, read as a fallback default only.
  static const _legacySelectedModelKey = 'agent_settings.selected_model_id';

  String _providerKeyFor(ModelPhase phase) => switch (phase) {
    ModelPhase.frontier => _frontierProviderKey,
    ModelPhase.capable => _capableProviderKey,
    ModelPhase.execution => _executionProviderKey,
  };

  String _modelKeyFor(ModelPhase phase) => switch (phase) {
    ModelPhase.frontier => _frontierModelKey,
    ModelPhase.capable => _capableModelKey,
    ModelPhase.execution => _executionModelKey,
  };

  @override
  Future<AgentModelDescriptor> getModelForPhase(ModelPhase phase) async {
    final prefs = await SharedPreferences.getInstance();
    final providerName = prefs.getString(_providerKeyFor(phase));
    final providerId = ProviderId.values.firstWhere(
      (p) => p.name == providerName,
      orElse: () => ProviderId.claudeAgentSdk,
    );
    final modelId =
        prefs.getString(_modelKeyFor(phase)) ??
        prefs.getString(_legacySelectedModelKey);
    final provider = _registry.providerById(providerId);
    return provider.availableModels.firstWhere(
      (m) => m.modelId == modelId,
      orElse: () => provider.availableModels.first,
    );
  }

  @override
  Future<void> setModelForPhase(
    ModelPhase phase,
    AgentModelDescriptor model,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerKeyFor(phase), model.providerId.name);
    await prefs.setString(_modelKeyFor(phase), model.modelId);
  }
}
