// presentation/cubit/execution_context_cap_cubit.dart — ExecutionContextCapCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/providers/domain/enums/model_phase.dart';
import 'package:aion/features/providers/domain/repositories/execution_context_cap_repository.dart';
import 'package:aion/features/providers/domain/repositories/model_routing_repository.dart';
import 'package:aion/features/providers/presentation/cubit/execution_context_cap_state.dart';

/// Business logic for the Settings screen's "Execution Context Cap" row:
/// loads the persisted override (if any) alongside the execution-phase
/// model's real context-window limit, and persists changes to the
/// override. Kept separate from `ModelRoutingCubit`/
/// `AutomationSettingsCubit` — one cubit per concern, per `project.md`'s
/// Cubit-vs-repository split.
class ExecutionContextCapCubit extends Cubit<ExecutionContextCapState> {
  /// Creates an [ExecutionContextCapCubit] backed by [_capRepository] and
  /// [_modelRoutingRepository].
  ExecutionContextCapCubit(this._capRepository, this._modelRoutingRepository)
    : super(const ExecutionContextCapLoading());

  final ExecutionContextCapRepository _capRepository;
  final ModelRoutingRepository _modelRoutingRepository;

  /// Loads the persisted override and the execution-phase
  /// `AgentModelDescriptor`'s real `contextWindowTokens`, and emits
  /// [ExecutionContextCapReady].
  Future<void> load() async {
    final override = await _capRepository.getContextCapOverride();
    final model = await _modelRoutingRepository.getModelForPhase(
      ModelPhase.execution,
    );
    if (isClosed) return;
    emit(
      ExecutionContextCapReady(
        overrideTokens: override,
        modelDefaultTokens: model.contextWindowTokens,
      ),
    );
  }

  /// Persists [tokens] as the override, clamped to at most one below the
  /// current execution model's real `contextWindowTokens` (an override
  /// can lower the cap, never raise or match it past the real limit) and
  /// at least `1`; `null`/`<= 0` clears the override entirely.
  Future<void> setOverride(int? tokens) async {
    final current = state;
    final ceiling = current is ExecutionContextCapReady
        ? current.modelDefaultTokens
        : (await _modelRoutingRepository.getModelForPhase(
            ModelPhase.execution,
          )).contextWindowTokens;
    final clamped = (tokens == null || tokens <= 0)
        ? null
        : tokens.clamp(1, ceiling - 1);
    await _capRepository.setContextCapOverride(clamped);
    if (isClosed) return;
    emit(
      ExecutionContextCapReady(
        overrideTokens: clamped,
        modelDefaultTokens: ceiling,
      ),
    );
  }
}
