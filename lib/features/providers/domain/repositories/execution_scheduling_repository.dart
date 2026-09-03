// domain/repositories/execution_scheduling_repository.dart — ExecutionSchedulingRepository interface (domain layer).

import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';

/// Persists the user's coding-execution scheduling choice — see
/// `ExecutionSchedulingCubit` and `AIO-1400` §6. Plain reads/writes only, no
/// validation.
abstract interface class ExecutionSchedulingRepository {
  /// The persisted [ExecutionSchedulingMode], defaulting to
  /// [ExecutionSchedulingMode.strictFifo] if none has been saved yet —
  /// today's shipped behavior stays the default for every existing user.
  Future<ExecutionSchedulingMode> getMode();

  /// Persists [mode] as the scheduling mode.
  Future<void> setMode(ExecutionSchedulingMode mode);

  /// The persisted concurrency ceiling, defaulting to `2` if none has
  /// been saved yet. Only meaningful under
  /// [ExecutionSchedulingMode.parallel]/[ExecutionSchedulingMode.hybrid]
  /// — ignored under [ExecutionSchedulingMode.strictFifo].
  Future<int> getConcurrencyCeiling();

  /// Persists [ceiling] as the concurrency ceiling.
  Future<void> setConcurrencyCeiling(int ceiling);
}
