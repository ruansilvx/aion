// domain/enums/execution_scheduling_mode.dart — ExecutionSchedulingMode enum (domain layer).

/// How `TicketsCubit` schedules coding-execution runs (Task/Bug tickets
/// moving to `TicketStatus.inProgress`) against each other. Persisted via
/// `ExecutionSchedulingRepository`, defaulting to [strictFifo] — today's
/// shipped, unchanged behavior. See
/// `aion-arch/changes/parallel-work/design.md` §1.
enum ExecutionSchedulingMode {
  /// One coding-execution run at a time, FIFO — today's shipped behavior.
  /// Every other queued Task/Bug waits regardless of scheduling capacity.
  strictFifo,

  /// Up to the configured concurrency ceiling may run at once, with no
  /// regard for shared parents — two Tasks/Bugs under the same Story may
  /// run concurrently against each other.
  parallel,

  /// Like [parallel], but Tasks/Bugs sharing a parent Story never run
  /// concurrently against each other — same-parent siblings serialize
  /// automatically, while unrelated tickets still run in parallel up to
  /// the concurrency ceiling.
  hybrid,
}
