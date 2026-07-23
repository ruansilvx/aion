// domain/repositories/model_routing_repository.dart — ModelRoutingRepository abstract interface (domain layer).

import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';

/// Persists which [AgentModel] each [ModelPhase] currently resolves to.
/// Replaces `AgentSettingsRepository` (removed by
/// `aion-arch/changes/per-phase-tier-based-model-routing`) — a single
/// global model selection no longer exists, only a per-phase one. Plain
/// reads/writes only, no validation — any [AgentModel] value is valid for
/// any [ModelPhase], per `project.md`'s Cubit-vs-repository convention.
abstract interface class ModelRoutingRepository {
  /// The currently configured [AgentModel] for [phase].
  Future<AgentModel> getModelForPhase(ModelPhase phase);

  /// Persists [model] as [phase]'s selection.
  Future<void> setModelForPhase(ModelPhase phase, AgentModel model);
}
