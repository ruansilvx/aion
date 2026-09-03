// presentation/cubit/in_flight_execution_run.dart — InFlightExecutionRun helper (presentation layer).

import 'package:aion/core/contracts/agent_provider.dart';

/// One coding-execution Task/Bug's currently-in-flight model turn, as tracked
/// by `TicketsCubit._inFlightRuns` — pairs the turn's own `runId` (regenerated
/// fresh for every implement/verify turn) with the [AgentProvider] it's
/// running against, so `TicketsCubit .cancelCodingExecution` can resolve
/// `provider.client.cancel(runId)` without re-deriving either from scratch.
/// See `AIO-1400` §5.1.
class InFlightExecutionRun {
  /// Creates an [InFlightExecutionRun] pairing [runId] with [provider].
  InFlightExecutionRun(this.runId, this.provider);

  /// The current turn's `AgentRequest.runId`.
  final String runId;

  /// The [AgentProvider] this turn is running against — its `client` is
  /// what `AgentModelClient.cancel` is actually called on.
  final AgentProvider provider;
}
