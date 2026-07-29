// data/repositories/shared_prefs_execution_context_cap_repository.dart — SharedPrefsExecutionContextCapRepository (data layer).

import 'package:shared_preferences/shared_preferences.dart';

import 'package:aion/features/providers/domain/repositories/execution_context_cap_repository.dart';

/// `shared_preferences`-backed implementation of
/// [ExecutionContextCapRepository]. One key
/// (`execution_context_cap.override_tokens`), mirroring
/// `SharedPrefsModelRoutingRepository`'s one-key-per-concept shape. Setting
/// `null` removes the key entirely, same as clearing an override.
class SharedPrefsExecutionContextCapRepository
    implements ExecutionContextCapRepository {
  static const _overrideKey = 'execution_context_cap.override_tokens';

  @override
  Future<int?> getContextCapOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_overrideKey);
  }

  @override
  Future<void> setContextCapOverride(int? tokens) async {
    final prefs = await SharedPreferences.getInstance();
    if (tokens == null) {
      await prefs.remove(_overrideKey);
    } else {
      await prefs.setInt(_overrideKey, tokens);
    }
  }
}
