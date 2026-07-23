// presentation/cubit/model_routing_state.dart — ModelRoutingState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/providers/domain/enums/agent_model.dart';
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

/// Loaded — carries the persisted [AgentModel] selection for every
/// [ModelPhase].
class ModelRoutingReady extends ModelRoutingState {
  /// Creates a [ModelRoutingReady] state carrying [modelByPhase].
  const ModelRoutingReady(this.modelByPhase);

  /// The currently selected [AgentModel] for each [ModelPhase], keyed
  /// rather than split into named fields — same reasoning as
  /// `AutomationSettingsReady.confidenceByContext`: a future phase slots
  /// in with no state-shape change.
  final Map<ModelPhase, AgentModel> modelByPhase;

  @override
  List<Object?> get props => [modelByPhase];
}
