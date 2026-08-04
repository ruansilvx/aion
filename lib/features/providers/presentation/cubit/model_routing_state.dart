// presentation/cubit/model_routing_state.dart — ModelRoutingState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';

/// The state emitted by `ModelRoutingCubit`.
sealed class ModelRoutingState extends Equatable {
  const ModelRoutingState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before `ModelRoutingCubit.load` resolves.
class ModelRoutingLoading extends ModelRoutingState {
  /// Creates a [ModelRoutingLoading] state.
  const ModelRoutingLoading();
}

/// Loaded — carries the persisted [AgentModelDescriptor] selection for
/// every [ModelPhase], plus the models each phase's dropdown may offer.
class ModelRoutingReady extends ModelRoutingState {
  /// Creates a [ModelRoutingReady] state carrying [modelByPhase] and
  /// [availableModels].
  const ModelRoutingReady(this.modelByPhase, this.availableModels);

  /// The currently selected [AgentModelDescriptor] for each [ModelPhase],
  /// keyed rather than split into named fields — same reasoning as
  /// `AutomationSettingsReady.confidenceByContext`: a future phase slots
  /// in with no state-shape change.
  final Map<ModelPhase, AgentModelDescriptor> modelByPhase;

  /// Every [AgentModelDescriptor] a MODELS-tier dropdown may currently
  /// offer, keyed by [ModelPhase] — filtered by which registered
  /// providers support that phase's `ModelPhaseToolAccess.requiredToolAccessTier`.
  final Map<ModelPhase, List<AgentModelDescriptor>> availableModels;

  @override
  List<Object?> get props => [modelByPhase, availableModels];
}
