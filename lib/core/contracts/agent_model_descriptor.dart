// core/contracts/agent_model_descriptor.dart — AgentModelDescriptor value object (core layer).

import 'package:equatable/equatable.dart';

import 'package:aion/core/contracts/provider_id.dart';

/// A provider-scoped model. Replaces the old `AgentModel` enum as the
/// value object every model selection/routing surface uses — a model is
/// no longer implicitly "the one provider's model." See
/// `AIO-1544` §1.
class AgentModelDescriptor extends Equatable {
  /// Creates an [AgentModelDescriptor].
  const AgentModelDescriptor({
    required this.providerId,
    required this.modelId,
    required this.label,
    required this.contextWindowTokens,
  });

  /// Which [ProviderId] offers this model.
  final ProviderId providerId;

  /// The identifier passed as `AgentRequest.model` (was `AgentModel.id`).
  final String modelId;

  /// Human-readable label for the Settings model dropdown.
  final String label;

  /// The model's real context window, in tokens.
  final int contextWindowTokens;

  @override
  List<Object?> get props => [providerId, modelId, label, contextWindowTokens];
}
