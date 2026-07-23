// presentation/cubit/model_routing_cubit.dart — ModelRoutingCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/providers/domain/enums/agent_model.dart';
import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/providers/presentation/cubit/model_routing_state.dart';

/// Business logic for the Settings screen's "MODELS" section: loads the
/// persisted [AgentModel] for every [ModelPhase] and persists changes to
/// any one of them. Kept separate from `ProviderSettingsCubit`/
/// `AutomationSettingsCubit` since the three concerns (provider
/// connection, automation confidence, model routing) are unrelated — one
/// cubit per concern, per `project.md`'s Cubit-vs-repository split.
class ModelRoutingCubit extends Cubit<ModelRoutingState> {
  /// Creates a [ModelRoutingCubit] backed by [_repository].
  ModelRoutingCubit(this._repository) : super(const ModelRoutingLoading());

  final ModelRoutingRepository _repository;

  /// Loads the persisted [AgentModel] for every [ModelPhase] and emits
  /// [ModelRoutingReady].
  Future<void> load() async {
    final results = await Future.wait(
      ModelPhase.values.map(_repository.getModelForPhase),
    );
    if (isClosed) return;
    emit(ModelRoutingReady(Map.fromIterables(ModelPhase.values, results)));
  }

  /// Persists [model] as [phase]'s new selection and re-emits
  /// [ModelRoutingReady] with that entry updated.
  Future<void> selectModel(ModelPhase phase, AgentModel model) async {
    await _repository.setModelForPhase(phase, model);
    if (isClosed) return;
    final current = state;
    final updated = current is ModelRoutingReady
        ? Map<ModelPhase, AgentModel>.of(current.modelByPhase)
        : <ModelPhase, AgentModel>{};
    updated[phase] = model;
    emit(ModelRoutingReady(updated));
  }
}
