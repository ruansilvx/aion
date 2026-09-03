// presentation/cubit/execution_scheduling_cubit.dart — ExecutionSchedulingCubit business logic (presentation layer).

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';
import 'package:aion/features/providers/domain/repositories/execution_scheduling_repository.dart';
import 'package:aion/features/providers/presentation/cubit/execution_scheduling_state.dart';

/// Business logic for the Settings screen's "Coding execution scheduling"
/// section: loads the persisted [ExecutionSchedulingMode]/concurrency
/// ceiling and persists changes to either. Kept separate from
/// `ExecutionContextCapCubit`/`AutomationSettingsCubit` — one cubit per
/// concern, per `project.md`'s Cubit-vs-repository split. Added for
/// `AIO-1400`; see that change's design.md §6.
class ExecutionSchedulingCubit extends Cubit<ExecutionSchedulingState> {
  /// Creates an [ExecutionSchedulingCubit] backed by [_repository].
  ExecutionSchedulingCubit(this._repository)
    : super(const ExecutionSchedulingLoading());

  final ExecutionSchedulingRepository _repository;

  /// Loads the persisted mode and concurrency ceiling and emits
  /// [ExecutionSchedulingReady].
  Future<void> load() async {
    final mode = await _repository.getMode();
    final ceiling = await _repository.getConcurrencyCeiling();
    if (isClosed) return;
    emit(ExecutionSchedulingReady(mode: mode, concurrencyCeiling: ceiling));
  }

  /// Persists [mode] as the scheduling mode and re-emits
  /// [ExecutionSchedulingReady], preserving the current concurrency
  /// ceiling. No-ops if [state] isn't already [ExecutionSchedulingReady].
  Future<void> selectMode(ExecutionSchedulingMode mode) async {
    final current = state;
    if (current is! ExecutionSchedulingReady) return;
    await _repository.setMode(mode);
    if (isClosed) return;
    emit(
      ExecutionSchedulingReady(
        mode: mode,
        concurrencyCeiling: current.concurrencyCeiling,
      ),
    );
  }

  /// Persists [ceiling] as the concurrency ceiling and re-emits
  /// [ExecutionSchedulingReady], preserving the current mode. Clamped to
  /// at least `1` — a ceiling below `1` would never let anything start.
  /// No-ops if [state] isn't already [ExecutionSchedulingReady].
  Future<void> setConcurrencyCeiling(int ceiling) async {
    final current = state;
    if (current is! ExecutionSchedulingReady) return;
    final clamped = ceiling < 1 ? 1 : ceiling;
    await _repository.setConcurrencyCeiling(clamped);
    if (isClosed) return;
    emit(
      ExecutionSchedulingReady(mode: current.mode, concurrencyCeiling: clamped),
    );
  }
}
