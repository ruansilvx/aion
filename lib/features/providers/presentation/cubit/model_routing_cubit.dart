// presentation/cubit/model_routing_cubit.dart — ModelRoutingCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/core/contracts/agent_model_descriptor.dart';
import 'package:aion/core/contracts/provider_registry.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/providers/presentation/cubit/model_routing_state.dart';

/// Business logic for the Settings screen's "MODELS" section: loads the
/// persisted [AgentModelDescriptor] for every [ModelPhase] (plus which
/// models each phase's dropdown may offer, via [_registry]) and persists
/// changes to any one of them. Kept separate from `ProviderSettingsCubit`/
/// `AutomationSettingsCubit` since the three concerns (provider
/// connection, automation confidence, model routing) are unrelated — one
/// cubit per concern, per `project.md`'s Cubit-vs-repository split.
class ModelRoutingCubit extends Cubit<ModelRoutingState> {
  /// Creates a [ModelRoutingCubit] backed by [_repository] and
  /// [_registry].
  ModelRoutingCubit(this._repository, this._registry)
    : super(const ModelRoutingLoading());

  final ModelRoutingRepository _repository;
  final ProviderRegistry _registry;

  /// Loads the persisted [AgentModelDescriptor] for every [ModelPhase],
  /// plus — per phase — the union of `availableModels` across every
  /// registered provider whose `AgentProvider.supportedToolAccessTiers`
  /// covers that phase's `ModelPhaseToolAccess.requiredToolAccessTier`.
  /// Emits [ModelRoutingReady].
  Future<void> load() async {
    final results = await Future.wait(
      ModelPhase.values.map(_repository.getModelForPhase),
    );
    if (isClosed) return;
    emit(
      ModelRoutingReady(
        Map.fromIterables(ModelPhase.values, results),
        _computeAvailableModels(),
      ),
    );
  }

  /// Persists [model] as [phase]'s new selection and re-emits
  /// [ModelRoutingReady] with that entry updated.
  Future<void> selectModel(ModelPhase phase, AgentModelDescriptor model) async {
    await _repository.setModelForPhase(phase, model);
    if (isClosed) return;
    final current = state;
    final updatedModelByPhase = current is ModelRoutingReady
        ? Map<ModelPhase, AgentModelDescriptor>.of(current.modelByPhase)
        : <ModelPhase, AgentModelDescriptor>{};
    updatedModelByPhase[phase] = model;
    emit(
      ModelRoutingReady(
        updatedModelByPhase,
        current is ModelRoutingReady
            ? current.availableModels
            : _computeAvailableModels(),
      ),
    );
  }

  /// Builds, per [ModelPhase], the deduplicated union of `availableModels`
  /// across every provider in [_registry] whose `supportedToolAccessTiers`
  /// contains that phase's `requiredToolAccessTier`.
  Map<ModelPhase, List<AgentModelDescriptor>> _computeAvailableModels() {
    return {
      for (final phase in ModelPhase.values)
        phase: [
          for (final provider in _registry.availableProviders)
            if (provider.supportedToolAccessTiers.contains(
              phase.requiredToolAccessTier,
            ))
              ...provider.availableModels,
        ],
    };
  }
}
