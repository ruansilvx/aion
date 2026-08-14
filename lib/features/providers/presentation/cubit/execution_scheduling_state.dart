// presentation/cubit/execution_scheduling_state.dart — ExecutionSchedulingState sealed hierarchy (presentation layer).

import 'package:equatable/equatable.dart';

import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';

/// The state emitted by `ExecutionSchedulingCubit`.
sealed class ExecutionSchedulingState extends Equatable {
  const ExecutionSchedulingState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before `ExecutionSchedulingCubit.load` resolves.
class ExecutionSchedulingLoading extends ExecutionSchedulingState {
  /// Creates an [ExecutionSchedulingLoading] state.
  const ExecutionSchedulingLoading();
}

/// Loaded — carries the persisted scheduling mode and concurrency
/// ceiling, so the Settings row can render both without a second
/// repository read.
class ExecutionSchedulingReady extends ExecutionSchedulingState {
  /// Creates an [ExecutionSchedulingReady] state carrying [mode] and
  /// [concurrencyCeiling].
  const ExecutionSchedulingReady({
    required this.mode,
    required this.concurrencyCeiling,
  });

  /// The persisted scheduling mode.
  final ExecutionSchedulingMode mode;

  /// The persisted concurrency ceiling — meaningful only under
  /// [ExecutionSchedulingMode.parallel]/[ExecutionSchedulingMode.hybrid].
  final int concurrencyCeiling;

  @override
  List<Object?> get props => [mode, concurrencyCeiling];
}
