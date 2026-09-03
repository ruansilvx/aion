// domain/repositories/model_routing_repository.dart — ModelRoutingRepository abstract interface (domain layer).

import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';

/// Persists which [AgentModelDescriptor] each [ModelPhase] currently
/// resolves to. Replaces `AgentSettingsRepository` (removed by
/// `AIO-1491`) — a single
/// global model selection no longer exists, only a per-phase one. Plain
/// reads/writes only, no validation — any [AgentModelDescriptor] value is
/// valid for any [ModelPhase], per `project.md`'s Cubit-vs-repository
/// convention.
abstract interface class ModelRoutingRepository {
  /// The currently configured [AgentModelDescriptor] for [phase].
  Future<AgentModelDescriptor> getModelForPhase(ModelPhase phase);

  /// Persists [model] as [phase]'s selection.
  Future<void> setModelForPhase(ModelPhase phase, AgentModelDescriptor model);
}
