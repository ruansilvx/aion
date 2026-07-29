// domain/repositories/execution_context_cap_repository.dart — ExecutionContextCapRepository abstract interface (domain layer).

/// Persists a user-configurable override for the coding-execution
/// context-window handoff cap (see
/// `TicketsCubit._effectiveExecutionContextCap`). `null` means "no
/// override — use the execution-phase model's real
/// `AgentModel.contextWindowTokens`." Plain reads/writes only, no
/// validation — `TicketsCubit`/`ExecutionContextCapCubit` are responsible
/// for never persisting a value at or above the model's real limit.
abstract interface class ExecutionContextCapRepository {
  /// The persisted override, or `null` if none is set.
  Future<int?> getContextCapOverride();

  /// Persists [tokens] as the override. `null` clears it.
  Future<void> setContextCapOverride(int? tokens);
}
