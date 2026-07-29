// presentation/cubit/execution_context_cap_state.dart — ExecutionContextCapState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

/// The state emitted by `ExecutionContextCapCubit`.
sealed class ExecutionContextCapState extends Equatable {
  const ExecutionContextCapState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before `ExecutionContextCapCubit.load` resolves.
class ExecutionContextCapLoading extends ExecutionContextCapState {
  /// Creates an [ExecutionContextCapLoading] state.
  const ExecutionContextCapLoading();
}

/// Loaded — carries the persisted override and the execution-phase
/// model's real default, so the Settings row can show "effective cap: N
/// tokens" without reaching into `ModelRoutingRepository` directly.
class ExecutionContextCapReady extends ExecutionContextCapState {
  /// Creates an [ExecutionContextCapReady] state carrying [overrideTokens]
  /// and [modelDefaultTokens].
  const ExecutionContextCapReady({
    required this.overrideTokens,
    required this.modelDefaultTokens,
  });

  /// The persisted override, or `null` if none is set.
  final int? overrideTokens;

  /// The execution-phase model's real `AgentModel.contextWindowTokens`.
  final int modelDefaultTokens;

  @override
  List<Object?> get props => [overrideTokens, modelDefaultTokens];
}
