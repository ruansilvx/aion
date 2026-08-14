// data/repositories/shared_prefs_execution_scheduling_repository.dart — SharedPrefsExecutionSchedulingRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/providers/domain/enums/execution_scheduling_mode.dart';
import 'package:aion/features/providers/domain/repositories/execution_scheduling_repository.dart';

/// `shared_preferences`-backed implementation of
/// [ExecutionSchedulingRepository]. Two keys
/// (`execution_scheduling.mode`/`execution_scheduling.concurrency_ceiling`),
/// mirroring `SharedPrefsExecutionContextCapRepository`'s one-key-per-concept
/// shape. Defaults to [ExecutionSchedulingMode.strictFifo]/`2` when
/// nothing has been saved yet.
class SharedPrefsExecutionSchedulingRepository
    implements ExecutionSchedulingRepository {
  static const _modeKey = 'execution_scheduling.mode';
  static const _concurrencyCeilingKey =
      'execution_scheduling.concurrency_ceiling';

  /// Default concurrency ceiling when none has been persisted yet.
  static const _defaultConcurrencyCeiling = 2;

  @override
  Future<ExecutionSchedulingMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString(_modeKey);
    return ExecutionSchedulingMode.values.firstWhere(
      (mode) => mode.name == storedName,
      orElse: () => ExecutionSchedulingMode.strictFifo,
    );
  }

  @override
  Future<void> setMode(ExecutionSchedulingMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  @override
  Future<int> getConcurrencyCeiling() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_concurrencyCeilingKey) ?? _defaultConcurrencyCeiling;
  }

  @override
  Future<void> setConcurrencyCeiling(int ceiling) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_concurrencyCeilingKey, ceiling);
  }
}
